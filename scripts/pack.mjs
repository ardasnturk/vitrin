#!/usr/bin/env node
// Builds the publishable `@ardasnturk/vitrin` npm package and packs it into <out>/ardasnturk-vitrin-<version>.tgz.
//
// The package holds one bundled CLI (dist/bin.js: packages/cli with every internal @vitrin/* workspace package
// inlined by esbuild), the runtime files the code reads from disk (data/, the Remotion
// sources that @remotion/bundler compiles at render time, the Swift OCR script), LICENSE and README.
// Third-party packages (sharp, playwright, remotion, @remotion/*, fonts, zod, …) stay real `dependencies`
// with the same version ranges as the workspace packages declare.
//
// Usage: node scripts/pack.mjs [--out <dir>] [--write-sums]   (needs `pnpm build` first; `pnpm pack:release` does both)
//
// The tarball's checksum is the SHA-256 of the gunzipped tar: the tar is byte-identical on every machine that builds
// the same commit (npm pack fixes mtimes and owners), while the gzip layer differs between Node versions. The plugin's
// launcher verifies a downloaded release against the entry for its version in plugins/vitrin/SHA256SUMS, which
// `--write-sums` (`pnpm release:checksum`) records; the release workflow refuses to publish a tarball that does not match.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';
import { build } from 'esbuild';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PKG_NAME = '@ardasnturk/vitrin';
const readJson = (file) => JSON.parse(readFileSync(file, 'utf8'));

const argv = process.argv.slice(2);
const outIdx = argv.indexOf('--out');
const writeSums = argv.includes('--write-sums');
const SUMS = join(ROOT, 'plugins', 'vitrin', 'SHA256SUMS');
const OUT = resolve(outIdx >= 0 && argv[outIdx + 1] ? argv[outIdx + 1] : join(ROOT, 'release'));
const STAGE = join(OUT, 'package');

const rootPkg = readJson(join(ROOT, 'package.json'));
const version = rootPkg.version;
const cliEntry = join(ROOT, 'packages', 'cli', 'dist', 'bin.js');
if (!existsSync(cliEntry)) {
  console.error('packages/cli/dist/bin.js is missing: run `pnpm build` first (or `pnpm pack:release`).');
  process.exit(1);
}

// 1. Third-party dependencies of every workspace package, with the ranges they declare today.
const workspace = readdirSync(join(ROOT, 'packages'))
  .map((d) => join(ROOT, 'packages', d, 'package.json'))
  .filter(existsSync)
  .map(readJson);
const internal = new Set(workspace.map((p) => p.name));
const dependencies = {};
for (const p of workspace) {
  for (const [name, range] of Object.entries(p.dependencies ?? {})) {
    if (internal.has(name)) continue;
    if (dependencies[name] && dependencies[name] !== range) {
      throw new Error(`${name} is declared as ${dependencies[name]} and ${range} in different workspace packages; align them first.`);
    }
    dependencies[name] = range;
  }
}
const sortedDeps = Object.fromEntries(Object.entries(dependencies).sort(([a], [b]) => a.localeCompare(b)));

// 2. Bundle the CLI: internal packages inlined, third-party packages external.
rmSync(STAGE, { recursive: true, force: true });
mkdirSync(STAGE, { recursive: true });
const result = await build({
  entryPoints: [cliEntry],
  outfile: join(STAGE, 'dist', 'bin.js'),
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node22',
  external: Object.keys(dependencies).flatMap((name) => [name, `${name}/*`]),
  metafile: true,
  logLevel: 'warning',
});
const strays = Object.keys(result.metafile.inputs).filter((f) => f.split(/[\\/]/).includes('node_modules'));
if (strays.length) {
  throw new Error(`Undeclared third-party code was bundled (add it to a workspace package's dependencies):\n  ${strays.join('\n  ')}`);
}

// 3. Runtime files, at the same paths relative to dist/ as in the monorepo:
//    - core finds data/ by walking up from dist/ to the folder with data/targets.json;
//    - video bundles <dist>/../src/remotion/index.ts; research runs <dist>/../scripts/ocr.swift.
const copy = (from, to) => cpSync(join(ROOT, from), join(STAGE, to), { recursive: true });
for (const f of readdirSync(join(ROOT, 'data')).filter((f) => f.endsWith('.json'))) copy(join('data', f), join('data', f));
// The native UI kit Claude's HTML screens link to (copied into metadata/screens/kit/ by `vitrin capture`).
for (const f of readdirSync(join(ROOT, 'data', 'screen-kit'))) copy(join('data', 'screen-kit', f), join('data', 'screen-kit', f));
copy('packages/video/src/remotion', 'src/remotion');
copy('packages/video/src/types.ts', 'src/types.ts');
copy('packages/research/scripts/ocr.swift', 'scripts/ocr.swift');
// The Studio UI (`vitrin studio`), prebuilt by packages/studio/build.mjs; the server looks for <pkg>/studio/index.html.
if (!existsSync(join(ROOT, 'packages', 'studio', 'dist', 'index.html'))) {
  console.error('packages/studio/dist is missing: run `pnpm build` first (it builds the Studio UI too).');
  process.exit(1);
}
copy('packages/studio/dist', 'studio');
copy('LICENSE', 'LICENSE');
copy('scripts/npm-readme.md', 'README.md');

const pkg = {
  name: PKG_NAME,
  version,
  description: 'Vitrin CLI: App Store Connect metadata, HTML-rendered screenshots and Remotion App Previews, driven by the /vitrin Claude Code skill',
  type: 'module',
  bin: { vitrin: 'dist/bin.js' },
  files: ['dist', 'data', 'src', 'scripts', 'studio'],
  engines: { node: '>=22' },
  dependencies: sortedDeps,
  keywords: ['app-store', 'app-store-connect', 'aso', 'screenshots', 'app-preview', 'remotion', 'ios', 'claude-code'],
  author: rootPkg.author,
  license: rootPkg.license,
  homepage: rootPkg.homepage,
  bugs: rootPkg.bugs,
  repository: rootPkg.repository,
};
writeFileSync(join(STAGE, 'package.json'), `${JSON.stringify(pkg, null, 2)}\n`);

// 4. npm pack → <out>/ardasnturk-vitrin-<version>.tgz
const packed = JSON.parse(execFileSync('npm', ['pack', '--json', '--pack-destination', OUT], { cwd: STAGE, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] }))[0];
const tarball = join(OUT, packed.filename);
const mb = (n) => `${(n / 1024 / 1024).toFixed(2)} MB`;
console.log(`${relative(process.cwd(), tarball) || tarball}: ${packed.entryCount} files, ${mb(packed.size)} packed, ${mb(packed.unpackedSize)} unpacked`);

// 5. The checksum the launcher verifies (see the header), as a SHA256SUMS line for the gunzipped tar.
export function tarSha256(tgz) {
  return createHash('sha256').update(gunzipSync(readFileSync(tgz))).digest('hex');
}
/** Replaces or adds the line for `name` in a SHA256SUMS text (`<sha256>  <name>`), keeping the others. */
export function withSum(text, sha256, name) {
  const lines = text.split('\n').filter((l) => l.trim() && !l.endsWith(`  ${name}`));
  return [...lines, `${sha256}  ${name}`].join('\n') + '\n';
}
const sumName = `ardasnturk-vitrin-${version}.tar`;
const sum = tarSha256(tarball);
console.log(`${sum}  ${sumName}  (SHA-256 of the gunzipped tar; the plugin's launcher checks it)`);
if (writeSums) {
  writeFileSync(SUMS, withSum(existsSync(SUMS) ? readFileSync(SUMS, 'utf8') : '', sum, sumName));
  console.log(`recorded in ${relative(process.cwd(), SUMS)}`);
}
if (process.env.GITHUB_OUTPUT) writeFileSync(process.env.GITHUB_OUTPUT, `tarball=${tarball.split(sep).join('/')}\nsha256=${sum}\nsum_name=${sumName}\n`, { flag: 'a' });
