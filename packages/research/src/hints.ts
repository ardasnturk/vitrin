import { cachedFetch, type CachedFetchOptions } from '@vitrin/core';

/** Apple's numeric storefront ids for the hints endpoint; a country outside this list has no suggestions. */
export const STOREFRONT_IDS: Record<string, number> = {
  ae: 143481, ar: 143505, at: 143445, au: 143460, be: 143446, br: 143503, ca: 143455, ch: 143459, cl: 143483, cn: 143465, co: 143501, cz: 143489, de: 143443, dk: 143458, eg: 143516, es: 143454, fi: 143447, fr: 143442, gb: 143444, gr: 143448, hk: 143463, hu: 143482, id: 143476, ie: 143449, il: 143491, in: 143467, it: 143450, jp: 143462, kr: 143466, mx: 143468, my: 143473, nl: 143452, no: 143457, nz: 143461, ph: 143474, pl: 143478, pt: 143453, ro: 143487, ru: 143469, sa: 143479, se: 143456, sg: 143464, th: 143475, tr: 143480, tw: 143470, ua: 143492, us: 143441, vn: 143471, za: 143472,
};

const ENTITIES: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };

/** The `term` strings of the plist Apple answers with, in its order. */
export function parseHints(plist: string): string[] {
  const out: string[] = [];
  for (const m of plist.matchAll(/<key>term<\/key>\s*<string>([^<]*)<\/string>/g)) {
    out.push(m[1]!.replace(/&(\w+);/g, (all, e: string) => ENTITIES[e] ?? all).trim());
  }
  return [...new Set(out.filter(Boolean))];
}

/**
 * What the App Store's search box suggests for what someone is typing: real searches, in that country's own words,
 * without any paid data source. The endpoint is undocumented, so a failure is an empty list, never an error.
 */
export async function searchHints(term: string, storefront: string, opts: CachedFetchOptions): Promise<string[]> {
  const id = STOREFRONT_IDS[storefront];
  if (!id) return [];
  const url = `https://search.itunes.apple.com/WebObjects/MZSearchHints.woa/wa/hints?${new URLSearchParams({ clientApplication: 'Software', term })}&sf=${id}`;
  try {
    const buf = await cachedFetch(url, { ...opts, headers: { 'User-Agent': 'iTunes/12.13 (Macintosh; OS X 15)', 'X-Apple-Store-Front': `${id}-1,29`, ...opts.headers } });
    return parseHints(buf.toString('utf8'));
  } catch {
    return [];
  }
}
