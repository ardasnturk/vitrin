import type { StorefrontInfo } from '@vitrin/core';
import type { Competitors, CompetitorApp, KeywordCandidate, KeywordPlan, RankSnapshot } from '@vitrin/schemas';
import { describe, expect, it } from 'vitest';
import { rankHighlights, auditLocale, auditTotal, charmPrice, loadPpp, parseHints, pricingPlan, rivalsToTrack, shareFor, termCovered, topRivals, totalAudit, verdictFor, compareRanks, competitionScore, estimatePopularity, kmeans, median, nameTermFrequency, rgbToHex, titleShare, totalScore, trackedTerms } from '../src/index.js';

describe('keyword scoring', () => {
  it('computes median and competition', () => {
    expect(median([3, 1, 2])).toBe(2);
    expect(median([1, 2, 3, 4])).toBe(2.5);
    const empty = competitionScore(0, [], 0);
    expect(empty.score).toBe(0);
    const crowded = competitionScore(50, Array(10).fill(1_000_000), 1);
    expect(crowded.score).toBeGreaterThan(0.95);
    // A full result list alone is not competition: every real term returns the whole page.
    expect(competitionScore(50, Array(10).fill(10), 0).score).toBeLessThan(0.15);
    const results = [{ trackName: 'Habit Tracker' }, { trackName: 'Daily Habits' }, { trackName: 'Streaks' }, { trackName: 'Done' }];
    expect(titleShare('habit', results, 'en-US')).toBe(0.5);
  });

  it('leaves total null until Claude sets relevance', () => {
    const c = { relevance: null, popularity: { score: 0.8, source: 'estimate' as const }, competition: { resultCount: 10, top10MedianRatings: 10, score: 0.2 }, ownRank: null };
    expect(totalScore(c)).toBeNull();
    expect(totalScore({ ...c, relevance: 1 })).toBeGreaterThan(0.6);
  });

  it('gives no score to a term without demand, and lets a smaller term beat a crowded popular one', () => {
    const c = (popularity: number, competition: number) => ({ relevance: 1, popularity: { score: popularity, source: 'estimate' as const }, competition: { resultCount: 10, top10MedianRatings: 10, score: competition } });
    expect(totalScore(c(0, 0))).toBe(0); // a seed with no results
    expect(totalScore(c(0.05, 0))).toBeLessThan(totalScore(c(0.5, 0.8))!); // barely any demand loses to a real term
    expect(totalScore(c(0.3, 0.1))).toBeGreaterThan(totalScore(c(0.9, 0.9))!); // the smaller, open term wins
  });

  it('estimates popularity from result names and volume', () => {
    const results = [{ trackId: 1, trackName: 'Habit Tracker', userRatingCount: 200_000 }, { trackId: 2, trackName: 'Streaks', userRatingCount: 50_000 }];
    expect(estimatePopularity('habit', results, 'en-US')).toBeGreaterThan(estimatePopularity('zebra', results, 'en-US'));
  });

  it('counts name terms without stopwords', () => {
    const apps = [{ name: 'Habit Tracker: Daily Goals' }, { name: 'Daily Habit Tracker' }, { name: 'The Habit App' }] as CompetitorApp[];
    const terms = nameTermFrequency(apps, 'en-US');
    expect(terms[0]).toEqual({ term: 'habit', count: 3 });
    expect(terms.some((t) => t.term === 'the' || t.term === 'app')).toBe(false);
    expect(terms.find((t) => t.term === 'habit tracker')?.count).toBe(2);
  });
});

describe('rank tracking', () => {
  const c = (term: string, total: number | null, ownRank: number | null = null) => ({ term, relevance: 1, competition: { resultCount: 50, top10MedianRatings: 1, score: 0 }, popularity: { score: 0, source: 'estimate' as const }, total, ownRank });

  it('tracks the selected terms first, then the best-scored and already-ranked ones', () => {
    const plan = { locale: 'en-US', storefront: 'us', generatedAt: '', candidates: [c('water', 0.2), c('habit', 0.9), c('streak', null, 7), c('zzz', null)], selected: { name: ['Habit Tracker'], subtitle: [], keywords: ['goal'] } };
    expect(trackedTerms(plan, ['seed'])).toEqual(['habit tracker', 'goal', 'habit', 'water', 'streak']);
    expect(trackedTerms(undefined, ['seed', 'other'], 1)).toEqual(['seed']);
  });

  it('compares a snapshot with the previous one', () => {
    const entry = (term: string, rank: number | null) => ({ locale: 'en-US', storefront: 'us', term, rank, limit: 50 });
    const before = { date: '2026-10-01', bundleId: 'x', entries: [entry('habit', 12), entry('goal', null)] };
    const after = { date: '2026-10-15', bundleId: 'x', entries: [entry('habit', 5), entry('goal', 30), entry('new', 3)] };
    expect(compareRanks(before, after)).toEqual([
      { locale: 'en-US', term: 'habit', before: 12, after: 5, delta: 7 },
      { locale: 'en-US', term: 'goal', before: null, after: 30, delta: null },
      { locale: 'en-US', term: 'new', before: null, after: 3, delta: null },
    ]);
  });
});

describe('palette', () => {
  it('finds dominant colours deterministically', () => {
    const px: Array<[number, number, number]> = [...Array(70).fill([250, 10, 10]), ...Array(30).fill([10, 10, 250])];
    const res = kmeans(px, 2);
    expect(rgbToHex(res[0]!.color)).toBe('#FA0A0A');
    expect(res[0]!.weight).toBeCloseTo(0.7);
    expect(kmeans(px, 2)).toEqual(res);
  });
});

describe('audit', () => {
  const candidate = (term: string, popularity: number, competition: number, ownRank: number | null, median = 100): KeywordCandidate => ({ term, relevance: 1, popularity: { score: popularity, source: 'estimate' }, competition: { resultCount: 50, top10MedianRatings: median, score: competition }, total: 0.5, ownRank });
  const plan = (candidates: KeywordCandidate[]): KeywordPlan => ({ locale: 'en-US', storefront: 'us', generatedAt: new Date().toISOString(), candidates });
  const listing = { name: 'Habit Tracker: Ritim', subtitle: 'Daily routine and streak goals', keywords: 'water,sleep,focus,journal,mood,reminder,planner,morning,evening,workout,reading,meditate,health' };

  it('caps the score by the rankings: a perfect listing nobody finds is not a good listing', () => {
    expect(totalAudit(0, 100, 100)).toBe(30);
    expect(totalAudit(100, 100, 100)).toBe(100);
    expect(verdictFor(30)).toBe('pivot');
    expect(verdictFor(55)).toBe('align');
    expect(verdictFor(80)).toBe('fine');
  });

  it('weighs ranks by demand and lists what is missing', () => {
    const a = auditLocale({ plan: plan([candidate('habit tracker', 0.8, 0.5, 4), candidate('water log', 0.5, 0.2, null), candidate('streak', 0.4, 0.3, 45), candidate('nobody', 0.02, 0, null)]), listing, listingSource: 'live', ownRatings: 500 });
    expect(a.sections.rankings).toBeGreaterThan(30);
    expect(a.ranked.map((t) => t.term)).toEqual(['habit tracker']);
    expect(a.gaps.map((t) => t.term)).toEqual(['water log', 'streak']);
    expect(a.gaps[0]).toMatchObject({ volume: 50, difficulty: 20, covered: false, reach: 'reachable' });
    expect(a.gaps[1]!.covered).toBe(true);
    expect(a.takeaways[0]).toContain('water log');
    expect(a.score).toBe(totalAudit(a.sections.rankings!, a.sections.listing!, a.sections.competition!));
  });

  it('prefers a newer rank snapshot over research day', () => {
    const ranks: RankSnapshot = { date: '2026-11-01', bundleId: 'a.b', entries: [{ locale: 'en-US', storefront: 'us', term: 'streak', rank: 2, limit: 50 }] };
    const a = auditLocale({ plan: plan([candidate('streak', 0.4, 0.3, null)]), listing, listingSource: 'live', ownRatings: 0, ranks });
    expect(a.ranked[0]!.rank).toBe(2);
  });

  it('does not count a keyword field a public lookup cannot see as empty', () => {
    const c = [candidate('habit', 0.5, 0.1, null)];
    const open = auditLocale({ plan: plan(c), listing: { name: 'Habit', subtitle: 'A long enough subtitle here' }, listingSource: 'live', ownRatings: 0 });
    expect(open.sections.listing).toBe(100);
    expect(open.takeaways.join()).not.toContain('keyword field');
  });

  it('says so when nothing can be judged', () => {
    const a = auditLocale({ plan: plan([candidate('nobody', 0.01, 0, null)]), listingSource: 'none', ownRatings: 0 });
    expect(a.score).toBeNull();
    expect(auditTotal([a])).toBeNull();
  });

  it('marks a term as covered across fields, and a term held by giants as a stretch', () => {
    expect(termCovered('routine habit', listing, 'en-US')).toBe(true);
    expect(termCovered('habit journey', listing, 'en-US')).toBe(false);
    const a = auditLocale({ plan: plan([candidate('fitness', 0.9, 0.9, null, 2_000_000)]), listing, listingSource: 'live', ownRatings: 100 });
    expect(a.gaps[0]!.reach).toBe('stretch');
    expect(a.sections.competition).toBe(0);
  });
});

describe('rivals', () => {
  const app = (trackId: number, name: string, rankBySeed: Record<string, number>, storefront = 'us') => ({ trackId, name, storefront, rankBySeed, userRatingCount: trackId }) as unknown as CompetitorApp;
  const competitors = { apps: [app(1, 'One', { a: 3, b: 40 }), app(2, 'Two', { a: 1, b: 2 }), app(3, 'Three', { a: 30 }), app(4, 'Four', { a: 1 }, 'de')] } as unknown as Competitors;

  it('ranks rivals by how often they hold the top 10 of one storefront', () => {
    expect(topRivals(competitors, 'us').map((r) => [r.name, r.top10])).toEqual([['Two', 2], ['One', 1]]);
  });

  it('keeps following configured and earlier rivals when research is gone', () => {
    const previous = { date: 'x', bundleId: 'a', entries: [], rivalNames: { '9': 'Nine' } } as RankSnapshot;
    const rivals = rivalsToTrack([7], previous, undefined, ['us']);
    expect([...rivals.keys()]).toEqual([7, 9]);
    expect([...rivalsToTrack([], undefined, competitors, ['us']).values()]).toEqual(['Two', 'One']);
  });
});

describe('search hints', () => {
  it('reads the terms out of the plist and decodes entities', () => {
    const plist = '<dict><key>term</key><string>habit &amp; goals</string><key>url</key><string>x</string></dict><dict><key>term</key>\n  <string>habit tracker</string></dict><dict><key>term</key><string>habit tracker</string></dict>';
    expect(parseHints(plist)).toEqual(['habit & goals', 'habit tracker']);
  });
});

describe('pricing', () => {
  const stores = [{ code: 'us', country: 'US' }, { code: 'tr', country: 'Türkiye' }, { code: 'in', country: 'India' }, { code: 'xx', country: 'Nowhere' }] as StorefrontInfo[];
  const data = { source: 't', gni: { us: 80000, tr: 40000, in: 8000 } };
  const opts = { base: 10, baseCountry: 'us', method: 'ppp' as const, floor: 0.25, ceiling: 1 };

  it('follows purchasing power within the floor', () => {
    const rows = Object.fromEntries(pricingPlan(opts, data, stores).rows.map((r) => [r.storefront, r]));
    expect(rows.us!.share).toBe(1);
    expect(rows.tr!.share).toBe(0.5);
    expect(rows.in!.share).toBe(0.25); // 10% of the base income, held at the floor
    expect(rows.in!.price).toBe(2.99);
    expect(rows.xx).toMatchObject({ share: 1, measured: false });
  });

  it('snaps to five levels with tiers', () => {
    expect(shareFor(0.9, 'tiers')).toBe(1);
    expect(shareFor(0.5, 'tiers')).toBe(0.6);
    expect(shareFor(0.1, 'tiers')).toBe(0.25);
  });

  it('refuses a base country without data', () => {
    expect(() => pricingPlan({ ...opts, baseCountry: 'xx' }, data, stores)).toThrow(/income data/);
  });

  it('ships income data for almost every storefront', () => {
    expect(Object.keys(loadPpp().gni).length).toBeGreaterThan(150);
    expect(charmPrice(4.9)).toBe(4.99);
    expect(charmPrice(0.5)).toBe(0.5);
  });
});

describe('rank highlights', () => {
  const row = (term: string, before: number | null, after: number | null) => ({ locale: 'en-US', term, before, after, delta: before !== null && after !== null ? before - after : null });

  it('tells big moves and crossings of the top 10, not noise', () => {
    const h = rankHighlights([row('a', 12, 9), row('b', 8, 30), row('c', 40, 20), row('d', 20, 22), row('e', null, 7), row('f', 4, null), row('g', null, null)]);
    expect(h.enteredTop10.map((c) => c.term)).toEqual(['a', 'e']);
    expect(h.leftTop10.map((c) => c.term)).toEqual(['b', 'f']);
    expect([h.up, h.down]).toEqual([1, 1]);
  });
});
