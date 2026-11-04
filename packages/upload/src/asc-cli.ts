import { addSecret, ensureDir, exec, existsSync, log, writeText, type AppPaths } from '@vitrin/core';
import { copyFile, readdir, readFile, rm } from 'node:fs/promises';
import { basename, extname, isAbsolute, join, resolve } from 'node:path';
import { AscApiError, AscClient } from './asc-client.js';
import { classicTypeFor } from './display-types.js';
import { isActive, type UploadPlan } from './plan.js';
import { ASC_PLATFORM, type AppStorePlatform, type RenderedAsset } from './platforms.js';
import { perDisplayTypeAssetsFor } from './scope.js';

export type CommandRunner = typeof exec;

export interface AscInvocation {
  command: string;
  args: string[];
  env: Record<string, string>;
}

/**
 * Vitrin's App Store uploader: drives the `asc` CLI (https://github.com/rorkai/App-Store-Connect-CLI, MIT,
 * `brew install asc`). Every command is built by a pure function below; the runner
 * is injected (tests never run the binary).
 *
 * - Text: `asc metadata push --app <id> --version <v> --platform <IOS|MAC_OS|TV_OS|VISION_OS> --dir <dir>` with
 *   `--dry-run` for the plan. asc's canonical layout (internal/cli/metadata/foundation.go: `app-info/<locale>.json`
 *   and `version/<version>/<locale>.json`) is generated from Vitrin's metadata/store/metadata export.
 * - Media: one `asc screenshots upload` / `asc video-previews upload --version-localization <id> --path <dir>
 *   --device-type <type> --replace --confirm` per locale and display type: `--replace` deletes only the screenshots
 *   of that one set, so other display types stay untouched.
 * - Auth, two sources (see `ascEnv`):
 *   1. Vitrin's key (.env or the app's global key: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH | ASC_KEY_CONTENT_BASE64)
 *      is mapped to asc's documented environment credential (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_TYPE=team and one
 *      of ASC_PRIVATE_KEY_PATH / ASC_PRIVATE_KEY_B64; a complete environment set makes asc skip its stored lookup,
 *      and ASC_PROFILE is cleared so a selected profile cannot win). Values go only into the child's environment,
 *      never into arguments or logs.
 *   2. No Vitrin key at all: nothing is overridden and asc uses its own stored authentication (`asc auth login`:
 *      the keychain or ~/.asc/config.json profile, or ASC_PROFILE from the user's shell). `asc auth status --output
 *      json` tells whether such a credential exists (`ascStoredAuth`). Vitrin's own ASC API calls (plan, App Asset
 *      Library, read-back) then go through `asc api` too (`ascCliClient`), so no key file is needed anywhere.
 *   A partial Vitrin key (e.g. ASC_KEY_ID without the .p8) is an error, never a silent fallback.
 */

export const ASC_BIN = 'asc';
export const ASC_INSTALL_HINT = 'brew install asc (https://github.com/rorkai/App-Store-Connect-CLI)';

export type AscPlatform = 'IOS' | 'MAC_OS' | 'TV_OS' | 'VISION_OS';

/** Where asc takes its credential from: Vitrin's key (mapped to asc's environment variables) or asc's own login. */
export type AscAuthSource = 'vitrin-key' | 'asc-login';

/**
 * asc's credential for a child process. With any of Vitrin's key variables set, the full key is mapped to asc's
 * environment credential and `problems` lists what is missing. With none set, `source` is `asc-login`: the env map
 * is empty (nothing is overridden) and asc falls back to its own stored authentication (`asc auth login`).
 */
export function ascEnv(env: NodeJS.ProcessEnv, root: string): { env: Record<string, string>; problems: string[]; source: AscAuthSource } {
  const problems: string[] = [];
  const keyId = env.ASC_KEY_ID?.trim();
  const issuer = env.ASC_ISSUER_ID?.trim();
  const b64 = env.ASC_KEY_CONTENT_BASE64?.trim();
  const path = env.ASC_KEY_PATH?.trim();
  if (!keyId && !issuer && !b64 && !path) return { env: {}, problems, source: 'asc-login' };
  if (!keyId) problems.push('ASC_KEY_ID is missing');
  if (!issuer) problems.push('ASC_ISSUER_ID is missing');
  if (!b64 && !path) problems.push('ASC_KEY_PATH (or ASC_KEY_CONTENT_BASE64) is missing');
  const out: Record<string, string> = {
    ASC_KEY_ID: keyId ?? '',
    ASC_ISSUER_ID: issuer ?? '',
    ASC_KEY_TYPE: 'team',
    // Exactly one private-key source; clear the others so a value in the user's shell cannot mix in.
    ASC_PRIVATE_KEY_PATH: '',
    ASC_PRIVATE_KEY_B64: '',
    ASC_PRIVATE_KEY: '',
    // A selected profile would win over the environment credential (authentication.mdx resolution matrix).
    ASC_PROFILE: '',
  };
  if (b64) {
    addSecret(b64);
    out.ASC_PRIVATE_KEY_B64 = b64;
  } else if (path) {
    const full = isAbsolute(path) ? path : resolve(root, path);
    if (!existsSync(full)) problems.push(`.p8 file not found: ${path}`);
    out.ASC_PRIVATE_KEY_PATH = full;
  }
  if (keyId) addSecret(keyId);
  if (issuer) addSecret(issuer);
  return { env: out, problems, source: 'vitrin-key' };
}

export function ascAuthStatusInvocation(): AscInvocation {
  return { command: ASC_BIN, args: ['auth', 'status', '--output', 'json'], env: {} };
}

/**
 * asc's own stored authentication (`asc auth login`), read with `asc auth status --output json` (never validated
 * over the network, never changed): `profiles` names the stored credentials, `env` is true when asc's own
 * environment variables form a complete credential. Null when asc is missing or the output is not understood.
 */
export async function ascStoredAuth(runner: CommandRunner = exec): Promise<{ profiles: string[]; defaultProfile?: string; env: boolean } | null> {
  const inv = ascAuthStatusInvocation();
  const res = await runner(inv.command, inv.args, { timeoutMs: 30_000 }).catch(() => ({ code: 127, stdout: '', stderr: '' }));
  if (res.code !== 0) return null;
  try {
    const doc = JSON.parse(res.stdout) as { credentials?: Array<{ name?: string; isDefault?: boolean }>; environmentCredentialsComplete?: boolean };
    const creds = Array.isArray(doc.credentials) ? doc.credentials : [];
    const profiles = creds.map((c) => c.name ?? '').filter(Boolean);
    return { profiles, defaultProfile: creds.find((c) => c.isDefault)?.name, env: Boolean(doc.environmentCredentialsComplete) };
  } catch {
    return null;
  }
}

/** True when asc can authenticate on its own (a stored profile or a complete asc environment credential). */
export async function ascHasOwnAuth(runner: CommandRunner = exec): Promise<boolean> {
  const s = await ascStoredAuth(runner);
  return Boolean(s && (s.profiles.length || s.env));
}

/** `asc api <METHOD> <path> --allow-unknown-path [--confirm --body-file -]`: one raw ASC API call through asc. */
export function ascApiInvocation(method: string, path: string, hasBody: boolean, env: Record<string, string>): AscInvocation {
  // Vitrin's paths come from the ASC API 4.5.1 spec; asc's embedded index can lag behind it (App Asset Library).
  const args = ['api', method, path, '--allow-unknown-path'];
  if (method !== 'GET') args.push('--confirm');
  if (hasBody) args.push('--body-file', '-');
  return { command: ASC_BIN, args, env };
}

/**
 * An AscClient whose requests go through `asc api` with asc's own authentication, for when Vitrin has no ASC key
 * (see the module comment). Same methods and paging as AscClient; asc retries on its own, and a failed call becomes
 * an AscApiError (status 0 when asc does not print one, 404 for “does not exist”).
 */
export class AscCliClient extends AscClient {
  constructor(
    private readonly runner: CommandRunner = exec,
    private readonly cwd?: string,
    private readonly childEnv: Record<string, string> = {},
  ) {
    super(undefined);
  }

  override async request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const inv = ascApiInvocation(method, path, body !== undefined, this.childEnv);
    const res = await this.runner(inv.command, inv.args, { cwd: this.cwd, env: inv.env, input: body !== undefined ? JSON.stringify(body) : undefined, timeoutMs: 300_000 });
    if (res.code === 127 || /ENOENT|command not found/i.test(res.stderr)) throw new Error(`asc is not installed: ${ASC_INSTALL_HINT}`);
    if (res.code !== 0) {
      const text = (res.stderr || res.stdout).trim().replace(/^Error:\s*(api:\s*)?/i, '');
      const status = Number(/\b(4\d\d|5\d\d)\b/.exec(text)?.[1] ?? (/does not exist|not found/i.test(text) ? 404 : 0));
      throw new AscApiError(status, path, [{ detail: text.split('\n')[0]?.slice(0, 300) || `asc exit ${res.code}` }]);
    }
    const out = res.stdout.trim();
    if (!out) return undefined as T;
    try {
      return JSON.parse(out) as T;
    } catch {
      throw new AscApiError(200, path, [{ detail: `asc api output is not JSON: ${out.slice(0, 300)}` }]);
    }
  }
}

/**
 * The client for Vitrin's own ASC API calls: Vitrin's key when one is set (`keyed`), else `asc api` with asc's own
 * login when asc has one, else undefined (remote state unknown).
 */
export async function ascClientFor(env: NodeJS.ProcessEnv, root: string, keyed: () => AscClient, runner: CommandRunner = exec): Promise<{ client?: AscClient; source?: AscAuthSource }> {
  const auth = ascEnv(env, root);
  if (auth.source === 'vitrin-key') return { client: keyed(), source: 'vitrin-key' };
  if (await ascHasOwnAuth(runner)) return { client: new AscCliClient(runner, root), source: 'asc-login' };
  return {};
}

export function ascVersionInvocation(): AscInvocation {
  return { command: ASC_BIN, args: ['version'], env: {} };
}

export function ascMetadataPushInvocation(o: { appId: string; version: string; platform: AscPlatform; dir: string; dryRun: boolean; confirm?: boolean }, env: Record<string, string>): AscInvocation {
  const args = ['metadata', 'push', '--app', o.appId, '--version', o.version, '--platform', o.platform, '--dir', o.dir];
  if (o.dryRun) args.push('--dry-run');
  // --confirm is required only for field clears (explicit null); it never enables deletes (that is --allow-deletes).
  else if (o.confirm) args.push('--confirm');
  return { command: ASC_BIN, args, env };
}

export function ascScreenshotsUploadInvocation(o: { localizationId: string; path: string; deviceType: string; dryRun?: boolean }, env: Record<string, string>): AscInvocation {
  const args = ['screenshots', 'upload', '--version-localization', o.localizationId, '--path', o.path, '--device-type', o.deviceType, '--replace'];
  args.push(o.dryRun ? '--dry-run' : '--confirm');
  return { command: ASC_BIN, args, env };
}

export function ascVideoPreviewsUploadInvocation(o: { localizationId: string; path: string; deviceType: string; dryRun?: boolean }, env: Record<string, string>): AscInvocation {
  const args = ['video-previews', 'upload', '--version-localization', o.localizationId, '--path', o.path, '--device-type', o.deviceType, '--replace'];
  args.push(o.dryRun ? '--dry-run' : '--confirm');
  return { command: ASC_BIN, args, env };
}

/** `asc versions create --app <id> --version <v> --platform <p> --if-exists skip` (`vitrin doctor --create-version`). */
export function ascVersionsCreateInvocation(o: { appId: string; version: string; platform: AscPlatform }, env: Record<string, string>): AscInvocation {
  return { command: ASC_BIN, args: ['versions', 'create', '--app', o.appId, '--version', o.version, '--platform', o.platform, '--if-exists', 'skip'], env };
}

/**
 * `asc review submit --app <id> --version-id <id> --platform <p> --latest --confirm`: attaches the newest App Store
 * eligible build of that version and submits it for review (`vitrin submit`, after the user's explicit yes).
 */
export function ascSubmitInvocation(o: { appId: string; versionId: string; platform: AscPlatform }, env: Record<string, string>): AscInvocation {
  return { command: ASC_BIN, args: ['review', 'submit', '--app', o.appId, '--version-id', o.versionId, '--platform', o.platform, '--latest', '--confirm'], env };
}

export function ascValidateInvocation(o: { appId: string; platform?: AscPlatform; version?: string }, env: Record<string, string>): AscInvocation {
  const args = ['validate', '--app', o.appId];
  if (o.version) args.push('--version', o.version);
  if (o.platform) args.push('--platform', o.platform);
  return { command: ASC_BIN, args, env };
}

// ---- metadata export: metadata/store/metadata → asc canonical layout ----

/** Store tree file → asc field, per scope. */
const APP_INFO_FIELDS: Record<string, string> = { 'name.txt': 'name', 'subtitle.txt': 'subtitle', 'privacy_url.txt': 'privacyPolicyUrl' };
const VERSION_FIELDS: Record<string, string> = {
  'description.txt': 'description',
  'keywords.txt': 'keywords',
  'marketing_url.txt': 'marketingUrl',
  'promotional_text.txt': 'promotionalText',
  'support_url.txt': 'supportUrl',
  'release_notes.txt': 'whatsNew',
};
/** asc supports an explicit `null` clear only for these (metadata.mdx, “Clearing nullable fields”). */
const ASC_CLEARABLE = new Set(['subtitle', 'privacyPolicyUrl', 'promotionalText']);
/** Store tree files that asc metadata push does not upload. */
const NOT_IN_ASC = ['copyright.txt', 'primary_category.txt', 'secondary_category.txt', 'primary_first_sub_category.txt', 'primary_second_sub_category.txt', 'secondary_first_sub_category.txt', 'secondary_second_sub_category.txt', 'review_information'];

export interface AscMetadataExport {
  dir: string;
  files: string[];
  /** Number of explicit `null` clears (the push then needs --confirm). */
  clears: number;
  warnings: string[];
}

/**
 * Writes `<dir>/app-info/<locale>.json` (when `includeAppInfo`) and `<dir>/version/<version>/<locale>.json` from the
 * store tree (metadata/store/metadata). A missing file means “leave the remote value”, so the key is omitted; an
 * empty file means “clear”, written as `null` where asc supports it.
 */
export async function exportAscMetadata(storeMetadata: string, dir: string, o: { locales: string[]; version: string; includeAppInfo: boolean; dropReleaseNotes?: boolean }): Promise<AscMetadataExport> {
  await rm(dir, { recursive: true, force: true });
  const out: AscMetadataExport = { dir, files: [], clears: 0, warnings: [] };
  for (const locale of o.locales) {
    const src = join(storeMetadata, locale);
    if (!existsSync(src)) continue;
    const scopes: Array<[Record<string, string>, string]> = [[VERSION_FIELDS, join(dir, 'version', o.version, `${locale}.json`)]];
    if (o.includeAppInfo) scopes.unshift([APP_INFO_FIELDS, join(dir, 'app-info', `${locale}.json`)]);
    for (const [fields, target] of scopes) {
      const doc: Record<string, string | null> = {};
      for (const [file, key] of Object.entries(fields)) {
        if (file === 'release_notes.txt' && o.dropReleaseNotes) continue;
        const f = join(src, file);
        if (!existsSync(f)) continue;
        const value = (await readFile(f, 'utf8')).trim();
        if (value) doc[key] = value;
        else if (ASC_CLEARABLE.has(key)) {
          doc[key] = null;
          out.clears++;
        } else out.warnings.push(`${locale} ${key}: asc cannot clear this field; the App Store Connect value stays.`);
      }
      if (!Object.keys(doc).length) continue;
      await writeText(target, JSON.stringify(doc, null, 2) + '\n');
      out.files.push(target);
    }
  }
  if (existsSync(storeMetadata)) {
    const root = await readdir(storeMetadata);
    const skipped = NOT_IN_ASC.filter((f) => root.includes(f));
    if (skipped.length) out.warnings.push(`asc metadata push does not upload ${skipped.join(', ')}; they stay as they are in App Store Connect (edit them there).`);
  }
  return out;
}

// ---- media jobs ----

export interface AscMediaJob {
  platform: AppStorePlatform;
  locale: string;
  kind: 'screenshot' | 'preview';
  /** ScreenshotDisplayType (APP_…) or PreviewType. */
  deviceType: string;
  targets: string[];
  files: string[];
}

/**
 * One job per (platform, locale, kind, classic display type) for the sets this run replaces. Targets without a
 * classic type (iPhone Duo) are left out: they go through the App Asset Library.
 */
export function ascMediaJobs(plan: UploadPlan, assets: RenderedAsset[], locales: string[]): AscMediaJob[] {
  const jobs = new Map<string, AscMediaJob>();
  for (const p of plan.platforms) {
    const ps = plan.scope?.apple.find((s) => s.platform === p.platform);
    if (!ps || !isActive(ps)) continue;
    const files = perDisplayTypeAssetsFor(ps, assets).filter((a) => locales.includes(a.locale));
    for (const a of [...files].sort((x, y) => x.order.localeCompare(y.order) || x.target.id.localeCompare(y.target.id))) {
      if (a.kind !== 'screenshot' && a.kind !== 'preview') continue;
      const type = classicTypeFor(a.target);
      if (!type) continue;
      const key = `${p.platform}|${a.locale}|${a.kind}|${type}`;
      const job = jobs.get(key) ?? { platform: p.platform, locale: a.locale, kind: a.kind, deviceType: type, targets: [], files: [] };
      if (!job.targets.includes(a.target.id)) job.targets.push(a.target.id);
      job.files.push(a.file);
      jobs.set(key, job);
    }
  }
  return [...jobs.values()];
}

/** `metadata/asc/<platform>/…` — rebuilt for every run. */
export function ascRoot(paths: AppPaths, platform: AppStorePlatform): string {
  return join(paths.vitrin, 'asc', platform);
}

/** Copies a job's files into their own folder, named so that asc's sorted directory read keeps Vitrin's order. */
export async function stageAscJob(paths: AppPaths, job: AscMediaJob): Promise<string> {
  const dir = join(ascRoot(paths, job.platform), 'media', job.locale, job.deviceType);
  await rm(dir, { recursive: true, force: true });
  await ensureDir(dir);
  let i = 0;
  for (const f of job.files) {
    i++;
    await copyFile(f, join(dir, `${String(i).padStart(2, '0')}_${basename(f, extname(f))}${extname(f)}`));
  }
  return dir;
}

async function runAsc(inv: AscInvocation, root: string, runner: CommandRunner, what: string): Promise<void> {
  const res = await runner(inv.command, inv.args, { cwd: root, stream: true, env: inv.env });
  if (res.code === 0) return;
  if (res.code === 127 || /ENOENT|command not found/i.test(res.stderr)) throw new Error(`asc is not installed: ${ASC_INSTALL_HINT}`);
  throw new Error(`${what} failed (asc exit ${res.code}). See the details above.`);
}

/**
 * The `asc` uploader: per Apple platform, text through `asc metadata push` (app info with the first platform only;
 * it is shared) and each selected display type through `asc screenshots|video-previews upload --replace`.
 * Returns the number of media jobs run. Duo sets are not handled here (App Asset Library).
 */
export async function runAscForPlatforms(
  paths: AppPaths,
  plan: UploadPlan,
  assets: RenderedAsset[],
  client: AscClient | undefined,
  opts: { languages: string[]; env: NodeJS.ProcessEnv; dryRun?: boolean; skipScreenshots?: boolean },
  runner: CommandRunner = exec,
): Promise<{ metadataRuns: number; mediaJobs: number }> {
  const auth = ascEnv(opts.env, paths.root);
  // A partial Vitrin key is an error; no Vitrin key at all means asc's own login (empty env map, see ascEnv).
  if (auth.problems.length) throw new Error(`asc credentials: ${auth.problems.join('; ')}`);
  if (!plan.appId) throw new Error('No App Store Connect app id; the asc uploader needs the app record (run `vitrin doctor`).');
  let metadataRuns = 0;
  let appInfoDone = false;
  for (const p of plan.platforms) {
    const ps = plan.scope?.apple.find((s) => s.platform === p.platform);
    if (plan.scope && !isActive(ps)) continue;
    if (!p.version) continue;
    if (!ps || ps.metadata) {
      const dir = join(ascRoot(paths, p.platform), 'metadata');
      const exp = await exportAscMetadata(paths.storeMetadata, dir, { locales: opts.languages, version: p.version.versionString, includeAppInfo: !appInfoDone, dropReleaseNotes: p.firstRelease });
      for (const w of exp.warnings) log.warn(w);
      if (exp.files.length) {
        log.step(`asc metadata push ${p.platform}${opts.dryRun ? ' (dry run)' : ''}…`);
        await runAsc(ascMetadataPushInvocation({ appId: plan.appId, version: p.version.versionString, platform: ASC_PLATFORM[p.platform] as AscPlatform, dir, dryRun: Boolean(opts.dryRun), confirm: exp.clears > 0 }, auth.env), paths.root, runner, 'asc metadata push');
        metadataRuns++;
        appInfoDone = true;
      }
    }
  }
  if (opts.skipScreenshots) return { metadataRuns, mediaJobs: 0 };
  const jobs = ascMediaJobs(plan, assets, opts.languages);
  if (jobs.length && !client) {
    if (opts.dryRun) return { metadataRuns, mediaJobs: 0 };
    throw new Error('The asc media upload needs the version localization ids (an ASC API key in Vitrin, or `asc auth login`).');
  }
  const locCache = new Map<string, Array<{ id: string; attributes: Record<string, string | null> }>>();
  let mediaJobs = 0;
  for (const job of jobs) {
    const version = plan.platforms.find((p) => p.platform === job.platform)?.version;
    if (!version) continue;
    if (!locCache.has(version.id)) locCache.set(version.id, await client!.versionLocalizations(version.id));
    const loc = locCache.get(version.id)!.find((l) => l.attributes.locale === job.locale);
    if (!loc) {
      log.warn(`${job.platform} ${job.locale}: no version localization (upload the text first); ${job.deviceType} skipped.`);
      continue;
    }
    const dir = await stageAscJob(paths, job);
    const inv = job.kind === 'screenshot' ? ascScreenshotsUploadInvocation({ localizationId: loc.id, path: dir, deviceType: job.deviceType, dryRun: opts.dryRun }, auth.env) : ascVideoPreviewsUploadInvocation({ localizationId: loc.id, path: dir, deviceType: job.deviceType, dryRun: opts.dryRun }, auth.env);
    log.step(`asc ${job.kind === 'screenshot' ? 'screenshots' : 'video-previews'} upload ${job.platform} ${job.locale} ${job.deviceType} (${job.files.length} files, replaces only this set)…`);
    await runAsc(inv, paths.root, runner, `asc ${inv.args[0]} upload ${job.deviceType}`);
    mediaJobs++;
  }
  return { metadataRuns, mediaJobs };
}

/** `asc version` → the version string, or null when asc is not installed. */
export async function ascVersion(runner: CommandRunner = exec): Promise<string | null> {
  const inv = ascVersionInvocation();
  const res = await runner(inv.command, inv.args, { timeoutMs: 30_000 }).catch(() => ({ code: 127, stdout: '', stderr: '' }));
  if (res.code !== 0) return null;
  return /v?(\d+\.\d+\.\d+)/.exec(res.stdout + res.stderr)?.[1] ?? ((res.stdout + res.stderr).trim() || 'unknown');
}
