import { execFile, spawn } from 'node:child_process';
import { accessSync, chmodSync, constants, existsSync, mkdirSync, readdirSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import type { StoredKey } from './store.js';

const VITRIN_DATA = process.env.VITRIN_HOME ?? join(process.env.XDG_DATA_HOME ?? join(homedir(), '.local', 'share'), 'vitrin');

function loginPath(): Promise<string | undefined> {
  const shell = process.env.SHELL ?? '/bin/zsh';
  return new Promise((ok) => {
    execFile(shell, ['-lic', 'printf %s "$PATH"'], { timeout: 8000 }, (err, stdout) => ok(err ? undefined : stdout.split('\n').at(-1)));
  });
}

let cached: NodeJS.ProcessEnv | undefined;

/**
 * The user's environment. Whatever starts the hub is usually an app with a bare PATH, so node, asc, ffmpeg and claude
 * are found through the login shell once, then passed to everything the hub runs (the Mac app's ShellEnvironment).
 */
export async function shellEnv(): Promise<NodeJS.ProcessEnv> {
  if (cached) return cached;
  const home = homedir();
  const dirs = ((await loginPath()) ?? process.env.PATH ?? '/usr/bin:/bin:/usr/sbin:/sbin').split(':').filter(Boolean);
  const extra = ['/opt/homebrew/bin', '/usr/local/bin', join(home, '.local', 'bin'), join(VITRIN_DATA, 'bin'), join(VITRIN_DATA, 'node', 'bin')];
  try {
    const nvm = join(home, '.nvm', 'versions', 'node');
    extra.push(...readdirSync(nvm).sort((a, b) => b.localeCompare(a, undefined, { numeric: true })).map((v) => join(nvm, v, 'bin')));
  } catch {
    /* no nvm */
  }
  for (const dir of extra) if (!dirs.includes(dir) && existsSync(dir)) dirs.push(dir);
  cached = { ...process.env, PATH: dirs.join(':'), NO_COLOR: '1', FORCE_COLOR: '0', BROWSER: 'none' };
  return cached;
}

/** After an install: the next lookup sees the new tool. */
export function forgetShellEnv(): void {
  cached = undefined;
}

export async function which(tool: string): Promise<string | undefined> {
  const env = await shellEnv();
  for (const dir of (env.PATH ?? '').split(':')) {
    const file = join(dir, tool);
    try {
      accessSync(file, constants.X_OK);
      return file;
    } catch {
      /* next */
    }
  }
  return undefined;
}

export interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

export function run(cmd: string, args: string[], opts: { env?: NodeJS.ProcessEnv; cwd?: string; timeoutMs?: number } = {}): Promise<RunResult> {
  return new Promise((ok) => {
    const child = spawn(cmd, args, { env: opts.env, cwd: opts.cwd ?? tmpdir(), stdio: ['ignore', 'pipe', 'pipe'] });
    const out: Buffer[] = [];
    const err: Buffer[] = [];
    child.stdout.on('data', (d: Buffer) => out.push(d));
    child.stderr.on('data', (d: Buffer) => err.push(d));
    const timer = setTimeout(() => child.kill('SIGTERM'), opts.timeoutMs ?? 180_000);
    const done = (code: number) => {
      clearTimeout(timer);
      ok({ code, stdout: Buffer.concat(out).toString('utf8'), stderr: Buffer.concat(err).toString('utf8') });
    };
    child.on('error', (e) => {
      err.push(Buffer.from(e.message));
      done(127);
    });
    child.on('close', (code, signal) => done(code ?? (signal ? 124 : 1)));
  });
}

/** The environment of an asc run: Vitrin's key when there is one, else nothing (asc uses its own login). */
export function ascAuthEnv(key: StoredKey | undefined): NodeJS.ProcessEnv {
  if (!key) return {};
  return { ASC_KEY_ID: key.keyId, ASC_ISSUER_ID: key.issuerId, ASC_PRIVATE_KEY_PATH: key.keyPath, ASC_KEY_TYPE: 'team', ASC_PRIVATE_KEY_B64: '', ASC_PRIVATE_KEY: '', ASC_PROFILE: '' };
}

/** Runs `asc <args>`. Read-only unless told otherwise: asc then refuses every POST, PATCH, PUT and DELETE. */
export async function runAsc(args: string[], key: StoredKey | undefined, opts: { write?: boolean; timeoutMs?: number; env?: NodeJS.ProcessEnv } = {}): Promise<RunResult> {
  const bin = await which('asc');
  if (!bin) return { code: 127, stdout: '', stderr: 'asc is not installed on this Mac.' };
  const env = { ...(await shellEnv()), ...ascAuthEnv(key), ASC_READ_ONLY: opts.write ? '0' : '1', ...opts.env };
  return run(bin, args, { env, timeoutMs: opts.timeoutMs });
}

/**
 * The Apple Ads API key pair: an EC (prime256v1) key whose private half stays in Vitrin's folder, in the file Vitrin
 * for Mac uses, because `asc ads auth login` takes a path. Made once; the public half is what Apple Ads asks for.
 */
export async function adsKeyPair(base: string): Promise<{ publicKey: string; privateKey: string }> {
  const folder = join(base, 'keys');
  const privateKey = join(folder, 'apple-ads-private.pem');
  mkdirSync(folder, { recursive: true, mode: 0o700 });
  if (!existsSync(privateKey)) {
    const made = await run('/usr/bin/openssl', ['ecparam', '-genkey', '-name', 'prime256v1', '-noout', '-out', privateKey]);
    if (made.code !== 0) throw new Error(made.stderr.trim() || 'The key pair could not be made.');
    chmodSync(privateKey, 0o600);
  }
  const pub = await run('/usr/bin/openssl', ['ec', '-in', privateKey, '-pubout']);
  if (pub.code !== 0) throw new Error(pub.stderr.trim() || 'The public key could not be read.');
  return { publicKey: pub.stdout.trim(), privateKey };
}

/** Installs a missing tool on the Mac the way the Mac app does when Homebrew is there. */
export async function installTool(tool: string): Promise<RunResult> {
  const env = await shellEnv();
  let result: RunResult;
  if (tool === 'claude') {
    const npm = await which('npm');
    if (!npm) return { code: 127, stdout: '', stderr: 'npm is not installed on this Mac.' };
    result = await run(npm, ['install', '-g', '--no-fund', '--no-audit', '@anthropic-ai/claude-code'], { env, timeoutMs: 600_000 });
  } else if (tool === 'asc' || tool === 'ffmpeg') {
    const brew = await which('brew');
    if (!brew) return { code: 127, stdout: '', stderr: 'Homebrew is not installed. Open Vitrin for Mac on this Mac: it installs this tool without Homebrew.' };
    result = await run(brew, ['install', tool], { env: { ...env, HOMEBREW_NO_ENV_HINTS: '1' }, timeoutMs: 900_000 });
  } else {
    return { code: 2, stdout: '', stderr: `Unknown tool: ${tool}` };
  }
  forgetShellEnv();
  return result;
}

