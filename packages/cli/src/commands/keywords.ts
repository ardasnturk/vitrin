import { log } from '@vitrin/core';
import { competitionScore, estimatePopularity, ItunesClient, searchHints, STOREFRONT_IDS, titleShare } from '@vitrin/research';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import pc from 'picocolors';
import { EXIT } from '../context.js';

export interface KeywordRow {
  storefront: string;
  term: string;
  /** Came from the App Store's search box, not from the command line. */
  suggested: boolean;
  volume: number;
  difficulty: number;
  /** Median ratings of the top 10, the size of what you would have to pass. */
  top10Ratings: number;
  top: string[];
}

export interface KeywordsOptions {
  terms: string[];
  storefronts: string[];
  hints: boolean;
  max: number;
  json?: boolean;
}

/** `vitrin keywords`: try an idea in any country before there is an app or a project. */
export async function keywordsCommand(o: KeywordsOptions): Promise<number> {
  const http = { cacheDir: join(tmpdir(), 'vitrin-keywords'), ttlHours: 24, minIntervalMs: 3100 };
  const itunes = new ItunesClient(http);
  const rows: KeywordRow[] = [];
  for (const storefront of o.storefronts) {
    const given = o.terms.map((t) => t.toLowerCase());
    const suggested: string[] = [];
    if (o.hints) {
      if (!STOREFRONT_IDS[storefront]) log.warn(`No search suggestions for ${storefront.toUpperCase()}: only the given terms are scored.`);
      for (const term of given) suggested.push(...(await searchHints(term, storefront, { ...http, minIntervalMs: 500 })));
    }
    for (const term of [...new Set([...given, ...suggested.map((t) => t.toLowerCase())])].slice(0, o.max)) {
      const { results } = await itunes.search(term, storefront, 50);
      const top = results.slice(0, 10);
      const locale = 'en-US';
      const competition = competitionScore(results.length, top.map((r) => r.userRatingCount ?? 0), titleShare(term, results, locale));
      rows.push({ storefront, term, suggested: !given.includes(term), volume: Math.round(estimatePopularity(term, results, locale) * 100), difficulty: Math.round(competition.score * 100), top10Ratings: competition.top10MedianRatings, top: top.slice(0, 3).map((r) => r.trackName) });
    }
  }
  if (o.json) {
    console.log(JSON.stringify(rows, null, 2));
    return EXIT.OK;
  }
  for (const storefront of o.storefronts) {
    log.info(pc.bold(storefront.toUpperCase()));
    for (const r of rows.filter((x) => x.storefront === storefront).sort((a, b) => b.volume - b.difficulty - (a.volume - a.difficulty))) {
      log.info(`  ${r.term}${r.suggested ? pc.dim(' (suggested)') : ''}: vol ${r.volume}, diff ${r.difficulty}  ${pc.dim(r.top[0] ?? '')}`);
    }
  }
  log.dim('Volume and difficulty are estimates from the apps that rank for a term, not Apple search counts.');
  return EXIT.OK;
}
