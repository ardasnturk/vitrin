import { byteLength, tokenize } from '@vitrin/core';
import { keywordReach, NO_DEMAND_SCORE, type AuditLocale, type AuditTerm, type AuditVerdict, type Competitors, type KeywordCandidate, type KeywordPlan, type RankSnapshot } from '@vitrin/schemas';

export interface AuditListing {
  name?: string;
  subtitle?: string;
  keywords?: string;
}

export interface AuditInput {
  plan: KeywordPlan;
  listing?: AuditListing;
  listingSource: AuditLocale['listingSource'];
  /** Rating count of the app itself in this storefront. */
  ownRatings: number;
  competitors?: Competitors;
  /** Newer ranks than research day, when `vitrin rank` ran since. */
  ranks?: RankSnapshot;
}

/** How much a position is worth: the top 10 is what people see, and beyond 30 almost nobody scrolls. */
export function rankCredit(rank: number | null): number {
  if (rank === null) return 0;
  if (rank <= 3) return 1;
  if (rank <= 10) return 0.8;
  if (rank <= 30) return 0.4;
  return 0.1;
}

export function verdictFor(score: number): AuditVerdict {
  return score < 40 ? 'pivot' : score < 70 ? 'align' : 'fine';
}

/** A strong listing does not make up for ranking nowhere, so the total stays within 30 points of the rankings. */
export function totalAudit(rankings: number, listing: number, competition: number): number {
  return Math.round(Math.min(0.5 * rankings + 0.3 * listing + 0.2 * competition, rankings + 30));
}

/** All the words of `term` appear somewhere in the name, subtitle and keyword field (the store combines across them). */
export function termCovered(term: string, listing: AuditListing, locale: string): boolean {
  const have = new Set(tokenize([listing.name, listing.subtitle, (listing.keywords ?? '').replaceAll(',', ' ')].filter(Boolean).join(' '), locale));
  const words = tokenize(term, locale);
  return words.length > 0 && words.every((w) => have.has(w));
}

export function auditTerm(c: KeywordCandidate, rank: number | null, ownRatings: number, listing: AuditListing, locale: string): AuditTerm {
  return {
    term: c.term,
    volume: Math.round(c.popularity.score * 100),
    difficulty: Math.round(c.competition.score * 100),
    rank,
    reach: keywordReach({ competition: c.competition, ownRank: rank }, ownRatings),
    covered: termCovered(c.term, listing, locale),
  };
}

/** Apps found most often in the top 10 of the researched terms in one storefront; the app's own never appear here. */
export function topRivals(competitors: Competitors | undefined, storefront: string, n = 5): AuditLocale['rivals'] {
  return (competitors?.apps ?? [])
    .filter((a) => a.storefront === storefront)
    .map((a) => ({ trackId: a.trackId, name: a.name, top10: Object.values(a.rankBySeed).filter((r) => r <= 10).length, ratings: a.userRatingCount }))
    .filter((a) => a.top10 > 0)
    .sort((a, b) => b.top10 - a.top10 || (b.ratings ?? 0) - (a.ratings ?? 0))
    .slice(0, n);
}

/** Field fill and coverage of the terms with demand, weighted by how much demand each has. */
function listingScore(terms: AuditTerm[], listing: AuditListing | undefined): number | null {
  if (!listing || !terms.length) return null;
  const weight = terms.reduce((a, t) => a + t.volume, 0) || 1;
  const coverage = terms.reduce((a, t) => a + (t.covered ? t.volume : 0), 0) / weight;
  const subtitle = Math.min((listing.subtitle ?? '').length / 20, 1);
  // A public lookup cannot see the keyword field, so its fill is left out rather than counted as empty.
  const parts: Array<[number, number]> = [[coverage, 0.6], [subtitle, 0.2]];
  if (listing.keywords !== undefined) parts.push([Math.min(byteLength(listing.keywords) / 90, 1), 0.2]);
  const total = parts.reduce((a, [, w]) => a + w, 0);
  return Math.round((parts.reduce((a, [v, w]) => a + v * w, 0) / total) * 100);
}

function takeaways(a: Pick<AuditLocale, 'gaps' | 'sections' | 'ranked'>, listing: AuditListing | undefined): string[] {
  const out: string[] = [];
  if (!listing) out.push('There is no listing to judge in this language yet: write one, it is the biggest gain available.');
  const open = a.gaps.filter((g) => !g.covered && g.reach === 'reachable');
  if (open.length) out.push(`Add ${open.slice(0, 3).map((g) => `"${g.term}"`).join(', ')}: demand, reachable, and missing from the listing.`);
  const unranked = a.gaps.filter((g) => g.covered && g.reach === 'reachable');
  if (unranked.length) out.push(`${unranked.slice(0, 3).map((g) => `"${g.term}"`).join(', ')} ${unranked.length === 1 ? 'is' : 'are'} in the listing but outside the top 30: move ${unranked.length === 1 ? 'it' : 'them'} into the name or subtitle, or swap for a smaller term.`);
  if (listing && (listing.subtitle ?? '').length < 20) out.push('The subtitle is short: it is the second strongest field, use it.');
  if (listing?.keywords !== undefined && byteLength(listing.keywords) < 90) out.push('The keyword field has unused bytes.');
  if (!a.gaps.some((g) => g.reach === 'reachable') && a.gaps.length && !a.ranked.length) out.push('Every term with demand is held by far bigger apps: research smaller, more specific terms before rewriting.');
  return out.slice(0, 4);
}

/** Where one language stands. Pure: everything it needs was fetched before. */
export function auditLocale(o: AuditInput): AuditLocale {
  const { plan, listing, ownRatings } = o;
  const locale = plan.locale;
  const listed = listing ?? {};
  const rankOf = (c: KeywordCandidate): number | null => {
    const e = o.ranks?.entries.find((x) => x.locale === locale && x.term === c.term);
    return e ? e.rank : c.ownRank;
  };
  const demand = plan.candidates
    .filter((c) => c.popularity.score >= NO_DEMAND_SCORE && c.relevance !== 0)
    .map((c) => auditTerm(c, rankOf(c), ownRatings, listed, locale))
    .sort((a, b) => b.volume - a.volume || a.term.localeCompare(b.term));
  const rivals = topRivals(o.competitors, plan.storefront);
  const base = { locale, storefront: plan.storefront, listingSource: o.listingSource, rivals };
  const none: AuditLocale = { ...base, score: null, verdict: null, sections: { rankings: null, listing: null, competition: null }, ranked: [], gaps: [], takeaways: ['Nothing with measurable demand was found: run `vitrin research` with broader seeds.'] };
  if (!demand.length) return none;

  const weight = demand.reduce((a, t) => a + t.volume, 0) || 1;
  const rankings = Math.round((demand.reduce((a, t) => a + rankCredit(t.rank) * t.volume, 0) / weight) * 100);
  const competition = Math.round((demand.filter((t) => t.reach !== 'stretch').length / demand.length) * 100);
  const listScore = listingScore(demand.slice(0, 15), listing);
  const score = totalAudit(rankings, listScore ?? 0, competition);
  const ranked = demand.filter((t) => t.rank !== null && t.rank <= 10);
  const gaps = demand.filter((t) => t.rank === null || t.rank > 30);
  const sections = { rankings, listing: listScore, competition };
  return { ...base, score, verdict: verdictFor(score), sections, ranked, gaps, takeaways: takeaways({ gaps, sections, ranked }, listing) };
}

/** Mean of the locales that measured anything. */
export function auditTotal(locales: AuditLocale[]): number | null {
  const scores = locales.map((l) => l.score).filter((s): s is number => s !== null);
  return scores.length ? Math.round(scores.reduce((a, b) => a + b, 0) / scores.length) : null;
}
