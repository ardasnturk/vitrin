import { execFile } from 'node:child_process';
import { existsSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { describe, expect, it } from 'vitest';
import { STUDIO_RUN_ENV, studioRunRefusal, USER_ONLY_COMMANDS } from '../src/context.js';
import { ALLOWED_TOOLS, DISALLOWED_TOOLS } from '../src/studio/claude.js';

/**
 * The fence around a Claude run the Studio starts: the prompt and the tool rules say "never upload, approve, submit,
 * finalize or init", and the CLI makes it so. The child carries VITRIN_STUDIO_RUN=1; these commands refuse to run under it.
 */

const BIN = join(fileURLToPath(new URL('.', import.meta.url)), '..', 'dist', 'bin.js');
const run = promisify(execFile);
const REFUSAL = "is the user's command: run it from the Studio";

async function vitrin(cwd: string, studioRun: boolean, ...args: string[]): Promise<{ code: number; out: string }> {
  const env: NodeJS.ProcessEnv = { ...process.env, ASC_KEY_ID: '', ASC_ISSUER_ID: '', ASC_KEY_PATH: '', ASC_KEY_CONTENT_BASE64: '' };
  delete env[STUDIO_RUN_ENV];
  if (studioRun) env[STUDIO_RUN_ENV] = '1';
  try {
    const r = await run('node', [BIN, ...args], { cwd, env });
    return { code: 0, out: r.stdout + r.stderr };
  } catch (err) {
    const e = err as { code: number; stdout: string; stderr: string };
    return { code: e.code, out: e.stdout + e.stderr };
  }
}

function project(): string {
  const dir = mkdtempSync(join(tmpdir(), 'vitrin-fence-'));
  writeFileSync(join(dir, 'vitrin.config.yaml'), 'app:\n  bundleId: com.example.app\n  locales: [en-US]\nurls: {}\n');
  return dir;
}

describe('studioRunRefusal', () => {
  const marked = { [STUDIO_RUN_ENV]: '1' };

  it('refuses the user-only commands under the mark and nothing else', () => {
    for (const c of USER_ONLY_COMMANDS) expect(studioRunRefusal(c, {}, marked)).toContain(`vitrin ${c} ${REFUSAL}`);
    for (const c of ['analyze', 'write', 'design', 'validate', 'review', 'all', 'doctor']) expect(studioRunRefusal(c, {}, marked)).toBeUndefined();
  });

  it('leaves upload --dry-run open: it prints the plan and changes nothing', () => {
    expect(studioRunRefusal('upload', { dryRun: true }, marked)).toBeUndefined();
    expect(studioRunRefusal('upload', { dryRun: false }, marked)).toBeDefined();
  });

  it('does nothing without the mark', () => {
    for (const c of USER_ONLY_COMMANDS) expect(studioRunRefusal(c, {}, {})).toBeUndefined();
    expect(studioRunRefusal('upload', {}, { [STUDIO_RUN_ENV]: '' })).toBeUndefined();
  });
});

describe('vitrin under VITRIN_STUDIO_RUN', () => {
  it.each([
    ['upload', '--yes'],
    ['approve'],
    ['submit', '--confirm', 'com.example.app'],
    ['finalize', '--checked', '--keep-research'],
    ['init'],
    ['studio', '--no-open'],
  ])('refuses `vitrin %s` with exit 1 before it does anything', async (...args) => {
    const dir = project();
    const res = await vitrin(dir, true, ...args);
    expect(res.code).toBe(1);
    expect(res.out).toContain(`vitrin ${args[0]} ${REFUSAL}`);
    expect(existsSync(join(dir, 'metadata'))).toBe(false);
  }, 60_000);

  it('refuses the command however the global options are placed', async () => {
    const dir = project();
    const res = await vitrin(dir, true, '-C', dir, '--force', 'upload', '--yes');
    expect(res.code).toBe(1);
    expect(res.out).toContain(`vitrin upload ${REFUSAL}`);
  }, 60_000);

  it('lets upload --dry-run through to the usual checks', async () => {
    const res = await vitrin(project(), true, 'upload', '--dry-run');
    expect(res.out).not.toContain(REFUSAL);
  }, 60_000);

  it('changes nothing without the mark', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'vitrin-fence-'));
    const res = await vitrin(dir, false, 'init');
    expect(res.code).toBe(0);
    expect(res.out).not.toContain(REFUSAL);
    expect(existsSync(join(dir, 'vitrin.config.yaml'))).toBe(true);
  }, 60_000);
});

describe('the tool rules of a Studio run', () => {
  it('allow vitrin, ls and the media tools in Bash, and no shell that can read or send files', () => {
    expect(ALLOWED_TOOLS).toEqual(expect.arrayContaining(['Read', 'Edit', 'Write', 'Glob', 'Grep', 'MultiEdit', 'Skill', 'Bash(vitrin:*)', 'Bash(ls:*)', 'Bash(ffmpeg:*)', 'Bash(ffprobe:*)']));
    expect(ALLOWED_TOOLS).not.toContain('Bash(cat:*)');
    expect(ALLOWED_TOOLS).not.toContain('Bash(open:*)');
    expect(ALLOWED_TOOLS.filter((t) => t.startsWith('Bash('))).toEqual(['Bash(vitrin:*)', 'Bash(ls:*)', 'Bash(ffmpeg:*)', 'Bash(ffprobe:*)']);
  });

  it("deny the user's commands, the global-option escape, git, the web and the secrets", () => {
    for (const c of ['upload', 'approve', 'submit', 'finalize', 'init', 'studio']) expect(DISALLOWED_TOOLS).toContain(`Bash(vitrin ${c}:*)`);
    // `vitrin -C . upload` and `vitrin --cwd . upload` start with "vitrin -": one rule covers every global option placed first
    // (no space before the `*`: `:*` would need one and miss `-C`).
    expect(DISALLOWED_TOOLS).toContain('Bash(vitrin -*)');
    expect(DISALLOWED_TOOLS).toEqual(expect.arrayContaining(['Bash(git:*)', 'WebFetch', 'WebSearch']));
    // A Read deny also covers Edit and Write on the same path.
    expect(DISALLOWED_TOOLS).toEqual(expect.arrayContaining(['Read(.env*)', 'Read(**/.env*)', 'Read(**/*.p8)', 'Read(**/secrets/**)']));
  });
});
