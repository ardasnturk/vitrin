import type { AppPaths } from '@vitrin/core';
import type { LocaleMetadata, Platform, VitrinConfig } from '@vitrin/schemas';
import type { AscClient } from './asc-client.js';
import { buildPlan } from './plan.js';

/**
 * After an upload: read App Store Connect back and list each text field that still differs from the local files,
 * for every Apple platform version plus the shared app info.
 */
export async function readBack(opts: {
  paths: AppPaths;
  config: VitrinConfig;
  bundleId: string;
  metadata: LocaleMetadata[];
  client?: AscClient;
  platforms?: Platform[];
}): Promise<string[]> {
  const out: string[] = [];
  // Only what this run uploaded is compared (config.selection): unselected text was left as it is in the store.
  const sel = opts.config.selection;
  if (sel?.assets?.length && !sel.assets.includes('metadata')) return out;
  const platforms = (opts.platforms ?? []).filter((p) => !sel?.platforms?.length || sel.platforms.includes(p));
  if (opts.client && (!opts.platforms || platforms.length)) {
    const plan = await buildPlan({ ...opts, platforms: opts.platforms ? platforms : undefined, include: { creatives: false, cpp: false, events: false } });
    const diffs = plan.items.filter((i) => i.area === 'metadata' && i.change !== 'unchanged');
    out.push(...plan.blockers, ...diffs.map((d) => `${d.platform ? `${d.platform} ` : ''}${d.locale} ${d.field}: ASC “${d.remote ?? '(empty)'}”, local “${d.local}”`));
  }
  return out;
}
