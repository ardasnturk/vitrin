import { VitrinConfig, type AppMetadata, type AppProfile, type Competitors, type KeywordPlan, type LiveListing, type LocaleMetadata } from '@vitrin/schemas';
import { describe, expect, it } from 'vitest';
import { containsTerm, looksLikeKeywordList, pluralForms, termCovered, validateText } from '../src/index.js';

const config = VitrinConfig.parse({
  app: { locales: ['tr', 'en-US'], primaryLocale: 'tr' },
  urls: { support: 'https://ritim.app/support', privacy: 'https://ritim.app/privacy' },
  copyrightHolder: 'JASTech',
});

const profile = {
  app: { displayName: 'Ritim' },
  features: [
    { id: 'streaks', title: 'Seriler', evidence: [{ path: 'a.swift' }] },
    { id: 'charts', title: 'Grafikler', evidence: [{ path: 'b.swift' }] },
  ],
} as unknown as AppProfile;

const appMeta: AppMetadata = { copyright: '2026 JASTech', primaryCategory: 'HEALTH_AND_FITNESS', secondaryCategory: 'PRODUCTIVITY', primarySubcategories: [], secondarySubcategories: [], reviewNotes: '' };

function meta(over: Partial<LocaleMetadata> & { locale: string }): LocaleMetadata {
  return {
    name: 'Ritim: Alışkanlık Takibi',
    subtitle: 'Günlük rutin ve seri',
    promotionalText: '',
    description: 'Ritim ile alışkanlıklarını her gün tek dokunuşla işaretle.\nSerilerini koru, grafiklerle ilerlemeni gör.\nHatırlatıcılar seni yolda tutar.',
    keywords: 'hedef,plan,motivasyon,takvim,hatırlatıcı',
    whatsNew: '',
    claims: [{ text: 'Serilerini koru', featureIds: ['streaks'] }],
    ...over,
  } as LocaleMetadata;
}

function run(locales: LocaleMetadata[], extra: { competitors?: Competitors; app?: AppMetadata } = {}) {
  return validateText({ config, profile, competitors: extra.competitors, appMetadata: extra.app ?? appMeta, locales: new Map(locales.map((l) => [l.locale, l])) });
}

const codes = (r: ReturnType<typeof run>) => r.issues.items.map((i) => i.code);

describe('text limits', () => {
  it('passes a clean locale', () => {
    const r = run([meta({ locale: 'tr' }), meta({ locale: 'en-US', name: 'Ritim: Habit Tracker', subtitle: 'Daily routine and streaks', keywords: 'goal,planner,motivation,calendar,reminder', description: 'Check in your habits with one tap every day.\nKeep your streaks.\nSee progress in charts.', claims: [{ text: 'Keep your streaks', featureIds: ['streaks'] }] })]);
    expect(r.issues.errors).toEqual([]);
  });

  it('measures the keyword field in bytes, not characters', () => {
    // 50 Turkish characters "ş" = 100 bytes → ok; one more letter → 101 bytes.
    const ok = 'şş'.repeat(25);
    expect(run([meta({ locale: 'tr', keywords: ok })]).measurements.tr!.keywords!.bytes).toBe(100);
    const r = run([meta({ locale: 'tr', keywords: ok + 'a' })]);
    expect(codes(r)).toContain('text.too-long');
    expect(r.measurements.tr!.keywords).toMatchObject({ bytes: 101, chars: 51, unit: 'bytes' });
  });

  it('counts name length in graphemes', () => {
    expect(codes(run([meta({ locale: 'tr', name: 'A' })]))).toContain('text.too-short');
    expect(codes(run([meta({ locale: 'tr', name: 'Ritim: Alışkanlık ve Rutin Takibi' })]))).toContain('text.too-long');
  });

  it('rejects HTML and missing required fields', () => {
    const c = codes(run([meta({ locale: 'tr', description: '<b>Merhaba</b> dünya, bu bir açıklamadır.' })]));
    expect(c).toContain('text.html');
    expect(codes(run([meta({ locale: 'tr', keywords: '' })]))).toContain('text.required');
  });
});

describe('ASO rules', () => {
  it('flags subtitle words repeated from the name', () => {
    expect(codes(run([meta({ locale: 'tr', subtitle: 'Alışkanlık ve seri' })]))).toContain('aso.subtitle-repeats-name');
  });

  it('flags keyword problems', () => {
    const c = codes(run([meta({ locale: 'tr', keywords: 'hedef, plan,ab,hedef,ritim,jastech,iphone' })]));
    expect(c).toContain('keywords.spaces');
    expect(c).toContain('keywords.too-short');
    expect(c).toContain('keywords.duplicate');
    expect(c).toContain('keywords.repeats-name');
    expect(c).toContain('keywords.developer-name');
    expect(c).toContain('keywords.apple-trademark');
  });

  it('warns on singular/plural pairs', () => {
    expect(codes(run([meta({ locale: 'en-US', name: 'Ritim', subtitle: 'Daily', keywords: 'goal,goals,planner', description: 'Long enough description for the hook line here.' })]))).toContain('keywords.plural');
    expect(pluralForms('hedef', 'tr')).toContain('hedefler');
  });

  it('rejects price and unproven superlatives in strict fields', () => {
    const c = codes(run([meta({ locale: 'tr', subtitle: 'En iyi ücretsiz rutin' })]));
    expect(c).toContain('text.price');
    expect(c).toContain('text.superlative');
    const en = codes(run([meta({ locale: 'en-US', name: 'Ritim', subtitle: '#1 habit app, free', keywords: 'goal', description: 'Long enough description for the hook line here.' })]));
    expect(en).toContain('text.price');
    expect(en).toContain('text.superlative');
  });

  it('rejects competitor brand names', () => {
    const competitors = { apps: [{ name: 'Streaks: Habit Tracker', sellerName: 'Crunchy Bagel' }] } as unknown as Competitors;
    const c = codes(run([meta({ locale: 'tr', description: 'Streaks uygulamasına alternatif, sade bir takipçi. Uzun açıklama.' })], { competitors }));
    expect(c).toContain('text.competitor-brand');
  });

  it('only warns about price in promotional text', () => {
    const r = run([meta({ locale: 'tr', promotionalText: 'Bu hafta indirim var' })]);
    expect(r.issues.items.find((i) => i.code === 'text.price' && i.field === 'promotionalText')?.severity).toBe('warning');
  });

  it('checks claims against features', () => {
    const c = codes(run([meta({ locale: 'tr', claims: [{ text: 'Apple Watch ile', featureIds: ['apple-watch'] }] })]));
    expect(c).toContain('claim.unknown-feature');
  });

  it('checks copyright format', () => {
    expect(codes(run([meta({ locale: 'tr' })], { app: { ...appMeta, copyright: '© JASTech' } }))).toContain('copyright.format');
  });
});

describe('keyword plan and field usage', () => {
  const candidate = (term: string, over: Partial<KeywordPlan['candidates'][number]> = {}) => ({
    term,
    relevance: 0.9,
    competition: { resultCount: 50, top10MedianRatings: 100, score: 0.3 },
    popularity: { score: 0.6, source: 'estimate' as const },
    total: 0.5,
    ownRank: null,
    ...over,
  });
  const plan = (over: Partial<KeywordPlan> = {}): KeywordPlan => ({ locale: 'tr', storefront: 'tr', generatedAt: '2026-10-27T00:00:00Z', candidates: [candidate('hedef')], ...over });
  const withPlan = (m: LocaleMetadata, p: KeywordPlan, live?: LiveListing) =>
    validateText({ config, profile, appMetadata: appMeta, locales: new Map([[m.locale, m]]), keywordPlans: new Map([[m.locale, p]]), live }).issues.items.map((i) => i.code);

  it('covers multi-word terms across the indexed fields', () => {
    expect(termCovered('alışkanlık takibi', meta({ locale: 'tr' }), 'tr')).toBe(true);
    expect(termCovered('alışkanlık hedef', meta({ locale: 'tr' }), 'tr')).toBe(true);
    expect(termCovered('su takibi', meta({ locale: 'tr' }), 'tr')).toBe(false);
  });

  it('asks for relevance and a selection, and checks the selection against the fields', () => {
    const c = withPlan(meta({ locale: 'tr' }), plan({ candidates: [candidate('hedef', { relevance: null, total: null })] }));
    expect(c).toContain('keywords.plan-unscored');
    expect(c).toContain('keywords.plan-unselected');
    const mismatch = withPlan(meta({ locale: 'tr' }), plan({ selected: { name: ['su takibi'], subtitle: ['rutin'], keywords: ['hedef', 'meditasyon'] } }));
    expect(mismatch.filter((x) => x === 'keywords.plan-mismatch')).toHaveLength(2);
  });

  it('warns when a term the app ranks for is dropped, and lists best candidates left out', () => {
    const c = withPlan(meta({ locale: 'tr' }), plan({ candidates: [candidate('su takibi', { ownRank: 4 }), candidate('hedef', { ownRank: 2 })] }));
    expect(c.filter((x) => x === 'keywords.drops-ranked-term')).toHaveLength(1);
    expect(c).toContain('keywords.top-unused');
  });

  it('shows what changed against the live keyword field', () => {
    const live: LiveListing = { generatedAt: '2026-10-27T00:00:00Z', source: 'asc', locales: { tr: { keywords: 'hedef,su,günlük' } } };
    const r = validateText({ config, profile, appMetadata: appMeta, locales: new Map([['tr', meta({ locale: 'tr' })]]), live }).issues.items.find((i) => i.code === 'keywords.live-diff');
    expect(r?.message).toContain('removed su');
    expect(r?.message).toContain('added plan');
  });

  it('warns on an empty or short subtitle, a brand-only name and an underused keyword field', () => {
    const c = codes(run([meta({ locale: 'tr', name: 'Ritim', subtitle: '', keywords: 'hedef,plan' })]));
    expect(c).toContain('aso.subtitle-empty');
    expect(c).toContain('aso.name-brand-only');
    expect(c).toContain('keywords.underused');
    expect(codes(run([meta({ locale: 'tr', subtitle: 'Günlük rutin' })]))).toContain('aso.subtitle-short');
  });

  it('compares locales that share a storefront index, not locales that share a language', () => {
    const us = VitrinConfig.parse({ app: { locales: ['en-US', 'es-MX', 'en-GB'], primaryLocale: 'en-US' }, storefronts: ['us'], urls: config.urls });
    const en = meta({ locale: 'en-US', name: 'Ritim: Habit Tracker', subtitle: 'Daily routine and streaks', keywords: 'goal,planner,motivation,calendar,reminder' });
    const es = meta({ locale: 'es-MX', name: 'Ritim: Hábitos diarios', subtitle: 'Rutina y rachas', keywords: 'goal,meta,tracker,calendario' });
    const gb = meta({ locale: 'en-GB', keywords: 'goal,planner,motivation,calendar,reminder' });
    const items = validateText({ config: us, profile, appMetadata: appMeta, locales: new Map([en, es, gb].map((m) => [m.locale, m])) }).issues.items;
    const dup = items.filter((i) => i.code === 'keywords.cross-locale-duplicate');
    expect(dup).toHaveLength(1);
    expect(dup[0]!.message).toContain('United States');
    expect(dup[0]!.message).toContain('goal');
    expect(items.some((i) => i.code === 'keywords.cross-locale-repeats-name' && i.locale === 'es-MX' && i.message.includes('tracker'))).toBe(true);
  });
});

describe('containsTerm', () => {
  it('matches whole words across scripts', () => {
    expect(containsTerm('Free trial', 'free')).toBe(true);
    expect(containsTerm('Freedom', 'free')).toBe(false);
    expect(containsTerm('Uygulama #1', '#1')).toBe(true);
    expect(containsTerm('EN İYİ', 'en iyi', 'tr')).toBe(true);
    expect(containsTerm('無料アプリ', '無料')).toBe(true);
    expect(containsTerm('Distraction-free timer', 'free')).toBe(false);
    expect(containsTerm('100% offline', '$')).toBe(false);
  });
});

describe('competitor brands', () => {
  it('does not treat generic category phrases as brands', async () => {
    const { competitorBrands } = await import('../src/index.js');
    const competitors = {
      apps: [
        { name: 'Habit Tracker', sellerName: 'Davetech Co., Ltd' },
        { name: 'Productive - Habit Tracker', sellerName: 'Apalon Apps' },
        { name: 'Strides: Habit Tracker + Goals' },
        { name: 'Daily Habit Tracker & Planner' },
        { name: 'Grit: Habits, Goals', sellerName: 'Goals LLC' },
      ],
    } as unknown as Competitors;
    const brands = competitorBrands(competitors, ['Ritim'], ['habit tracker', 'goal tracker']);
    expect(brands).not.toContain('Habit Tracker');
    expect(brands).toContain('Productive');
    expect(brands).toContain('Strides');
    expect(brands).not.toContain('Goals');
  });
});

describe('ASO rules: fields, keyword field, research', () => {
  const candidate = (term: string, over: Partial<KeywordPlan['candidates'][number]> & { median?: number; popularity?: number } = {}) => ({
    term,
    relevance: 1,
    total: 0.5,
    ownRank: null,
    popularity: { score: over.popularity ?? 0.5, source: 'estimate' as const },
    competition: { resultCount: 50, top10MedianRatings: over.median ?? 50, score: 0.3 },
  });
  const planFor = (candidates: KeywordPlan['candidates'], selected: NonNullable<KeywordPlan['selected']>): KeywordPlan => ({ locale: 'en-US', storefront: 'us', generatedAt: '', candidates, selected });
  const check = (m: LocaleMetadata, extra: { plan?: KeywordPlan; competitors?: Competitors; app?: AppMetadata; plans?: Map<string, KeywordPlan> } = {}) =>
    validateText({ config, profile, competitors: extra.competitors, appMetadata: extra.app ?? appMeta, locales: new Map([[m.locale, m]]), keywordPlans: extra.plans ?? (extra.plan ? new Map([[m.locale, extra.plan]]) : undefined) });
  const en = (over: Partial<LocaleMetadata> = {}) => meta({ locale: 'en-US', name: 'Habit Tracker: Ritim', subtitle: 'Daily routine and streaks', keywords: 'goal,planner,motivation,calendar,reminder', ...over });
  const selfWith = (userRatingCount: number) => ({ generatedAt: '2026-11-04T00:00:00Z', storefronts: ['us'], seeds: [], self: { trackId: 1, name: 'Ritim', storefront: 'us', userRatingCount }, apps: [], topCharts: [], analysis: { nameTerms: [] } }) as unknown as Competitors;

  it('suggests the keyword first while nobody searches for the brand', () => {
    expect(codes(check(en({ name: 'Ritim: Habit Tracker' })))).toContain('aso.name-keyword-first');
    expect(codes(check(en()))).not.toContain('aso.name-keyword-first');
    expect(codes(check(en({ name: 'Ritim: Habit Tracker' }), { competitors: selfWith(50_000) }))).not.toContain('aso.name-keyword-first');
  });

  it('flags words repeated across keyword terms, and phrases only as a hint', () => {
    const r = check(en({ keywords: 'habit goals,habit routine,planner' }));
    expect(r.issues.items.find((i) => i.code === 'keywords.word-repeat')?.message).toContain('“habit”');
    expect(r.issues.items.find((i) => i.code === 'keywords.phrase')?.severity).toBe('info');
    const clean = codes(check(en()));
    expect(clean).not.toContain('keywords.word-repeat');
    expect(clean).not.toContain('keywords.phrase');
  });

  it('keeps a word written twice as a duplicate, not a word repeat', () => {
    const c = codes(check(en({ keywords: 'goal,goal,planner' })));
    expect(c).toContain('keywords.duplicate');
    expect(c).not.toContain('keywords.word-repeat');
  });

  it('flags category words, filler and special characters in the keyword field', () => {
    const app = { ...appMeta, primaryCategory: 'HEALTH_AND_FITNESS', secondaryCategory: 'GAMES' };
    const r = check(en({ keywords: 'health,game,the,#goal,planner' }), { app });
    expect(r.issues.items.find((i) => i.code === 'keywords.repeats-category')?.message).toContain('“health”');
    expect(r.issues.items.find((i) => i.code === 'keywords.repeats-category')?.message).toContain('“game”');
    expect(r.issues.items.filter((i) => i.code === 'keywords.noise').map((i) => i.message).join()).toContain('“the”');
    expect(codes(check(en({ keywords: 'goal,planner' }), { app }))).not.toContain('keywords.repeats-category');
    expect(codes(check(en({ keywords: 'goal,planner' }), { app }))).not.toContain('keywords.special-char');
    expect(codes(check(en({ keywords: '#goal,planner' }), { app }))).toContain('keywords.special-char');
  });

  it('judges filler per language, so a real word in another language passes', () => {
    const tr = (keywords: string) => check(meta({ locale: 'tr', keywords })).issues.items.filter((i) => i.code === 'keywords.noise').map((i) => i.message);
    expect(tr('para,bütçe,hesap')).toEqual([]); // "para" is money in Turkish, "for" in Spanish
    expect(tr('ve,bütçe,hesap').join()).toContain('“ve”');
  });

  it('detects keyword lists in text that does not rank', () => {
    expect(looksLikeKeywordList('habit, tracker, goals, routine, streak', 'en-US', 5)).toBe(true);
    expect(looksLikeKeywordList('Keywords: habit tracker', 'en-US', 5)).toBe(true);
    expect(looksLikeKeywordList('Track habits, keep your daily streaks alive, and see the charts.', 'en-US', 3)).toBe(false);
    expect(codes(check(en({ promotionalText: 'habit, tracker, goals, routine, streak' })))).toContain('text.keyword-list');
    expect(codes(check(en({ promotionalText: 'New in 1.2: a statistics tab with weekly charts.' })))).not.toContain('text.keyword-list');
    expect(codes(check(en({ name: 'Habits, Goals, Routine Planner' })))).toContain('text.keyword-list');
    expect(codes(check(en({ description: 'A calm way to build habits every day.\nhabit, tracker, goals, routine, streak, daily\nSee your progress in charts.' })))).toContain('text.keyword-list');
    expect(codes(check(en()))).not.toContain('text.keyword-list');
  });

  it('warns when a selected term shows no search demand', () => {
    const selected = { name: ['habit tracker'], subtitle: [], keywords: ['zebra'] };
    const dead = planFor([candidate('habit tracker'), candidate('zebra', { popularity: 0.02 })], selected);
    expect(check(en({ keywords: 'zebra,planner' }), { plan: dead }).issues.items.find((i) => i.code === 'keywords.no-demand')?.message).toContain('“zebra”');
    const alive = planFor([candidate('habit tracker'), candidate('zebra', { popularity: 0.3 })], selected);
    expect(codes(check(en({ keywords: 'zebra,planner' }), { plan: alive }))).not.toContain('keywords.no-demand');
  });

  it('warns when a small app only targets terms it cannot win yet', () => {
    const candidates = [candidate('habit tracker', { median: 500_000 }), candidate('daily routine', { median: 300_000 }), candidate('mood journal', { median: 200 })];
    const selected = { name: ['habit tracker'], subtitle: ['daily routine'], keywords: [] };
    const r = check(en(), { plan: planFor(candidates, selected) });
    expect(r.issues.items.find((i) => i.code === 'keywords.out-of-reach')?.message).toContain('mood journal');
    // A stronger app can hold these terms; one reachable term in the head or any other field is enough; a term it ranks for counts.
    expect(codes(check(en(), { plan: planFor(candidates, selected), competitors: selfWith(20_000) }))).not.toContain('keywords.out-of-reach');
    expect(codes(check(en(), { plan: planFor(candidates, { ...selected, subtitle: ['mood journal'] }) }))).not.toContain('keywords.out-of-reach');
    expect(codes(check(en({ keywords: 'mood,journal,planner' }), { plan: planFor(candidates, selected) }))).not.toContain('keywords.out-of-reach');
    expect(codes(check(en(), { plan: planFor([{ ...candidates[0]!, ownRank: 40 }, candidates[1]!, candidates[2]!], selected) }))).not.toContain('keywords.out-of-reach');
  });

  it('warns about a locale without research, and one seed list for two languages', () => {
    expect(codes(check(en(), { plans: new Map() }))).toContain('keywords.no-research');
    expect(codes(check(en(), { plan: planFor([], { name: [], subtitle: [], keywords: [] }) }))).not.toContain('keywords.no-research');
    const withSeeds = (seeds: unknown) => VitrinConfig.parse({ app: { locales: ['tr', 'en-US'], primaryLocale: 'tr' }, urls: config.urls, research: { seeds } });
    const both = (cfg: VitrinConfig) => validateText({ config: cfg, profile, appMetadata: appMeta, locales: new Map([en(), meta({ locale: 'tr' })].map((m) => [m.locale, m])) });
    expect(codes(both(withSeeds(['habit tracker', 'streak'])))).toContain('research.shared-seeds');
    expect(codes(both(withSeeds({ 'en-US': ['habit tracker'], tr: ['alışkanlık takibi'] })))).not.toContain('research.shared-seeds');
    expect(codes(both(withSeeds([])))).not.toContain('research.shared-seeds');
  });
});
