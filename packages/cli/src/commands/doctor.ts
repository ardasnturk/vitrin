import { ENV_KEYS, exec, existsSync, loadTargets, log, readJsonIfExists, renderEnvExample, writeJson, writeText, type EnvKey } from '@vitrin/core';
import { AppProfile, type Platform } from '@vitrin/schemas';
import {
  applePlatformsOf,
  ASC_INSTALL_HINT,
  ASC_PLATFORM,
  ascClientFor,
  ascEnv,
  ascHasOwnAuth,
  ascValidateInvocation,
  ascVersion,
  ascVersionsCreateInvocation,
  AscApiError,
  AscClient,
  AscCredentialError,
  credentialsFromEnv,
  diffRefData,
  isEditableVersion,
  isPem,
  platformsFromConfig,
} from '@vitrin/upload';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { chromium } from 'playwright';
import pc from 'picocolors';
import { bundleIdOf, EXIT, type Ctx } from '../context.js';

/** Installs Chromium for the Playwright version Vitrin itself uses (a bare `npx playwright` may fetch another version). */
function playwrightInstallCommand(): string {
  try {
    const cli = join(dirname(createRequire(import.meta.url).resolve('playwright/package.json')), 'cli.js');
    return `node "${cli}" install chromium`;
  } catch {
    return 'npx playwright install chromium';
  }
}

export type CheckStatus = 'ok' | 'warn' | 'fail' | 'skip';
export interface Check {
  id: string;
  title: string;
  status: CheckStatus;
  detail?: string;
  fix?: string;
}

export interface DoctorResult {
  checks: Check[];
  missingKeys: Array<Pick<EnvKey, 'name' | 'where'>>;
  exitCode: number;
}

export function compareVersions(a: string, b: string): number {
  const pa = a.split('.').map((x) => parseInt(x, 10) || 0);
  const pb = b.split('.').map((x) => parseInt(x, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d) return Math.sign(d);
  }
  return 0;
}

async function versionOf(cmd: string, args: string[], re: RegExp): Promise<string | null> {
  const r = await exec(cmd, args, { timeoutMs: 60_000 }).catch(() => ({ code: 127, stdout: '', stderr: '' }));
  if (r.code !== 0) return null;
  return re.exec(r.stdout + r.stderr)?.[1] ?? null;
}

/** What is installed for uploading: the asc CLI (every App Store upload). */
export interface UploaderTools {
  asc: string | null;
  /** asc has its own stored login (`asc auth login`), used when Vitrin has no ASC key. */
  ascLogin?: boolean;
  /** Homebrew, which installs the asc CLI (`brew install asc`). */
  brew?: string | null;
}

export async function detectUploaderTools(): Promise<UploaderTools> {
  const [asc, brew] = await Promise.all([ascVersion(), versionOf('brew', ['--version'], /Homebrew (\d+\.\d+\.\d+)/)]);
  const ascLogin = asc ? await ascHasOwnAuth() : false;
  return { asc, ascLogin, brew };
}

/**
 * Which of the upload-required keys are missing. ASC_KEY_PATH / ASC_KEY_CONTENT_BASE64 are alternatives. With
 * `ascLogin` (asc has its own stored login) and no ASC_* key variable set at all, the ASC key is not needed: asc
 * authenticates on its own. A partial key is still reported.
 */
export function missingUploadKeys(env: NodeJS.ProcessEnv, opts: { ascLogin?: boolean } = {}): Array<Pick<EnvKey, 'name' | 'where'>> {
  const missing: Array<Pick<EnvKey, 'name' | 'where'>> = [];
  const ascByLogin = Boolean(opts.ascLogin) && !['ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_KEY_PATH', 'ASC_KEY_CONTENT_BASE64'].some((n) => env[n]?.trim());
  for (const k of ENV_KEYS) {
    if (k.required !== 'upload') continue;
    if (ascByLogin && k.name.startsWith('ASC_')) continue;
    if (k.name === 'ASC_KEY_PATH' && env.ASC_KEY_CONTENT_BASE64?.trim()) continue;
    if (!env[k.name]?.trim()) missing.push({ name: k.name, where: k.where });
  }
  return missing;
}

/** Platforms from the app profile, falling back to the single `upload.platform` config value. */
export async function platformsOf(ctx: Ctx): Promise<Platform[]> {
  const profile = await readJsonIfExists(ctx.paths.profile, AppProfile).catch(() => undefined);
  return profile?.app.platforms?.length ? profile.app.platforms : platformsFromConfig(ctx.config.upload.platform);
}

export async function runDoctor(ctx: Ctx, opts: { createVersion?: string; offline?: boolean; tools?: boolean } = {}): Promise<DoctorResult> {
  const checks: Check[] = [];
  const add = (c: Check) => {
    checks.push(c);
    const icon = { ok: pc.green('✓'), warn: pc.yellow('⚠'), fail: pc.red('✗'), skip: pc.dim('–') }[c.status];
    log.info(`${icon} ${c.title}${c.detail ? pc.dim(` — ${c.detail}`) : ''}`);
    if (c.fix && c.status !== 'ok') log.info(pc.dim(`    → ${c.fix}`));
  };

  const platforms = await platformsOf(ctx);
  const apple = applePlatformsOf(platforms);

  // 1. Tools
  log.step('1/6 Tools');
  const node = process.versions.node;
  add({ id: 'node', title: `Node.js ${node}`, status: compareVersions(node, '22.0.0') >= 0 ? 'ok' : 'fail', fix: 'Install Node 22 or later.' });
  const pnpm = await versionOf('pnpm', ['--version'], /(\d+\.\d+\.\d+)/);
  add({ id: 'pnpm', title: 'pnpm', status: pnpm ? 'ok' : 'warn', detail: pnpm ?? 'not found', fix: 'corepack enable && corepack prepare pnpm@latest --activate (only needed to install Vitrin from source).' });
  // Uploads always use the asc CLI. The early `--tools` check only warns about a missing asc: nothing is uploaded yet.
  const { asc, ascLogin: ascSignedIn } = await detectUploaderTools();
  add({ id: 'asc', title: 'asc CLI', status: asc ? 'ok' : opts.tools ? 'warn' : 'fail', detail: asc ?? 'not found (every App Store upload uses it)', fix: ASC_INSTALL_HINT });
  const xcode = await versionOf('xcodebuild', ['-version'], /Xcode (\d+(?:\.\d+)*)/);
  // HTML screens (capture.mode: html) need no build: Xcode and simulators are then optional.
  const appleTool = (ok: boolean): CheckStatus => (ok ? 'ok' : ctx.config.capture.mode !== 'html' ? 'fail' : 'skip');
  add({ id: 'xcode', title: 'Xcode', status: appleTool(Boolean(xcode)), detail: xcode ?? 'not found', fix: 'Install Xcode and run `sudo xcode-select -s /Applications/Xcode.app`.' });
  const simctl = await exec('xcrun', ['simctl', 'list', 'runtimes']);
  add({ id: 'simctl', title: 'iOS Simulator (simctl)', status: appleTool(simctl.code === 0 && /iOS/.test(simctl.stdout)), fix: 'Download an iOS simulator runtime from Xcode > Settings > Components.' });
  const ffmpeg = await versionOf('ffmpeg', ['-version'], /ffmpeg version (\S+)/);
  const ffprobe = await versionOf('ffprobe', ['-version'], /ffprobe version (\S+)/);
  add({ id: 'ffmpeg', title: 'ffmpeg / ffprobe', status: ffmpeg && ffprobe ? 'ok' : 'fail', detail: ffmpeg ?? 'not found', fix: 'brew install ffmpeg' });
  let chromiumOk = false;
  try {
    chromiumOk = existsSync(chromium.executablePath());
  } catch {
    chromiumOk = false;
  }
  add({ id: 'playwright', title: 'Playwright Chromium', status: chromiumOk ? 'ok' : 'fail', fix: playwrightInstallCommand() });
  // `doctor --tools`: the early check before generating anything — no keys, no network, nothing written.
  if (opts.tools) return { checks, missingKeys: [], exitCode: checks.some((c) => c.status === 'fail') ? EXIT.FAIL : EXIT.OK };

  // 2. .env and keys
  log.step('2/6 .env and keys');
  const hasEnv = existsSync(ctx.paths.env);
  add({ id: 'env', title: '.env file', status: hasEnv ? 'ok' : 'warn', detail: hasEnv ? ctx.paths.env : 'missing', fix: `cp .env.example .env and fill in the values (${ctx.paths.env}).` });
  // No Vitrin ASC key but a stored `asc auth login`: asc (and Vitrin's API calls through `asc api`) use that.
  const ascLogin = ascEnv(ctx.env, ctx.root).source === 'asc-login' && Boolean(ascSignedIn);
  if (ascLogin) add({ id: 'asc-login', title: 'ASC credential', status: 'ok', detail: 'no Vitrin key; asc uses its own login (asc auth status)' });
  const missingKeys = missingUploadKeys(ctx.env, { ascLogin });
  for (const k of missingKeys) add({ id: `key:${k.name}`, title: k.name, status: 'fail', detail: 'missing', fix: k.where });
  let keyFileOk = Boolean(ctx.env.ASC_KEY_CONTENT_BASE64?.trim());
  if (ctx.env.ASC_KEY_PATH?.trim() && !ctx.env.ASC_KEY_CONTENT_BASE64?.trim()) {
    const p = ctx.env.ASC_KEY_PATH.trim();
    const full = p.startsWith('/') ? p : join(ctx.root, p);
    if (!existsSync(full)) add({ id: 'p8', title: '.p8 file', status: 'fail', detail: `not found: ${p}`, fix: 'Put the AuthKey_<KEYID>.p8 file downloaded from ASC at this path.' });
    else if (!isPem(await readFile(full, 'utf8'))) add({ id: 'p8', title: '.p8 file', status: 'fail', detail: 'not in PEM format', fix: 'The file must start with “-----BEGIN PRIVATE KEY-----”.' });
    else {
      keyFileOk = true;
      process.env.ASC_KEY_PATH = full;
      add({ id: 'p8', title: '.p8 file', status: 'ok', detail: 'PEM' });
    }
  }

  // 3–4. Live API
  log.step('3/6 App Store Connect API');
  let client: AscClient | undefined;
  let appId: string | undefined;
  if (opts.offline) add({ id: 'api', title: 'Live API test', status: 'skip', detail: '--offline' });
  else if (!ascLogin && (missingKeys.length || !keyFileOk)) add({ id: 'api', title: 'Live API test', status: 'skip', detail: 'keys missing' });
  else {
    try {
      client = (await ascClientFor(ctx.env, ctx.root, () => new AscClient(credentialsFromEnv(process.env)))).client;
      if (!client) throw new AscCredentialError('ASC API key is missing (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH) and asc has no login (asc auth login).');
      const bundleId = bundleIdOf(ctx);
      const app = await client.findApp(bundleId);
      if (!app) {
        add({ id: 'app', title: 'App record', status: 'fail', detail: `${bundleId} not found in ASC`, fix: 'The app record cannot be created with an API key (403). Create it once by hand in App Store Connect > Apps > +.' });
      } else {
        appId = app.id;
        add({ id: 'api', title: 'JWT and role', status: 'ok', detail: 'key valid' });
        add({ id: 'app', title: 'App record', status: 'ok', detail: `${app.attributes.name} (${app.id})` });
      }
    } catch (err) {
      if (err instanceof AscCredentialError) add({ id: 'api', title: 'ASC key', status: 'fail', detail: err.message });
      else if (err instanceof AscApiError && err.status === 401) add({ id: 'api', title: 'JWT', status: 'fail', detail: '401 — key/issuer invalid or revoked', fix: 'Check that the Key ID, Issuer ID and .p8 file belong to the same key.' });
      else if (err instanceof AscApiError && err.status === 403) add({ id: 'api', title: 'Role', status: 'fail', detail: '403 — insufficient permissions', fix: 'The key needs at least the App Manager role (Team Key).' });
      else add({ id: 'api', title: 'Live API test', status: 'fail', detail: (err as Error).message });
    }
  }

  log.step('4/6 Editable version');
  if (client && appId) {
    // One App Store version per Apple platform; --create-version only acts on the first (iOS when present).
    for (const p of apple) {
      const platform = ASC_PLATFORM[p];
      const suffix = apple.length > 1 ? ` (${platform})` : '';
      let versions = await client.appStoreVersions(appId, platform);
      let editable = versions.find(isEditableVersion);
      if (!editable && opts.createVersion && p === apple[0]) {
        log.info(`  Trying to create version ${opts.createVersion} with asc versions create…`);
        try {
          const auth = ascEnv(ctx.env, ctx.root);
          if (auth.problems.length) throw new Error(`asc credentials: ${auth.problems.join('; ')}`);
          const inv = ascVersionsCreateInvocation({ appId, version: opts.createVersion, platform: platform as 'IOS' }, auth.env);
          const res = await exec(inv.command, inv.args, { cwd: ctx.root, env: inv.env, stream: true, timeoutMs: 180_000 });
          if (res.code !== 0) throw new Error(`asc versions create failed (exit ${res.code}); App Store Connect may require the first version to be created by hand.`);
          versions = await client.appStoreVersions(appId, platform);
          editable = versions.find(isEditableVersion);
        } catch (err) {
          log.warn((err as Error).message);
        }
      }
      if (editable) add({ id: `version:${p}`, title: `Editable version${suffix}`, status: 'ok', detail: `${editable.attributes.versionString} (${editable.attributes.appVersionState ?? editable.attributes.appStoreState})` });
      else
        add({
          id: `version:${p}`,
          title: `Editable version${suffix}`,
          status: 'fail',
          detail: versions.length ? 'all versions are locked' : 'no App Store version exists',
          fix:
            p === 'ios'
              ? 'For a new version run `vitrin doctor --create-version 1.2.0`. For an app that is only on TestFlight the API may reject the first version; create it once by hand in ASC.'
              : `Add the platform to the app record in App Store Connect and create its first version there (${platform}).`,
        });
    }
  } else add({ id: 'version', title: 'Editable version', status: 'skip' });

  // 5. URLs
  log.step('5/6 URLs');
  for (const [key, url] of Object.entries(ctx.config.urls)) {
    if (!url) continue;
    if (opts.offline) {
      add({ id: `url:${key}`, title: `${key} URL`, status: 'skip', detail: url });
      continue;
    }
    if (/example\.(com|org)/.test(url)) {
      add({ id: `url:${key}`, title: `${key} URL`, status: 'fail', detail: `${url} is a placeholder`, fix: 'Put the real address in vitrin.config.yaml urls.' });
      continue;
    }
    try {
      const res = await fetch(url, { redirect: 'follow', signal: AbortSignal.timeout(15_000) });
      const text = key === 'support' ? await res.text() : '';
      const contact = /@[a-z0-9-]+\.[a-z]{2,}|mailto:|tel:|\+\d[\d\s]{6,}|contact|iletişim|kontakt|contacto|お問い合わせ|<form/i.test(text);
      if (!res.ok) add({ id: `url:${key}`, title: `${key} URL`, status: 'fail', detail: `${res.status} ${url}` });
      else if (key === 'support' && !contact) add({ id: `url:${key}`, title: 'Support page', status: 'warn', detail: 'no contact information found', fix: 'The support page must include real contact information (email/form).' });
      else add({ id: `url:${key}`, title: `${key} URL`, status: 'ok', detail: `${res.status}` });
    } catch (err) {
      add({ id: `url:${key}`, title: `${key} URL`, status: 'fail', detail: `${url}: ${(err as Error).message}` });
    }
  }

  // 6. refData vs targets.json
  log.step('6/6 App Asset Library refData');
  if (client) {
    try {
      const ref = await client.assetLibraryRefData();
      await writeJson(join(ctx.paths.cache, 'refdata.json'), ref);
      const diffs = diffRefData(ref, loadTargets());
      add({ id: 'refdata', title: 'refData ↔ data/asc-display-types.json', status: diffs.length ? 'warn' : 'ok', detail: diffs.length ? `${diffs.length} differences` : 'in sync', fix: diffs.slice(0, 6).join('\n      ') });
    } catch (err) {
      add({ id: 'refdata', title: 'refData', status: 'warn', detail: (err as Error).message });
    }
  } else add({ id: 'refdata', title: 'refData', status: 'skip' });

  // Optional (upload.ascValidate: true): asc's submission-readiness report for the editable version. A warning only:
  // it also checks things an upload does not need yet (an attached build, pricing).
  if (ctx.config.upload.ascValidate && client && appId) {
    const auth = ascEnv(ctx.env, ctx.root);
    if (auth.problems.length) add({ id: 'asc-validate', title: 'asc validate', status: 'skip', detail: auth.problems.join('; ') });
    else if (!(await ascVersion())) add({ id: 'asc-validate', title: 'asc validate', status: 'skip', detail: 'asc not installed', fix: ASC_INSTALL_HINT });
    else {
      for (const p of apple) {
        const inv = ascValidateInvocation({ appId, platform: ASC_PLATFORM[p] as 'IOS' }, auth.env);
        const res = await exec(inv.command, inv.args, { cwd: ctx.root, env: inv.env, timeoutMs: 180_000 });
        const last = (res.stdout + res.stderr).trim().split('\n').slice(-1)[0];
        add({ id: `asc-validate:${p}`, title: `asc validate (${ASC_PLATFORM[p]})`, status: res.code === 0 ? 'ok' : 'warn', detail: res.code === 0 ? 'ready for submission' : `exit ${res.code}${last ? `: ${last}` : ''}`, fix: `asc validate --app ${appId} --platform ${ASC_PLATFORM[p]} shows the full report.` });
      }
    }
  }

  let exitCode: number = EXIT.OK;
  if (checks.some((c) => c.status === 'fail')) exitCode = EXIT.FAIL;
  if (missingKeys.length) {
    exitCode = EXIT.NEEDS_INPUT;
    // Keep .env.example current so the user sees every key with its explanation.
    await writeText(ctx.paths.envExample, renderEnvExample(await extraEnvExampleLines(ctx.paths.envExample)));
    log.info('');
    log.info(pc.bold('Missing keys required for upload:'));
    for (const k of missingKeys) log.info(`  • ${pc.bold(k.name)} — ${k.where}`);
    log.info(`\nWrite the values to ${pc.bold(ctx.paths.env)} (example: ${ctx.paths.envExample}). Do not paste them into the chat.`);
    log.info('Add them to .env, then reply "continue".');
  }
  return { checks, missingKeys, exitCode };
}

async function extraEnvExampleLines(file: string): Promise<string[]> {
  if (!existsSync(file)) return [];
  const known = new Set(ENV_KEYS.map((k) => k.name));
  return (await readFile(file, 'utf8')).split('\n').filter((l) => {
    const m = /^([A-Z0-9_]+)=/.exec(l);
    return m && !known.has(m[1]!);
  });
}
