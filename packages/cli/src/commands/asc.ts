import { findAppRoot, loadEnv, log, mask } from '@vitrin/core';
import { AscClient, AscCredentialError, credentialsFromEnv, type JsonApiDocument, type JsonApiResource } from '@vitrin/upload';
import { join } from 'node:path';
import pc from 'picocolors';
import { EXIT, NeedsInput } from '../context.js';

/**
 * `vitrin asc …`: App Store Connect read-only, with the key from the environment or a project's `.env` and no
 * project folder required. The macOS app lists the team's apps with it before any project is added.
 */

export interface AscAppVersion {
  id: string;
  /** IOS, MAC_OS, TV_OS, VISION_OS. */
  platform: string;
  version: string;
  /** `appVersionState` (or the older `appStoreState`): READY_FOR_SALE, PREPARE_FOR_SUBMISSION, IN_REVIEW … */
  state: string;
  createdAt?: string;
}

export interface AscAppSummary {
  id: string;
  bundleId: string;
  name: string;
  sku: string;
  primaryLocale: string;
  /** The platforms that have an App Store version, in ASC's names. */
  platforms: string[];
  /** The newest App Store version per platform. */
  versions: AscAppVersion[];
}

export interface AscAppsResult {
  generatedAt: string;
  apps: AscAppSummary[];
}

type AppAttributes = { name?: string; bundleId?: string; sku?: string; primaryLocale?: string };
type VersionAttributes = { platform?: string; versionString?: string; appVersionState?: string; appStoreState?: string; createdAt?: string };

const PLATFORM_ORDER = ['IOS', 'MAC_OS', 'TV_OS', 'VISION_OS'];
/** `include=appStoreVersions` carries at most this many versions per app; ASC lists the newest first. */
const VERSIONS_PER_APP = 50;

export const ASC_APPS_PATH = `/v1/apps?include=appStoreVersions&fields[apps]=name,bundleId,sku,primaryLocale&fields[appStoreVersions]=platform,versionString,appVersionState,appStoreState,createdAt&limit=200&limit[appStoreVersions]=${VERSIONS_PER_APP}`;

const stateOf = (a: VersionAttributes) => a.appVersionState ?? a.appStoreState ?? '';

/**
 * The team's apps with the newest App Store version per platform, in one listing: `GET /v1/apps` with the versions
 * included, every page followed. The newest version is the one created last (ASC's `createdAt`), so a 2.0 in
 * preparation shows next to a 1.9 on sale as the current one.
 */
export async function listAscApps(client: AscClient): Promise<AscAppSummary[]> {
  const apps: Array<JsonApiResource<AppAttributes>> = [];
  const versionsById = new Map<string, JsonApiResource<VersionAttributes>>();
  let next: string | undefined = ASC_APPS_PATH;
  for (let page = 0; next; page++) {
    if (page >= 20) throw new Error(`ASC API ${ASC_APPS_PATH}: more than 20 pages; refusing to work with a partial list.`);
    const doc: JsonApiDocument<AppAttributes> = await client.get<JsonApiDocument<AppAttributes>>(next);
    apps.push(...(Array.isArray(doc.data) ? doc.data : [doc.data]));
    for (const inc of doc.included ?? []) if (inc.type === 'appStoreVersions') versionsById.set(inc.id, inc as JsonApiResource<VersionAttributes>);
    next = doc.links?.next;
  }
  return apps
    .map((app) => {
      const rel = app.relationships?.appStoreVersions?.data;
      const ids = Array.isArray(rel) ? rel.map((r) => r.id) : rel ? [rel.id] : [];
      const versions = ids.map((id) => versionsById.get(id)).filter((v): v is JsonApiResource<VersionAttributes> => Boolean(v));
      return {
        id: app.id,
        bundleId: app.attributes.bundleId ?? '',
        name: app.attributes.name ?? '',
        sku: app.attributes.sku ?? '',
        primaryLocale: app.attributes.primaryLocale ?? '',
        platforms: platformsOf(versions),
        versions: latestPerPlatform(versions),
      };
    })
    .sort((a, b) => a.name.localeCompare(b.name) || a.bundleId.localeCompare(b.bundleId));
}

function platformsOf(versions: Array<JsonApiResource<VersionAttributes>>): string[] {
  const set = new Set(versions.map((v) => v.attributes.platform ?? '').filter(Boolean));
  return [...set].sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
}

const rank = (platform: string) => {
  const i = PLATFORM_ORDER.indexOf(platform);
  return i < 0 ? PLATFORM_ORDER.length : i;
};

/** One version per platform: the one created last, by `createdAt`; without it, the first ASC listed. */
export function latestPerPlatform(versions: Array<JsonApiResource<VersionAttributes>>): AscAppVersion[] {
  const byPlatform = new Map<string, JsonApiResource<VersionAttributes>>();
  for (const v of versions) {
    const platform = v.attributes.platform ?? '';
    if (!platform) continue;
    const cur = byPlatform.get(platform);
    if (!cur || (v.attributes.createdAt ?? '') > (cur.attributes.createdAt ?? '')) byPlatform.set(platform, v);
  }
  return [...byPlatform.values()]
    .map((v) => ({ id: v.id, platform: v.attributes.platform ?? '', version: v.attributes.versionString ?? '', state: stateOf(v.attributes), ...(v.attributes.createdAt ? { createdAt: v.attributes.createdAt } : {}) }))
    .sort((a, b) => rank(a.platform) - rank(b.platform) || a.platform.localeCompare(b.platform));
}

export interface AscAppsOptions {
  cwd?: string;
  json?: boolean;
  /** For tests: the environment to read the key from (default `process.env` after the project's `.env`). */
  env?: NodeJS.ProcessEnv;
  fetchImpl?: typeof fetch;
}

/**
 * `vitrin asc apps`: works in any folder. The key comes from ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH in the
 * environment; inside a project, its `.env` fills in what the environment does not set (the environment wins, as
 * everywhere in Vitrin). Nothing is written: no workspace, no state, no `.gitignore` block.
 */
export async function ascAppsCommand(opts: AscAppsOptions = {}): Promise<number> {
  let env = opts.env;
  if (!env) {
    const root = findAppRoot(opts.cwd ?? process.cwd());
    env = loadEnv(join(root, '.env'));
  }
  let client: AscClient;
  try {
    client = new AscClient(credentialsFromEnv(env), opts.fetchImpl);
  } catch (err) {
    if (err instanceof AscCredentialError) {
      throw new NeedsInput(err.message, ['Set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH in the environment or in the project’s .env (App Store Connect → Users and Access → Integrations → App Store Connect API).'], 'keys-missing');
    }
    throw err;
  }
  const apps = await listAscApps(client);
  const result: AscAppsResult = { generatedAt: new Date().toISOString(), apps };
  if (opts.json) {
    process.stdout.write(mask(JSON.stringify(result, null, 2)) + '\n');
    return EXIT.OK;
  }
  if (!apps.length) {
    log.info('No apps on this team.');
    return EXIT.OK;
  }
  log.step(`${apps.length} app(s) on the team`);
  for (const app of apps) {
    const versions = app.versions.map((v) => `${platformLabel(v.platform)} ${v.version} ${pc.dim(v.state.toLowerCase().replace(/_/g, ' '))}`).join(pc.dim(' · '));
    log.info(`${pc.bold(app.name)} ${pc.dim(app.bundleId)}${versions ? `  ${versions}` : pc.dim('  no App Store version yet')}`);
  }
  return EXIT.OK;
}

export function platformLabel(platform: string): string {
  switch (platform) {
    case 'IOS': return 'iOS';
    case 'MAC_OS': return 'macOS';
    case 'TV_OS': return 'tvOS';
    case 'VISION_OS': return 'visionOS';
    default: return platform;
  }
}
