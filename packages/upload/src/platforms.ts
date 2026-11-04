import { existsSync, type AppPaths } from '@vitrin/core';
import type { Platform, RenderManifest, RenderTarget } from '@vitrin/schemas';
import { readdir } from 'node:fs/promises';
import { join } from 'node:path';

/**
 * One App Store version per value (config `upload.platform` uses the same names): ios (iPhone, iPad, Duo and Apple
 * Watch), osx (Mac), appletvos (Apple TV), xros (Apple Vision Pro).
 */
export type AppStorePlatform = 'ios' | 'osx' | 'appletvos' | 'xros';
export const APP_STORE_PLATFORMS: AppStorePlatform[] = ['ios', 'osx', 'appletvos', 'xros'];

/** ASC API `filter[platform]` (and asc `--platform`) of each App Store version. */
export const ASC_PLATFORM: Record<AppStorePlatform, string> = { ios: 'IOS', osx: 'MAC_OS', appletvos: 'TV_OS', xros: 'VISION_OS' };

/**
 * Shipping platform → App Store version. watchOS has no App Store version of its own: Apple Watch screenshots
 * belong to the iOS version (display types APP_WATCH_*).
 */
export function appStorePlatformFor(platform: Platform): AppStorePlatform {
  switch (platform) {
    case 'ios':
    case 'watchos':
      return 'ios';
    case 'macos':
      return 'osx';
    case 'tvos':
      return 'appletvos';
    case 'visionos':
      return 'xros';
  }
}

/** The App Store versions an app has, in a stable order (iOS first). */
export function applePlatformsOf(platforms: Platform[]): AppStorePlatform[] {
  const set = new Set(platforms.map(appStorePlatformFor));
  return APP_STORE_PLATFORMS.filter((p) => set.has(p));
}

/** Maps the legacy single `upload.platform` config value to profile platforms. */
export function platformsFromConfig(value: AppStorePlatform): Platform[] {
  return [{ ios: 'ios', osx: 'macos', appletvos: 'tvos', xros: 'visionos' }[value] as Platform];
}

/** Render target kind of one file (not the run selection's `AssetKind` from @vitrin/schemas). */
export type RenderedKind = 'screenshot' | 'preview' | 'creative' | 'event';

/** One rendered file, resolved to its target (and therefore its store and platform). */
export interface RenderedAsset {
  file: string;
  locale: string;
  target: RenderTarget;
  kind: RenderedKind;
  /** Sort key inside a set (shot id `01`, `02`, …). */
  order: string;
}

const SHOT_FILE_RE = /^(\d{2})_([a-z0-9-]+)_([a-z0-9.-]+)\.(png|jpe?g)$/;
const PREVIEW_FILE_RE = /^(\d{2})_([A-Z0-9_]+)\.(mp4|mov|m4v)$/;

/**
 * Every rendered file with its target. The render manifest is the source of truth; without one, the
 * screenshot, preview and creative folders are scanned (file names carry the target id).
 * Files whose target id is not in `targets` are returned in `unknown`.
 */
export async function collectRenderedAssets(paths: AppPaths, targets: RenderTarget[], manifest?: RenderManifest): Promise<{ assets: RenderedAsset[]; unknown: string[] }> {
  const byId = new Map(targets.map((t) => [t.id, t]));
  const assets: RenderedAsset[] = [];
  const unknown: string[] = [];
  const add = (file: string, locale: string, targetId: string, order: string) => {
    const target = byId.get(targetId);
    if (!target) {
      unknown.push(file);
      return;
    }
    if (!existsSync(file)) return;
    assets.push({ file, locale, target, kind: target.kind, order });
  };

  if (manifest) {
    for (const i of manifest.images) add(i.file, i.locale, i.target, i.shot);
    for (const v of manifest.videos) add(v.file, v.locale, v.target, v.id);
  } else {
    for (const locale of await subdirs(paths.screenshots)) {
      for (const f of (await readdir(join(paths.screenshots, locale))).sort()) {
        const m = SHOT_FILE_RE.exec(f);
        if (m) add(join(paths.screenshots, locale, f), locale, m[3]!, m[1]!);
      }
    }
    for (const locale of await subdirs(paths.appPreviews)) {
      for (const f of (await readdir(join(paths.appPreviews, locale))).sort()) {
        const m = PREVIEW_FILE_RE.exec(f);
        if (m) add(join(paths.appPreviews, locale, f), locale, m[2]!.includes('IPAD') ? 'preview-ipad' : 'preview-iphone', m[1]!);
      }
    }
    for (const locale of await subdirs(paths.creative)) {
      for (const f of (await readdir(join(paths.creative, locale))).sort()) {
        // `<targetId>_<key>.png`; target ids may contain `-` but never `_`.
        const m = /^([a-z0-9.-]+)_(.+)\.(png|jpe?g|mp4)$/.exec(f);
        if (m && byId.has(m[1]!)) add(join(paths.creative, locale, f), locale, m[1]!, m[2]!);
      }
    }
  }
  assets.sort((a, b) => a.locale.localeCompare(b.locale) || a.target.id.localeCompare(b.target.id) || a.order.localeCompare(b.order));
  return { assets, unknown };
}

async function subdirs(dir: string): Promise<string[]> {
  if (!existsSync(dir)) return [];
  const out: string[] = [];
  for (const e of await readdir(dir, { withFileTypes: true })) if (e.isDirectory() && !e.name.startsWith('.')) out.push(e.name);
  return out.sort();
}

export interface RoutedAssets {
  /** App Store screenshots and App Previews per App Store version. */
  apple: Record<AppStorePlatform, RenderedAsset[]>;
  /** App Store creatives (product page header, search, In-App Events): App Asset Library. */
  appleCreatives: RenderedAsset[];
}

export function routeAssets(assets: RenderedAsset[]): RoutedAssets {
  const out: RoutedAssets = { apple: { ios: [], osx: [], appletvos: [], xros: [] }, appleCreatives: [] };
  for (const a of assets) {
    if (a.kind === 'creative' || a.kind === 'event') {
      out.appleCreatives.push(a);
      continue;
    }
    out.apple[appStorePlatformFor(a.target.platform)].push(a);
  }
  return out;
}
