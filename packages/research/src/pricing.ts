import { DATA_DIR, loadStorefronts } from '@vitrin/core';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

export type PricingMethod = 'ppp' | 'tiers';

export interface PricingOptions {
  /** Price in the base country, in its currency. */
  base: number;
  baseCountry: string;
  method: PricingMethod;
  /** The lowest and highest share of the base price any country gets. */
  floor: number;
  ceiling: number;
}

export interface PricingRow {
  storefront: string;
  country: string;
  /** Share of the base price. */
  share: number;
  /** Target in the base country's currency; App Store Connect still snaps it to a local price point. */
  price: number;
  /** false = no income data for this country, so it keeps the full base price. */
  measured: boolean;
}

export interface PricingPlan {
  generatedAt: string;
  options: PricingOptions;
  source: string;
  rows: PricingRow[];
}

interface PppData {
  updatedAt: string;
  source: string;
  /** Storefront code → GNI per capita, PPP (international $). */
  gni: Record<string, number>;
}

let cache: PppData | undefined;
export function loadPpp(): PppData {
  cache ??= JSON.parse(readFileSync(join(DATA_DIR, 'ppp.json'), 'utf8')) as PppData;
  return cache;
}

const TIERS: Array<[number, number]> = [[0.8, 1], [0.55, 0.8], [0.35, 0.6], [0.18, 0.4], [0, 0.25]];

/** The share of a relative income: as measured, or snapped to the five tiers. */
export function shareFor(relative: number, method: PricingMethod): number {
  return method === 'tiers' ? TIERS.find(([min]) => relative >= min)![1] : relative;
}

/** Ends in .99 like prices people expect, except for prices so small that would move them much. */
export function charmPrice(n: number): number {
  return n < 1 ? Math.round(n * 100) / 100 : Math.max(0.99, Math.round(n) - 0.01);
}

/** Fair price per country from purchasing power. A proposal only: nothing here reaches App Store Connect. */
export function pricingPlan(o: PricingOptions, data: Pick<PppData, 'gni' | 'source'> = loadPpp(), stores = loadStorefronts()): PricingPlan {
  const baseGni = data.gni[o.baseCountry];
  if (!baseGni) throw new Error(`No income data for "${o.baseCountry}": pick another base country.`);
  const rows = stores.map((s): PricingRow => {
    const gni = data.gni[s.code];
    const share = gni ? Math.min(o.ceiling, Math.max(o.floor, shareFor(gni / baseGni, o.method))) : 1;
    return { storefront: s.code, country: s.country, share: Math.round(share * 100) / 100, price: charmPrice(o.base * share), measured: Boolean(gni) };
  });
  return { generatedAt: new Date().toISOString(), options: o, source: data.source, rows: rows.sort((a, b) => b.share - a.share || a.country.localeCompare(b.country)) };
}
