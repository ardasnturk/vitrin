import { enabledTargets, existsSync, loadTargets, log, readJsonIfExists, type AppPaths } from '@vitrin/core';
import { readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { RenderManifest, type AppProfile, type Platform, type PreviewType, type RenderTarget, type ScreenshotDisplayType, type VitrinConfig } from '@vitrin/schemas';
import type { AscClient } from './asc-client.js';
import { AssetLibraryClient, type PlacementSpec } from './asset-library.js';
import { classicTypeFor, displayTypesFor, perTypeRoute } from './display-types.js';
import { ClassicMediaClient } from './screenshot-sets.js';
import type { PollOptions } from './upload-operations.js';
import { isActive, type UploadPlan } from './plan.js';
import { collectRenderedAssets, platformsFromConfig, type RenderedAsset } from './platforms.js';
import { perDisplayTypeAssetsFor, type PlatformScope } from './scope.js';

export interface StoreContext {
  /** Platforms the app ships on: profile.app.platforms, or the legacy config.upload.platform. */
  platforms: Platform[];
  assets: RenderedAsset[];
  /** Targets enabled for this app on its platforms (decides whether a run carries a complete set). */
  enabledTargets: RenderTarget[];
}

/** Collects what an upload needs: platforms and rendered files routed by target. */
export async function prepareStores(opts: {
  paths: AppPaths;
  config: VitrinConfig;
  profile?: AppProfile;
  targets?: RenderTarget[];
}): Promise<StoreContext> {
  const { paths, config, profile } = opts;
  const platforms = profile?.app.platforms?.length ? profile.app.platforms : platformsFromConfig(config.upload.platform);
  const manifest = await readJsonIfExists(paths.renderManifest, RenderManifest).catch(() => undefined);
  const { assets, unknown } = await collectRenderedAssets(paths, opts.targets ?? loadTargets(), manifest);
  for (const f of unknown) log.dim(`  ${f}: target not in data/targets.json, not uploaded`);
  // Every format of the selected platforms, so a run limited by selection.targets counts as partial (never overwrites).
  const enabled = (opts.targets ?? enabledTargets(config, profile, { allFormats: true })).filter((t) => platforms.includes(t.platform));
  return { platforms, assets, enabledTargets: enabled };
}

function scopeOf(plan: UploadPlan, platform: string): PlatformScope | undefined {
  return plan.scope?.apple.find((s) => s.platform === platform);
}

/** Files of a platform that this run replaces, one display type at a time. */
export function perDisplayTypeFilesFor(plan: UploadPlan, platform: string, assets: RenderedAsset[]): RenderedAsset[] {
  const ps = scopeOf(plan, platform);
  if (!ps || !isActive(ps)) return [];
  return perDisplayTypeAssetsFor(ps, assets);
}

/** The subset of `perDisplayTypeFilesFor` that needs the App Asset Library (no classic display type: iPhone Duo). */
export function assetLibraryFilesFor(plan: UploadPlan, platform: string, assets: RenderedAsset[]): RenderedAsset[] {
  return perDisplayTypeFilesFor(plan, platform, assets).filter((a) => perTypeRoute(a.target) === 'asset-library');
}

export interface PerDisplayTypeOptions {
  /** `skip`: the classic sets are uploaded elsewhere (the asc CLI); only Asset Library sets are handled here. */
  classic?: 'api' | 'skip';
  uploadFetch?: typeof fetch;
  poll?: PollOptions;
}

/**
 * Replaces exactly the display types in this run and nothing else, one localization at a time:
 * - through the classic appScreenshotSets/appPreviewSets API when it has a type for the target (finds or creates
 *   that one set, deletes only its items, uploads, commits with the MD5 checksum and sets the order);
 * - through the App Asset Library otherwise (iPhone Duo)
 *   (deletes only placements of that placementType and refData placementGroup, uploads, places, orders).
 * Other device sets of the locale stay untouched. Returns the number of files uploaded.
 */
export async function uploadPerDisplayType(client: AscClient, plan: UploadPlan, assets: RenderedAsset[], locales: string[], opts: PerDisplayTypeOptions = {}): Promise<number> {
  if (!plan.appId) return 0;
  const lib = new AssetLibraryClient(client, { uploadFetch: opts.uploadFetch, poll: opts.poll });
  const classic = new ClassicMediaClient(client, { uploadFetch: opts.uploadFetch, poll: opts.poll });
  let uploaded = 0;
  let libraryId: string | undefined;
  for (const p of plan.platforms) {
    const files = perDisplayTypeFilesFor(plan, p.platform, assets).filter((a) => locales.includes(a.locale));
    if (!files.length || !p.version) continue;
    const groups = new Map<string, { locale: string; kind: 'screenshot' | 'preview'; route: 'classic' | 'asset-library'; type: string; spec?: PlacementSpec; files: RenderedAsset[] }>();
    for (const a of [...files].sort((x, y) => x.order.localeCompare(y.order) || x.target.id.localeCompare(y.target.id))) {
      if (a.kind !== 'screenshot' && a.kind !== 'preview') continue;
      const route = perTypeRoute(a.target);
      if (route === 'none') throw new Error(`${a.target.id}: no classic display type and no App Asset Library placement in data/asc-display-types.json; refusing a partial replacement that could touch other sets.`);
      if (route === 'classic' && opts.classic === 'skip') continue;
      const spec = displayTypesFor(a.target.id)?.assetLibrary;
      const type = route === 'classic' ? classicTypeFor(a.target)! : `${spec!.placementType}/${spec!.platform}/${spec!.displayClass}`;
      const key = `${a.locale}|${route}|${type}`;
      const g = groups.get(key) ?? { locale: a.locale, kind: a.kind, route, type, spec, files: [] };
      g.files.push(a);
      groups.set(key, g);
    }
    if (!groups.size) continue;
    const locs = await client.versionLocalizations(p.version.id);
    for (const g of groups.values()) {
      const loc = locs.find((l) => l.attributes.locale === g.locale);
      if (!loc) {
        log.warn(`${p.platform} ${g.locale}: no version localization (upload the text first); ${g.type} skipped.`);
        continue;
      }
      const paths = g.files.map((f) => f.file);
      if (g.route === 'classic') {
        const res =
          g.kind === 'screenshot'
            ? await classic.replaceScreenshotSet(loc.id, g.type as ScreenshotDisplayType, paths)
            : await classic.replacePreviewSet(loc.id, g.type as PreviewType, paths);
        log.dim(`  ${p.platform} ${g.locale} ${g.type}: ${res.createdSet ? 'created the set' : `replaced ${res.deleted} items`}, uploaded ${res.uploaded.length}`);
        uploaded += res.uploaded.length;
      } else {
        libraryId ??= await lib.libraryId(plan.appId);
        const res = await lib.replaceSet(libraryId, { type: 'appStoreVersionLocalizations', id: loc.id }, g.spec!, g.files.map((f) => ({ file: f.file, kind: f.kind === 'preview' ? ('video' as const) : ('image' as const) })));
        log.dim(`  ${p.platform} ${g.locale} ${g.type} (group ${res.group}): replaced ${res.removed} placements, placed ${res.placements.length}`);
        uploaded += res.placements.length;
      }
    }
  }
  return uploaded;
}

/**
 * Product page header and search result creatives of the version (App Asset Library, CREATIVE_ASSETS): for each
 * locale and placement type, the existing placements of that type are replaced. Files: `<creativeDir>/<locale>/
 * {header,search}_*.{png,mp4}`.
 */
export async function uploadVersionCreatives(client: AscClient, plan: UploadPlan, creativeDir: string, locales: string[], opts: { uploadFetch?: typeof fetch; poll?: PollOptions } = {}): Promise<number> {
  if (!plan.appId || !plan.version) return 0;
  const lib = new AssetLibraryClient(client, opts);
  const libraryId = await lib.libraryId(plan.appId);
  const locs = await client.versionLocalizations(plan.version.id);
  let n = 0;
  for (const locale of locales) {
    const loc = locs.find((l) => l.attributes.locale === locale);
    const dir = join(creativeDir, locale);
    if (!loc || !existsSync(dir)) continue;
    const byTarget = new Map<'header' | 'search', Array<{ file: string; kind: 'image' | 'video' }>>();
    for (const f of (await readdir(dir)).filter((x) => /^(header|search)_.*\.(png|jpe?g|mp4|mov)$/.test(x)).sort()) {
      const target = f.startsWith('header') ? 'header' : 'search';
      const list = byTarget.get(target) ?? [];
      list.push({ file: join(dir, f), kind: /\.(mp4|mov)$/.test(f) ? 'video' : 'image' });
      byTarget.set(target, list);
    }
    for (const [target, files] of byTarget) {
      const spec = displayTypesFor(target)?.assetLibrary;
      if (!spec) throw new Error(`${target}: no App Asset Library placement in data/asc-display-types.json.`);
      const res = await lib.replaceSet(libraryId, { type: 'appStoreVersionLocalizations', id: loc.id }, spec, files);
      log.ok(`${locale} ${target} → ${spec.placementType} (${res.placements.length} placed, ${res.removed} replaced)`);
      n += res.placements.length;
    }
  }
  return n;
}
