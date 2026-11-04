import type { AssetKind, Platform, RenderTarget, VitrinConfig } from '@vitrin/schemas';
import { applePlatformsOf, appStorePlatformFor, type AppStorePlatform, type RenderedAsset } from './platforms.js';

/**
 * How a set of images or videos reaches the store in this run.
 * - `per-display-type`: one set per localization and display type is replaced (`asc screenshots|video-previews
 *   upload --replace`, the App Asset Library for iPhone Duo); other sets stay.
 * - `skip`: not part of the run; the store content stays untouched.
 */
export type ReplaceMode = 'per-display-type' | 'skip';

export interface PlatformScope {
  platform: AppStorePlatform;
  /** Shipping platforms that live in this App Store version (ios + watchos for `ios`). */
  covers: Platform[];
  /** Covered platforms the user selected for this run. */
  selectedPlatforms: Platform[];
  metadata: boolean;
  screenshots: ReplaceMode;
  previews: ReplaceMode;
  /** Target ids uploaded in this run. */
  screenshotTargets: string[];
  previewTargets: string[];
  /** What stays untouched, in words, for the plan. */
  untouched: string[];
}

export interface StoreScope {
  /** Asset kinds selected for this run (config.selection.assets, default all). */
  assets: AssetKind[];
  apple: PlatformScope[];
}

export const ALL_ASSET_KINDS: AssetKind[] = ['metadata', 'screenshots', 'previews', 'creatives', 'events'];

/**
 * Resolves what this run uploads and what it must leave alone, from the shipping platforms, the user's
 * `config.selection`, the rendered files and the targets that are enabled for the app. The selected display types
 * are always replaced one set at a time (asc CLI, App Asset Library for iPhone Duo); every other set stays as it is
 * in App Store Connect.
 */
export function resolveScope(opts: {
  shipping: Platform[];
  selection?: VitrinConfig['selection'];
  assets: RenderedAsset[];
  /** Targets enabled for the app (core enabledTargets); used to decide whether a set is complete. */
  enabledTargets: RenderTarget[];
  locales: string[];
}): StoreScope {
  const kinds = opts.selection?.assets?.length ? opts.selection.assets : ALL_ASSET_KINDS;
  const selected = opts.shipping.filter((p) => !opts.selection?.platforms?.length || opts.selection.platforms.includes(p));
  const locales = new Set(opts.locales);
  const formats = opts.selection?.targets?.length ? new Set(opts.selection.targets) : undefined;
  const scope: StoreScope = { assets: kinds, apple: [] };

  for (const p of applePlatformsOf(opts.shipping)) {
    const covers = opts.shipping.filter((s) => appStorePlatformFor(s) === p);
    const selCovers = covers.filter((s) => selected.includes(s));
    const ps: PlatformScope = { platform: p, covers, selectedPlatforms: selCovers, metadata: false, screenshots: 'skip', previews: 'skip', screenshotTargets: [], previewTargets: [], untouched: [] };
    scope.apple.push(ps);
    if (!selCovers.length) {
      ps.untouched.push(`${covers.join(', ')} not selected: text, screenshots and previews stay untouched`);
      continue;
    }
    const notSelected = covers.filter((s) => !selCovers.includes(s));
    if (notSelected.length) ps.untouched.push(`${notSelected.join(', ')} not selected: its screenshots and previews stay untouched`);
    ps.metadata = kinds.includes('metadata');
    if (!ps.metadata) ps.untouched.push('text metadata not selected: stays untouched');

    for (const [kind, assetKind, field] of [
      ['screenshot', 'screenshots', 'screenshots'],
      ['preview', 'previews', 'previews'],
    ] as const) {
      if (!kinds.includes(assetKind)) {
        ps.untouched.push(`${assetKind} not selected: stay untouched`);
        continue;
      }
      const files = opts.assets.filter((a) => a.kind === kind && appStorePlatformFor(a.target.platform) === p && selCovers.includes(a.target.platform) && locales.has(a.locale) && (!formats || formats.has(a.target.id)));
      if (!files.length) continue;
      const ids = [...new Set(files.map((a) => a.target.id))].sort();
      const expected = opts.enabledTargets.filter((t) => t.kind === kind && covers.includes(t.platform)).map((t) => t.id);
      ps[field] = 'per-display-type';
      if (field === 'screenshots') ps.screenshotTargets = ids;
      else ps.previewTargets = ids;
      const others = expected.filter((id) => !ids.includes(id));
      ps.untouched.push(`${assetKind}: only ${ids.join(', ')} replaced${others.length ? `; ${others.join(', ')} and every other display type stay untouched` : '; other display types stay untouched'}`);
    }
  }

  return scope;
}

/** The files this run replaces, one display type at a time (asc CLI or App Asset Library). */
export function perDisplayTypeAssetsFor(scope: PlatformScope, assets: RenderedAsset[]): RenderedAsset[] {
  return assets.filter(
    (a) =>
      appStorePlatformFor(a.target.platform) === scope.platform &&
      ((a.kind === 'screenshot' && scope.screenshots === 'per-display-type' && scope.screenshotTargets.includes(a.target.id)) ||
        (a.kind === 'preview' && scope.previews === 'per-display-type' && scope.previewTargets.includes(a.target.id))),
  );
}
