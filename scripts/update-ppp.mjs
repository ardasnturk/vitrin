#!/usr/bin/env node
// Refreshes data/ppp.json (used by `vitrin pricing`) from the World Bank: GNI per capita, PPP, latest year per country.
import { readFileSync, writeFileSync } from 'node:fs';

const res = await fetch('https://api.worldbank.org/v2/country/all/indicator/NY.GNP.PCAP.PP.CD?format=json&per_page=400&mrnev=1');
const [meta, rows] = await res.json();
if (!Array.isArray(rows)) throw new Error('Unexpected World Bank response');
const { storefronts } = JSON.parse(readFileSync('data/storefront-languages.json', 'utf8'));
const codes = new Set(storefronts.map((s) => s.code));
const gni = {};
for (const r of rows) {
  const code = r.country.id.toLowerCase();
  if (codes.has(code) && typeof r.value === 'number') gni[code] = Math.round(r.value);
}
const out = { updatedAt: meta.lastupdated, source: 'World Bank, GNI per capita PPP (NY.GNP.PCAP.PP.CD), CC BY 4.0', gni: Object.fromEntries(Object.entries(gni).sort()) };
writeFileSync('data/ppp.json', `${JSON.stringify(out, null, 2)}\n`);
console.log(`${Object.keys(gni).length} of ${codes.size} storefronts`);
