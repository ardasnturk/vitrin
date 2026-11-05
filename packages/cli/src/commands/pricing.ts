import { existsSync, log, writeJson } from '@vitrin/core';
import { pricingPlan, type PricingMethod } from '@vitrin/research';
import { join } from 'node:path';
import pc from 'picocolors';
import { EXIT } from '../context.js';

export interface PricingCommandOptions {
  cwd?: string;
  base: number;
  country: string;
  method: string;
  floor: number;
  ceiling: number;
  json?: boolean;
}

/** `vitrin pricing`: a proposal to review. Vitrin does not change prices; set them in App Store Connect. */
export async function pricingCommand(o: PricingCommandOptions): Promise<number> {
  if (!(o.base > 0)) throw new Error('--base needs a price above 0.');
  if (o.method !== 'ppp' && o.method !== 'tiers') throw new Error('--method is ppp or tiers.');
  if (!(o.floor > 0 && o.floor <= o.ceiling && o.ceiling <= 1)) throw new Error('--floor and --ceiling are shares of the base price: 0 < floor ≤ ceiling ≤ 1.');
  const plan = pricingPlan({ base: o.base, baseCountry: o.country, method: o.method as PricingMethod, floor: o.floor, ceiling: o.ceiling });
  if (o.json) {
    console.log(JSON.stringify(plan, null, 2));
    return EXIT.OK;
  }
  const groups = new Map<number, string[]>();
  for (const r of plan.rows) groups.set(r.price, [...(groups.get(r.price) ?? []), r.storefront.toUpperCase()]);
  for (const [price, codes] of [...groups].sort((a, b) => b[0] - a[0])) log.info(`${pc.bold(price.toFixed(2))}  ${pc.dim(`${codes.length}:`)} ${codes.slice(0, 12).join(' ')}${codes.length > 12 ? ' …' : ''}`);
  const missing = plan.rows.filter((r) => !r.measured).map((r) => r.country);
  if (missing.length) log.dim(`No income data, full price: ${missing.join(', ')}`);
  const metadata = join(o.cwd ?? process.cwd(), 'metadata');
  if (existsSync(metadata)) {
    await writeJson(join(metadata, 'pricing', 'plan.json'), plan);
    log.ok('Saved metadata/pricing/plan.json');
  }
  log.dim('A proposal in the base currency: App Store Connect snaps each one to a local price point. Nothing was changed.');
  return EXIT.OK;
}
