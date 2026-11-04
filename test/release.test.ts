import { execFile, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { accessSync, chmodSync, constants, cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { promisify } from 'node:util';
import { gunzipSync } from 'node:zlib';
import { afterAll, describe, expect, it } from 'vitest';

const ROOT = resolve(import.meta.dirname, '..');
const readJson = (p: string) => JSON.parse(readFileSync(join(ROOT, p), 'utf8'));
const version: string = readJson('package.json').version;
const CLI = join(ROOT, 'packages', 'cli', 'dist', 'bin.js');
const LAUNCHER = join(ROOT, 'plugins', 'vitrin', 'bin', 'vitrin');
const SUMS = join(ROOT, 'plugins', 'vitrin', 'SHA256SUMS');
/** The checksum the launcher verifies: the SHA-256 of the gunzipped tar (the gzip layer differs between Node versions). */
const tarSha256 = (tgz: string) => createHash('sha256').update(gunzipSync(readFileSync(tgz))).digest('hex');

describe('release version (root package.json is the single source)', () => {
  it('is mirrored by the plugin, the marketplace entry and every workspace package', () => {
    expect(version).toMatch(/^\d+\.\d+\.\d+$/);
    expect(readJson('plugins/vitrin/.claude-plugin/plugin.json').version).toBe(version);
    const market = readJson('.claude-plugin/marketplace.json');
    const entry = market.plugins.find((p: { name: string }) => p.name === 'vitrin');
    expect(entry.source).toBe('./plugins/vitrin');
    expect(entry.version).toBe(version);
    for (const dir of readdirSync(join(ROOT, 'packages'))) {
      const file = join('packages', dir, 'package.json');
      if (existsSync(join(ROOT, file))) expect(`${file}@${readJson(file).version}`).toBe(`${file}@${version}`);
    }
  });

  it('has CHANGELOG notes for the version (the GitHub Release body)', async () => {
    // @ts-expect-error plain .mjs script without type declarations
    const { releaseNotes } = (await import('../scripts/release-notes.mjs')) as { releaseNotes: (c: string, v: string) => string };
    const notes = releaseNotes(readFileSync(join(ROOT, 'CHANGELOG.md'), 'utf8'), version);
    expect(notes.length).toBeGreaterThan(0);
    expect(notes).not.toMatch(/^## /m);
    const sample = '# Changelog\n\n## 1.1.0 — 2026-01-02\n\n- b\n\n## 1.0.0 — 2026-01-01\n\n- a\n';
    expect(releaseNotes(sample, '1.1.0')).toBe('- b');
    expect(releaseNotes(sample, '1.0.0')).toBe('- a');
    expect(releaseNotes(sample, '1.0')).toBe('');
  });

  it.skipIf(!existsSync(CLI))('vitrin --version prints it', () => {
    expect(execFileSync(process.execPath, [CLI, '--version'], { encoding: 'utf8' }).trim()).toBe(version);
  });
});

describe('Claude Code plugin', () => {
  it('ships the /vitrin skill and an executable POSIX launcher', () => {
    const skill = readFileSync(join(ROOT, 'plugins', 'vitrin', 'skills', 'vitrin', 'SKILL.md'), 'utf8');
    expect(skill).toMatch(/^---\nname: vitrin\n/);
    expect(skill).not.toMatch(/git clone/);
    accessSync(LAUNCHER, constants.X_OK);
    execFileSync('sh', ['-n', LAUNCHER]);
    const launcher = readFileSync(LAUNCHER, 'utf8');
    expect(launcher.startsWith('#!/bin/sh\n')).toBe(true);
    // The release workflow uploads exactly this asset name.
    expect(launcher).toContain('releases/download/v$version/ardasnturk-vitrin-$version.tgz');
    expect(launcher).toContain('node_modules/@ardasnturk/vitrin/dist/bin.js');
  });

  it('records the checksum of every released tarball (SHA-256 of the gunzipped tar) the launcher verifies', () => {
    const lines = readFileSync(SUMS, 'utf8').split('\n').filter(Boolean);
    expect(lines.length).toBeGreaterThan(0);
    for (const l of lines) expect(l).toMatch(/^[0-9a-f]{64}  ardasnturk-vitrin-\d+\.\d+\.\d+\.tar$/);
    const names = lines.map((l) => l.split('  ')[1]);
    expect(new Set(names).size).toBe(names.length);
    // 1.0.0 is the release asset on GitHub, hashed after a download; the same tag built here gives the same tar.
    expect(lines).toContain('41fab6003c6d2bdafe7bf977e1f509701424a3c24d2c7c16c149aea6fd75e35c  ardasnturk-vitrin-1.0.0.tar');
  });
});

describe('launcher install', () => {
  // A tiny stand-in for @ardasnturk/vitrin (no dependencies), served over HTTP like a GitHub release asset.
  const tmp = mkdtempSync(join(tmpdir(), 'vitrin-launcher-'));
  const VERSION = '0.0.1';
  let server: Server;
  let url: string;
  let tgz: string;
  const plugin = join(tmp, 'plugin');

  const setup = () => {
    const pkg = join(tmp, 'pkg');
    mkdirSync(join(pkg, 'dist'), { recursive: true });
    writeFileSync(join(pkg, 'package.json'), JSON.stringify({ name: '@ardasnturk/vitrin', version: VERSION, bin: { vitrin: 'dist/bin.js' }, files: ['dist'] }));
    writeFileSync(join(pkg, 'dist', 'bin.js'), '#!/usr/bin/env node\nconsole.log("stand-in " + process.argv.slice(2).join(" "));\n');
    const packed = JSON.parse(execFileSync('npm', ['pack', '--json', '--pack-destination', tmp], { cwd: pkg, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }))[0] as { filename: string };
    tgz = join(tmp, packed.filename);
    mkdirSync(join(plugin, 'bin'), { recursive: true });
    mkdirSync(join(plugin, '.claude-plugin'), { recursive: true });
    cpSync(LAUNCHER, join(plugin, 'bin', 'vitrin'));
    chmodSync(join(plugin, 'bin', 'vitrin'), 0o755);
    writeFileSync(join(plugin, '.claude-plugin', 'plugin.json'), JSON.stringify({ name: 'vitrin', version: VERSION }, null, 2));
  };

  const serve = () =>
    new Promise<void>((ok) => {
      server = createServer((req, res) => {
        if (req.url === '/release.tgz') {
          res.writeHead(200, { 'content-type': 'application/octet-stream' });
          res.end(readFileSync(tgz));
        } else {
          res.writeHead(404);
          res.end();
        }
      }).listen(0, '127.0.0.1', () => {
        url = `http://127.0.0.1:${(server.address() as AddressInfo).port}/release.tgz`;
        ok();
      });
    });

  // The launcher downloads from the server in this process, so it must run asynchronously (a sync spawn would block the server).
  const launch = async (env: Record<string, string>): Promise<{ status: number; stdout: string; stderr: string }> => {
    try {
      const r = await promisify(execFile)('sh', [join(plugin, 'bin', 'vitrin'), '--version'], { encoding: 'utf8', env: { ...process.env, VITRIN_SKIP_BROWSER: '1', ...env } });
      return { status: 0, ...r };
    } catch (err) {
      const e = err as { code?: number; stdout?: string; stderr?: string };
      return { status: typeof e.code === 'number' ? e.code : 1, stdout: e.stdout ?? '', stderr: e.stderr ?? '' };
    }
  };
  const run = (home: string, sums: string | undefined, env: Record<string, string> = {}) => {
    if (sums === undefined) rmSync(join(plugin, 'SHA256SUMS'), { force: true });
    else writeFileSync(join(plugin, 'SHA256SUMS'), sums);
    return launch({ VITRIN_HOME: home, VITRIN_TARBALL: url, ...env });
  };

  afterAll(async () => {
    await new Promise<void>((ok) => (server ? server.close(() => ok()) : ok()));
    rmSync(tmp, { recursive: true, force: true });
  });

  it('downloads, verifies the checksum and installs once; refuses a tarball that does not match', async () => {
    setup();
    await serve();
    const sum = tarSha256(tgz);
    const good = `${sum}  ardasnturk-vitrin-${VERSION}.tar\n`;

    // The right checksum: installed, then run; the second run skips the install.
    const home = join(tmp, 'home-ok');
    let r = await run(home, good);
    expect(r.status, r.stderr).toBe(0);
    expect(r.stdout.trim()).toBe('stand-in --version');
    expect(r.stderr).toContain('checksum verified');
    expect(existsSync(join(home, VERSION, '.vitrin-installed'))).toBe(true);
    r = await run(home, good);
    expect(r.status).toBe(0);
    expect(r.stderr).not.toContain('installing');

    // A different checksum: nothing is installed, the message names both values.
    const bad = join(tmp, 'home-bad');
    r = await run(bad, `${'0'.repeat(64)}  ardasnturk-vitrin-${VERSION}.tar\n`);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('checksum mismatch');
    expect(r.stderr).toContain(sum);
    expect(existsSync(join(bad, VERSION))).toBe(false);
    expect(readdirSync(bad).filter((f) => f.endsWith('.tgz'))).toEqual([]);

    // No entry for the version: refused for the default release URL, installed with a warning for VITRIN_TARBALL.
    const none = join(tmp, 'home-none');
    r = await run(none, `${sum}  ardasnturk-vitrin-9.9.9.tar\n`);
    expect(r.status).toBe(0);
    expect(r.stderr).toContain('unverified');
  }, 120_000);

  it('refuses the official release when the plugin records no checksum for its version', async () => {
    // VITRIN_TARBALL unset: the launcher would download from GitHub, but it must stop before that when the entry is missing.
    const home = join(tmp, 'home-missing');
    writeFileSync(join(plugin, 'SHA256SUMS'), `${'0'.repeat(64)}  ardasnturk-vitrin-${VERSION}.tar\n`);
    const r = await launch({ VITRIN_HOME: home, VITRIN_TARBALL: '', VITRIN_VERSION: '9.9.9' });
    // (A download of v9.9.9 fails too; either way nothing may be installed and the message must name the checksum file.)
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/SHA256SUMS|download failed/);
    expect(existsSync(join(home, '9.9.9'))).toBe(false);
  }, 60_000);
});

describe.skipIf(!existsSync(CLI))('packed @ardasnturk/vitrin tarball', () => {
  const out = mkdtempSync(join(tmpdir(), 'vitrin-pack-'));
  afterAll(() => rmSync(out, { recursive: true, force: true }));

  it('contains the bundled CLI and every runtime file the code reads from disk', () => {
    execFileSync(process.execPath, [join(ROOT, 'scripts', 'pack.mjs'), '--out', out], { stdio: 'pipe' });
    const tgz = join(out, `ardasnturk-vitrin-${version}.tgz`);
    expect(existsSync(tgz)).toBe(true);
    const files = execFileSync('tar', ['-tzf', tgz], { encoding: 'utf8' })
      .split('\n')
      .filter(Boolean)
      .map((f) => f.replace(/^package\//, ''));
    const expected = [
      'package.json',
      'README.md',
      'LICENSE',
      'dist/bin.js',
      'scripts/ocr.swift',
      'src/types.ts',
      ...readdirSync(join(ROOT, 'data')).filter((f) => f.endsWith('.json')).map((f) => `data/${f}`),
      ...readdirSync(join(ROOT, 'data', 'screen-kit')).map((f) => `data/screen-kit/${f}`),
      ...readdirSync(join(ROOT, 'packages', 'video', 'src', 'remotion')).map((f) => `src/remotion/${f}`),
      // The Studio UI (`vitrin studio`), prebuilt into packages/studio/dist by `pnpm build`.
      ...readdirSync(join(ROOT, 'packages', 'studio', 'dist')).map((f) => `studio/${f}`),
    ];
    expect(files).toContain('studio/index.html');
    expect(files).toContain('studio/studio.js');
    expect(files.sort()).toEqual([...new Set(expected)].sort());

    const pkg = JSON.parse(readFileSync(join(out, 'package', 'package.json'), 'utf8'));
    expect(pkg).toMatchObject({ name: '@ardasnturk/vitrin', version, bin: { vitrin: 'dist/bin.js' }, engines: { node: '>=22' } });
    const deps = Object.keys(pkg.dependencies);
    expect(deps.filter((d) => d.startsWith('@vitrin/'))).toEqual([]);
    for (const d of ['sharp', 'playwright', 'remotion', '@remotion/bundler', '@remotion/renderer', 'react', 'zod', 'yaml', 'commander', 'lucide-static', '@fontsource-variable/inter']) {
      expect(deps).toContain(d);
    }
    // Same ranges as the workspace packages declare today.
    expect(pkg.dependencies.sharp).toBe(readJson('packages/render/package.json').dependencies.sharp);
    expect(pkg.dependencies.remotion).toBe(readJson('packages/video/package.json').dependencies.remotion);

    const bin = readFileSync(join(out, 'package', 'dist', 'bin.js'), 'utf8');
    expect(bin.startsWith('#!/usr/bin/env node')).toBe(true);
    expect(bin).not.toMatch(/from ['"]@vitrin\//);
  }, 120_000);
});
