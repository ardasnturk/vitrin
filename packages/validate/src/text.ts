import { baseLanguage, byteLength, DATA_DIR, graphemeLength, loadForbiddenTerms, splitKeywords, storefrontForLocale, storefrontInfo, tokenize, wordCount } from '@vitrin/core';
import {
  isKnownBrand,
  keywordReach,
  NO_DEMAND_SCORE,
  TEXT_LIMITS,
  type AppMetadata,
  type AppProfile,
  type Competitors,
  type KeywordPlan,
  type LiveListing,
  type LocaleMetadata,
  type TextField,
  type ValidationReport,
  type VitrinConfig,
} from '@vitrin/schemas';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { findAppleAward, findKidsTerm, findPlaceholder, isGenericWhatsNew } from './apple-rules.js';
import { containsTerm, IssueList } from './issues.js';

export interface TextValidationInput {
  config: VitrinConfig;
  profile?: AppProfile;
  competitors?: Competitors;
  appMetadata?: AppMetadata;
  locales: Map<string, LocaleMetadata>;
  /** metadata/research/keywords/<locale>.json — the research the fields should follow. */
  keywordPlans?: Map<string, KeywordPlan>;
  /** metadata/research/live-listing.json — what the store shows today. */
  live?: LiveListing;
}

type Measurements = ValidationReport['measurements'];

const HTML_RE = /<\/?[a-z][a-z0-9]*(\s[^>]*)?>/i;
const STOP_FOR_DUPES = new Set(['and', 'the', 'for', 'with', 've', 'ile', 'için', 'de', 'da', 'und', 'et', 'y', 'e', '&', 'a', 'an', 'of', 'to', 'your', 'you', 'this', 'that', 'from', 'are', 'bir', 'bu', 'olarak', 'veya', 'daha', 'für', 'mit', 'pour', 'avec', 'para', 'con']);
/** Filler per language; a shared list would flag real words (Turkish "para" is money, Spanish "para" is "for"). */
const KEYWORD_FILLER: Record<string, string[]> = {
  en: ['the', 'and', 'for', 'with', 'of', 'to', 'your', 'you', 'this', 'that', 'from', 'are'],
  tr: ['ve', 'ile', 'için', 'bir', 'bu', 'olarak', 'veya', 'daha'],
  de: ['und', 'der', 'die', 'das', 'für', 'mit'],
  fr: ['et', 'le', 'la', 'les', 'pour', 'avec'],
  es: ['el', 'la', 'los', 'las', 'para', 'con'],
};

/** Terms from the forbidden list that apply to a locale (the base language plus the `*` and `en` lists). */
function termsFor(map: Record<string, string[]>, locale: string): string[] {
  const base = baseLanguage(locale);
  return [...new Set([...(map['*'] ?? []), ...(map[base] ?? [])])];
}

/**
 * Brand names of competitors (app name before the first separator, and seller names).
 * Generic category phrases are not brands: a candidate is dropped when every word in it also appears in the
 * names of at least three competitors or in the research seed terms (e.g. an app literally called "Habit Tracker").
 */
export function competitorBrands(competitors?: Competitors, ownNames: string[] = [], seeds: string[] = []): string[] {
  if (!competitors) return [];
  const own = new Set(ownNames.map((n) => n.toLowerCase()));
  const wordFreq = new Map<string, number>();
  for (const a of competitors.apps) {
    for (const w of new Set(tokenize(a.name))) wordFreq.set(w, (wordFreq.get(w) ?? 0) + 1);
  }
  // Singular/plural fold so "goals" counts as the seed word "goal".
  const stem = (w: string) => w.replace(/(ies|es|s)$/, (m) => (m === 'ies' ? 'y' : '')).replace(/(lar|ler)$/, '');
  const selfSeller = competitors.self?.sellerName;
  const seedWords = new Set(seeds.flatMap((s) => tokenize(s)).map(stem));
  const stemFreq = new Map<string, number>();
  for (const [w, n] of wordFreq) stemFreq.set(stem(w), (stemFreq.get(stem(w)) ?? 0) + n);
  const generic = (phrase: string) => {
    const words = tokenize(phrase);
    return words.length > 0 && words.every((w) => (stemFreq.get(stem(w)) ?? 0) >= 3 || seedWords.has(stem(w)) || STOP_FOR_DUPES.has(w));
  };
  const names = new Set<string>();
  for (const a of competitors.apps) {
    if (selfSeller && a.sellerName === selfSeller) continue; // the developer's own apps
    const brand = a.name.split(/\s[:\-–—|]\s|[:|–—]/)[0]?.trim();
    if (brand && brand.length >= 3 && !own.has(brand.toLowerCase()) && !generic(brand)) names.add(brand);
    const seller = a.sellerName?.replace(/,?\s+(Inc\.?|LLC|Ltd\.?|GmbH|A\.Ş\.|Corp\.?)$/i, '').trim();
    if (seller && seller.length >= 3 && !own.has(seller.toLowerCase()) && !generic(seller)) names.add(seller);
  }
  return [...names];
}

/**
 * Keywords written out as text: comma-separated items of a word or two, or a labelled "Keywords: …" line. Apple:
 * promotional text "should not be used to display keywords", and the description does not rank either.
 */
export function looksLikeKeywordList(line: string, locale: string, minItems: number): boolean {
  if (/^\s*(keywords?|tags?|anahtar kelimeler|schlüsselwörter|mots[- ]clés|palabras clave)\s*:/iu.test(line)) return true;
  const items = line.split(/[,;|،、，]/).map((s) => s.trim()).filter(Boolean);
  return items.length >= minItems && items.every((item) => wordCount(item, locale) <= 2);
}

/** Words of the ASC category constants (HEALTH_AND_FITNESS → health, fitness). The constants are English, so this only fits English locales. */
export function categoryWords(app?: Pick<AppMetadata, 'primaryCategory' | 'secondaryCategory'>): Set<string> {
  const words = [app?.primaryCategory, app?.secondaryCategory].flatMap((c) => (c ?? '').toLowerCase().split('_')).filter((w) => w && w !== 'and');
  return new Set(words.flatMap((w) => (w.endsWith('s') && w !== 'news' ? [w, w.slice(0, -1)] : [w])));
}

/** Seeds a locale is researched with; the same fallback as `seedsFor` in @vitrin/research, which validate does not depend on. */
function seedList(config: VitrinConfig, locale: string): string[] {
  const s = config.research.seeds;
  return Array.isArray(s) ? s : (s[locale] ?? s[baseLanguage(locale)] ?? []);
}

/** Every word of `term` appears among the words of the name, subtitle and keyword field (the App Store combines them). */
export function termCovered(term: string, m: Pick<LocaleMetadata, 'name' | 'subtitle' | 'keywords'>, locale: string): boolean {
  const words = new Set(tokenize([m.name, m.subtitle, splitKeywords(m.keywords).join(' ')].join(' '), locale));
  const need = tokenize(term, locale);
  return need.length > 0 && need.every((w) => words.has(w));
}

export function validateText(input: TextValidationInput): { issues: IssueList; measurements: Measurements } {
  const { config, profile, competitors, appMetadata, locales, keywordPlans, live } = input;
  const issues = new IssueList();
  const measurements: Measurements = {};
  const forbidden = loadForbiddenTerms();
  const featureCommits = (profile?.docs?.commitsSinceTag ?? []).map((c) => c.subject).filter((x) => /^(feat|add|new|introduce|support|implement)\b/i.test(x));
  const developer = config.copyrightHolder ?? '';
  const seeds = Array.isArray(config.research.seeds) ? config.research.seeds : Object.values(config.research.seeds).flat();
  const brands = competitorBrands(competitors, [profile?.app.displayName ?? '', developer], seeds);
  const featureIds = new Set(profile?.features.map((f) => f.id) ?? []);

  for (const locale of config.app.locales) {
    if (!locales.has(locale)) {
      issues.error('metadata.missing-locale', `No metadata file for ${locale} (metadata/listing/${locale}.json).`, { locale });
    }
  }

  for (const [locale, m] of locales) {
    const at = (field: string) => ({ locale, field, file: `metadata/listing/${locale}.json` });
    const lm: Measurements[string] = {};
    measurements[locale] = lm;

    // ---- limits ----
    const values: Record<TextField, string> = {
      name: m.name,
      subtitle: m.subtitle,
      promotionalText: m.promotionalText,
      description: m.description,
      keywords: m.keywords,
      whatsNew: m.whatsNew,
      reviewNotes: appMetadata?.reviewNotes ?? '',
    };
    for (const [field, limit] of Object.entries(TEXT_LIMITS) as Array<[TextField, (typeof TEXT_LIMITS)[TextField]]>) {
      if (field === 'reviewNotes') continue;
      const v = values[field];
      const chars = graphemeLength(v);
      const bytes = byteLength(v);
      const n = limit.unit === 'bytes' ? bytes : chars;
      lm[field] = { chars, bytes, limit: limit.max, unit: limit.unit };
      if (limit.required && !v.trim()) issues.error('text.required', `${field} cannot be empty.`, at(field));
      else if (n > limit.max) {
        issues.error('text.too-long', `${field} is ${n}/${limit.max} ${limit.unit === 'bytes' ? 'bytes' : 'characters'}.`, {
          ...at(field),
          fix: `Shorten by ${n - limit.max} ${limit.unit === 'bytes' ? 'bytes' : 'characters'}.`,
        });
      } else if (v.trim() && n < limit.min) issues.error('text.too-short', `${field} must be at least ${limit.min} characters.`, at(field));
      if (v !== v.trim()) issues.warn('text.whitespace', `${field} has leading/trailing whitespace.`, at(field));
      if (HTML_RE.test(v)) issues.error('text.html', `${field} contains HTML; the App Store accepts plain text only.`, at(field));
    }

    // ---- name / subtitle ----
    const nameWords = tokenize(m.name, locale).filter((w) => !STOP_FOR_DUPES.has(w));
    const subWords = tokenize(m.subtitle, locale).filter((w) => !STOP_FOR_DUPES.has(w));
    const repeated = subWords.filter((w) => nameWords.includes(w));
    if (repeated.length) {
      issues.error('aso.subtitle-repeats-name', `Subtitle repeats words from the name: ${[...new Set(repeated)].join(', ')}.`, {
        ...at('subtitle'),
        fix: 'Use secondary keywords in the subtitle that differ from the name.',
      });
    }
    // The subtitle is the second most weighted field; an empty or half-used one gives away ranking.
    if (!m.subtitle.trim()) issues.warn('aso.subtitle-empty', 'The subtitle is empty; it is indexed right after the name — use it for a benefit and a secondary keyword (≤ 30).', at('subtitle'));
    else if (graphemeLength(m.subtitle) < 20) issues.warn('aso.subtitle-short', `The subtitle uses ${graphemeLength(m.subtitle)}/30 characters; there is room for another keyword.`, at('subtitle'));
    const plan = keywordPlans?.get(locale);
    const brandWords = new Set(tokenize(profile?.app.displayName ?? '', locale));
    if (nameWords.length && nameWords.every((w) => brandWords.has(w)) && !(plan?.candidates ?? []).some((c) => termCovered(c.term, { name: m.name, subtitle: '', keywords: '' }, locale))) {
      issues.warn('aso.name-brand-only', `The name is only the brand (“${m.name}”); the name is the most weighted field — add the primary keyword (“keyword: brand”; “brand: keyword” once people search for the brand).`, at('name'));
    } else if (!isKnownBrand(competitors?.self) && brandWords.has(nameWords[0] ?? '') && nameWords.some((w) => !brandWords.has(w))) {
      issues.info('aso.name-keyword-first', `“${m.name}” leads with a brand people do not search for yet; “keyword: brand” says at once what the app does in search results.`, { ...at('name'), fix: 'This is about clarity, not a proven ranking gain: for a live app that ranks, reorder only when the name changes anyway.' });
    }
    if (looksLikeKeywordList(m.name, locale, 3)) issues.warn('text.keyword-list', `The name reads like a list of keywords (“${m.name}”); keep it natural (App Review 2.3.7).`, at('name'));
    if (looksLikeKeywordList(m.subtitle, locale, 4)) issues.warn('text.keyword-list', `The subtitle reads like a list of keywords (“${m.subtitle}”); say what the app does for the user.`, at('subtitle'));

    // ---- keywords ----
    const kwField = m.keywords;
    if (/,\s|\s,/.test(kwField)) {
      issues.error('keywords.spaces', 'Spaces around commas; every space costs a byte.', { ...at('keywords'), fix: 'Write commas without spaces: keyword1,keyword2' });
    }
    const terms = splitKeywords(kwField);
    const seen = new Set<string>();
    const isCjk = /^(ja|ko|zh)/.test(locale);
    for (const term of terms) {
      const lower = term.toLocaleLowerCase(locale);
      if (seen.has(lower)) issues.error('keywords.duplicate', `“${term}” appears more than once in the keyword field.`, at('keywords'));
      seen.add(lower);
      if (graphemeLength(term) <= 2 && !isCjk) {
        issues.error('keywords.too-short', `“${term}” must be longer than 2 characters.`, at('keywords'));
      }
      for (const w of tokenize(term, locale)) {
        if (nameWords.includes(w) || subWords.includes(w)) {
          issues.error('keywords.repeats-name', `“${w}” is already in the name/subtitle; repeating it in the keyword field wastes bytes.`, { ...at('keywords'), fix: `Remove “${w}”.` });
        }
      }
      if (developer && containsTerm(term, developer, locale)) {
        issues.error('keywords.developer-name', `The developer name (“${developer}”) should not be in the keyword field.`, at('keywords'));
      }
      for (const tm of forbidden.appleTrademarks) {
        if (containsTerm(term, tm, locale)) issues.error('keywords.apple-trademark', `The Apple trademark “${tm}” cannot be used in the keyword field.`, at('keywords'));
      }
    }
    for (const t of terms) {
      const lower = t.toLocaleLowerCase(locale);
      const plurals = pluralForms(lower, locale);
      for (const p of plurals) {
        if (seen.has(p)) issues.warn('keywords.plural', `Both “${t}” and “${p}” are present; the App Store matches singular/plural forms, so remove one.`, at('keywords'));
      }
    }
    for (const noise of [...forbidden.keywordNoise, ...(KEYWORD_FILLER[baseLanguage(locale)] ?? [])]) {
      if (seen.has(noise.toLowerCase())) issues.warn('keywords.noise', `“${noise}” is low-value; spend these bytes on another keyword.`, at('keywords'));
    }
    if (/[#@]/.test(kwField)) issues.warn('keywords.special-char', 'Special characters such as # or @ add nothing unless they are part of the brand; Apple advises against them.', at('keywords'));
    // A word needs to be there only once: the App Store combines the words of the keyword field, name and subtitle.
    // (`seen` holds each term once, so a term written twice stays `keywords.duplicate`.)
    if (!isCjk) {
      const uses = new Map<string, number>();
      for (const term of seen) for (const w of new Set(tokenize(term, locale))) uses.set(w, (uses.get(w) ?? 0) + 1);
      const again = [...uses].filter(([, n]) => n > 1).map(([w]) => w);
      if (again.length) issues.warn('keywords.word-repeat', `${again.map((w) => `“${w}”`).join(', ')} appears in more than one keyword term; a word only has to be there once.`, { ...at('keywords'), fix: 'Keep each word once and spend the bytes on new words.' });
      const phrases = [...seen].filter((t) => tokenize(t, locale).length > 1);
      if (phrases.length) issues.info('keywords.phrase', `${phrases.map((t) => `“${t}”`).join(', ')} is written as a phrase; a comma costs the same byte as the space and lets each word combine with the other fields. Keep a phrase only when the exact wording matters.`, at('keywords'));
    }
    if (baseLanguage(locale) === 'en') {
      const category = categoryWords(appMetadata);
      const inCategory = [...new Set([...seen].flatMap((t) => tokenize(t, locale)).filter((w) => category.has(w)))];
      if (inCategory.length) issues.warn('keywords.repeats-category', `${inCategory.map((w) => `“${w}”`).join(', ')} is in the app's category, which the App Store already indexes; Apple advises against repeating it.`, { ...at('keywords'), fix: 'Spend these bytes on another keyword.' });
    }
    if (kwField.trim() && byteLength(kwField) < 90) {
      issues.warn('keywords.underused', `Keyword field is ${byteLength(kwField)}/100 bytes; use the remaining bytes for another term.`, at('keywords'));
    }

    // ---- keyword plan: the research has to reach the fields ----
    if (keywordPlans && !plan) {
      issues.warn('keywords.no-research', `${locale} has no keyword research; its fields may be a translation instead of what people search for there.`, { ...at('keywords'), fix: 'Add seeds for this locale to research.seeds and run `vitrin research`.' });
    }
    if (plan) {
      const file = `metadata/research/keywords/${locale}.json`;
      const unscored = plan.candidates.filter((c) => c.relevance === null).length;
      if (unscored) issues.warn('keywords.plan-unscored', `${unscored} of ${plan.candidates.length} keyword candidates have no relevance; score them (0–1) so the plan can rank them.`, { locale, file });
      if (!plan.selected) issues.warn('keywords.plan-unselected', 'The keyword plan has no `selected` terms; write which terms go in the name, subtitle and keyword field.', { locale, file });
      else {
        for (const field of ['name', 'subtitle'] as const) {
          for (const term of plan.selected[field]) {
            if (!tokenize(term, locale).every((w) => tokenize(m[field], locale).includes(w))) issues.warn('keywords.plan-mismatch', `“${term}” is selected for the ${field}, but the ${field} does not contain it.`, at(field));
          }
        }
        for (const term of plan.selected.keywords) {
          if (!termCovered(term, m, locale)) issues.warn('keywords.plan-mismatch', `“${term}” is selected for the keyword field, but no field carries it.`, at('keywords'));
        }
        const candidate = (term: string) => plan.candidates.find((c) => c.term === term.toLocaleLowerCase(locale));
        const { name, subtitle, keywords: fieldTerms } = plan.selected;
        for (const term of [...name, ...subtitle, ...fieldTerms]) {
          const c = candidate(term);
          if (c && c.popularity.score < NO_DEMAND_SCORE) issues.warn('keywords.no-demand', `“${term}” shows no search demand (popularity ${c.popularity.score}); ranking #1 for it brings nobody.`, { ...at('keywords'), file });
        }
        // A new or small app needs at least one term it can win; the App Store combines the fields, so any field can carry it.
        const ownRatings = competitors?.self?.userRatingCount ?? 0;
        const reach = (c: (typeof plan.candidates)[number]) => keywordReach(c, ownRatings);
        const head = [...name, ...subtitle].map(candidate).filter((c) => c !== undefined);
        if (head.length && head.every((c) => reach(c) === 'stretch')) {
          const winnable = plan.candidates.filter((c) => reach(c) !== 'stretch' && c.total !== null && (c.relevance ?? 0) >= 0.6 && c.popularity.score >= NO_DEMAND_SCORE).sort((a, b) => b.total! - a.total!);
          if (winnable.length && !winnable.some((c) => termCovered(c.term, m, locale))) {
            issues.warn('keywords.out-of-reach', `Every researched term in the name and subtitle is held by apps far stronger than this one, and no field carries a closer term: ${winnable.slice(0, 3).map((c) => c.term).join(', ')}.`, { ...at('subtitle'), fix: 'Give the subtitle or the keyword field one of these, and grow into the bigger terms.' });
          }
        }
      }
      // Dropping a term the app already ranks for gives away traffic it has today.
      for (const c of plan.candidates) {
        if (c.ownRank !== null && c.ownRank <= 10 && !termCovered(c.term, m, locale)) {
          issues.warn('keywords.drops-ranked-term', `The app ranks #${c.ownRank} for “${c.term}”, but the name, subtitle and keywords no longer carry it.`, { ...at('keywords'), fix: 'Keep the term unless something better replaces it.' });
        }
      }
      const best = plan.candidates.filter((c) => c.total !== null && (c.relevance ?? 0) >= 0.6).sort((a, b) => b.total! - a.total!).slice(0, 5);
      const unused = best.filter((c) => !termCovered(c.term, m, locale)).map((c) => c.term);
      if (unused.length) issues.info('keywords.top-unused', `Best-scored candidates not in any field: ${unused.join(', ')}.`, at('keywords'));
    }
    const was = live?.locales[locale];
    if (was?.keywords !== undefined) {
      const before = new Set(splitKeywords(was.keywords).map((t) => t.toLocaleLowerCase(locale)));
      const after = new Set(splitKeywords(kwField).map((t) => t.toLocaleLowerCase(locale)));
      const removed = [...before].filter((t) => !after.has(t) && !termCovered(t, m, locale));
      const added = [...after].filter((t) => !before.has(t));
      if (removed.length || added.length) issues.info('keywords.live-diff', `Compared with the live keyword field: removed ${removed.join(', ') || '—'}; added ${added.join(', ') || '—'}.`, at('keywords'));
    }

    // ---- forbidden terms ----
    const priceTerms = termsFor(forbidden.price, locale);
    const superTerms = termsFor(forbidden.superlatives, locale);
    const strictFields: Array<[string, string]> = [
      ['name', m.name],
      ['subtitle', m.subtitle],
      ['keywords', m.keywords],
      ['promotionalText', m.promotionalText],
    ];
    for (const [field, text] of strictFields) {
      for (const t of priceTerms) {
        if (!containsTerm(text, t, locale)) continue;
        // Promotional text is meant for campaigns; flag it, but do not block.
        if (field === 'promotionalText') issues.warn('text.price', `${field} contains a price term (“${t}”); the price is already shown on the App Store.`, at(field));
        else issues.error('text.price', `${field} contains a price term (“${t}”).`, at(field));
      }
      for (const t of superTerms) if (containsTerm(text, t, locale)) issues.error('text.superlative', `${field} contains an unproven superlative (“${t}”).`, at(field));
    }
    for (const t of superTerms) {
      if (containsTerm(m.description, t, locale)) issues.warn('text.superlative', `The description contains “${t}”; remove it unless it is documented.`, at('description'));
    }
    for (const t of priceTerms.filter((x) => x.length > 1)) {
      if (containsTerm(m.description, t, locale)) issues.warn('text.price', `The description contains a price term (“${t}”); remove it unless it is subscription information.`, at('description'));
    }
    for (const brand of brands) {
      for (const [field, text] of [...strictFields, ['description', m.description] as [string, string], ['whatsNew', m.whatsNew] as [string, string]]) {
        if (containsTerm(text, brand, locale)) {
          issues.error('text.competitor-brand', `${field} contains a competitor brand name (“${brand}”).`, { ...at(field), fix: 'Other app or company names cannot be used.' });
        }
      }
    }

    // ---- App Review: placeholders, Apple recognitions, Kids Category wording, What's New ----
    const kidsApp = isKidsCategory(appMetadata);
    for (const [field, text] of [...strictFields, ['description', m.description] as [string, string], ['whatsNew', m.whatsNew] as [string, string]]) {
      const ph = findPlaceholder(text);
      if (ph) issues.error('text.placeholder', `${field} contains template text (“${ph}”); App Review rejects placeholder content (2.1).`, at(field));
      const award = findAppleAward(text, forbidden, locale);
      if (award) issues.error('text.apple-award', `${field} mentions an Apple-designated recognition (“${award}”); these may not be used in metadata.`, at(field));
      const kids = findKidsTerm(text, forbidden, locale);
      if (kids && !kidsApp) issues.error('text.kids-reserved', `${field} contains “${kids}”, which is reserved for apps in the Kids Category (App Review 2.3.8, 5.1.4).`, { ...at(field), fix: 'Describe the audience without it, or set the Kids age band in app.json ageRatingDraft.answers.kidsAgeBand if the app is in the Kids Category.' });
    }
    if (isGenericWhatsNew(m.whatsNew, forbidden, locale) && featureCommits.length) {
      issues.warn('whatsnew.generic', `What's New is generic, but this release adds features (${featureCommits.slice(0, 3).map((c) => `“${c}”`).join(', ')}); App Review 2.3.12 requires significant changes to be listed.`, at('whatsNew'));
    }

    // ---- only the name, subtitle, keywords and category rank; the rest is written for people ----
    if (looksLikeKeywordList(m.promotionalText, locale, 5)) issues.warn('text.keyword-list', 'The promotional text reads like a list of keywords; it does not affect search ranking, so use it to say what is new.', at('promotionalText'));
    if (m.description.split('\n').some((line) => looksLikeKeywordList(line, locale, 6))) issues.warn('text.keyword-list', 'A line of the description reads like a list of keywords; the description does not rank in App Store search, so write it for the person reading.', at('description'));

    // ---- description quality ----
    const firstLines = m.description.split('\n').filter((l) => l.trim()).slice(0, 3).join(' ');
    if (graphemeLength(firstLines) < 40) issues.warn('description.hook', 'The first 3 lines of the description are visible before “more”; write a strong hook.', at('description'));
    const counts = new Map<string, number>();
    for (const w of tokenize(m.description, locale)) if (w.length > 3 && !STOP_FOR_DUPES.has(w)) counts.set(w, (counts.get(w) ?? 0) + 1);
    for (const [w, c] of counts) {
      if (c > 6) issues.warn('description.stuffing', `“${w}” appears ${c} times in the description; it may look like keyword stuffing.`, at('description'));
    }

    // ---- URLs ----
    const urlChecks: Array<[string, string | undefined, boolean]> = [
      ['supportUrl', m.supportUrl ?? config.urls.support, true],
      ['privacyUrl', m.privacyUrl ?? config.urls.privacy, true],
      ['marketingUrl', m.marketingUrl ?? config.urls.marketing, false],
    ];
    for (const [field, url, required] of urlChecks) {
      if (!url) {
        if (required) issues.error('url.missing', `${field} is required (metadata or vitrin.config.yaml urls).`, at(field));
        continue;
      }
      if (!/^https?:\/\/[^\s/$.?#].[^\s]*$/i.test(url)) issues.error('url.invalid', `${field} is not a valid URL: ${url}`, at(field));
      else if (!url.startsWith('https://')) issues.warn('url.http', `${field} should use https.`, at(field));
      if (/\/\/(www\.)?example\.(com|org|net)\b/i.test(url)) issues.warn('url.placeholder', `${field} is a placeholder (${url}); set the real address before uploading.`, at(field));
    }

    // ---- claims ----
    for (const claim of m.claims) {
      for (const id of claim.featureIds) {
        if (!featureIds.has(id)) {
          issues.error('claim.unknown-feature', `Claim “${claim.text}” references an unknown feature: ${id}.`, { ...at('claims'), fix: 'Link it to an evidenced feature in app_profile.json features, or remove the claim (App Review 2.3).' });
        }
      }
      const all = [m.name, m.subtitle, m.promotionalText, m.description, m.whatsNew].join('\n');
      if (!all.toLocaleLowerCase(locale).includes(claim.text.toLocaleLowerCase(locale))) {
        issues.warn('claim.not-in-copy', `Claim text does not appear verbatim in the copy: “${claim.text}”.`, at('claims'));
      }
    }
    if (!m.claims.length) issues.warn('claim.none', 'The claims list is empty; link the feature claims in the description to app_profile features.', at('claims'));
  }

  // ---- each market searches in its own words: one seed list for two languages is a translation, not research ----
  const researched = [...locales.keys()].map((locale) => ({ locale, seeds: [...seedList(config, locale)].map((s) => s.toLocaleLowerCase(locale)).sort().join('\n') }));
  const sameSeeds = researched.filter((a, i) => a.seeds && researched.some((b, j) => i !== j && a.seeds === b.seeds && baseLanguage(a.locale) !== baseLanguage(b.locale)));
  if (sameSeeds.length) {
    issues.warn('research.shared-seeds', `${sameSeeds.map((s) => s.locale).join(', ')} are researched with the same seed terms; people in different markets search in their own words.`, { file: 'vitrin.config.yaml', field: 'research.seeds', fix: 'Write seeds per locale: `research.seeds: { "en-US": […], "tr": […] }`.' });
  }

  // ---- cross-locale: languages indexed in the same storefront share one search index ----
  // e.g. the US store indexes en-US and es-MX: a term in both keyword fields, or a keyword that repeats a word from
  // the other locale's name/subtitle, spends bytes twice for the same storefront.
  const pairs = new Map<string, { a: string; b: string; storefronts: string[] }>();
  const storefronts = config.storefronts.length ? config.storefronts : [...new Set([...locales.keys()].map(storefrontForLocale))];
  for (const code of storefronts) {
    const sf = storefrontInfo(code);
    if (!sf) continue;
    const indexed = [sf.default, ...sf.additional].filter((l) => locales.has(l));
    for (let i = 0; i < indexed.length; i++) {
      for (let j = i + 1; j < indexed.length; j++) {
        const key = [indexed[i]!, indexed[j]!].sort().join('|');
        const pair = pairs.get(key) ?? { a: indexed[i]!, b: indexed[j]!, storefronts: [] };
        pair.storefronts.push(sf.country);
        pairs.set(key, pair);
      }
    }
  }
  for (const { a, b, storefronts: where } of pairs.values()) {
    const ma = locales.get(a)!;
    const mb = locales.get(b)!;
    const store = where.length > 1 ? `${where[0]} (and ${where.length - 1} more)` : where[0];
    const ta = new Set(splitKeywords(ma.keywords).map((x) => x.toLowerCase()));
    const shared = splitKeywords(mb.keywords).filter((x) => ta.has(x.toLowerCase()));
    if (shared.length) {
      issues.warn('keywords.cross-locale-duplicate', `${a} and ${b} are both indexed in ${store}; their keyword fields share ${shared.join(', ')}.`, { locale: b, field: 'keywords', fix: 'Give the second locale different terms: together they form one index there.' });
    }
    for (const [x, y] of [[ma, mb], [mb, ma]] as const) {
      const titled = new Set(tokenize(`${x.name} ${x.subtitle}`, x.locale).filter((w) => !STOP_FOR_DUPES.has(w)));
      const repeats = [...new Set(splitKeywords(y.keywords).flatMap((t) => tokenize(t, y.locale)).filter((w) => titled.has(w)))];
      if (repeats.length) issues.warn('keywords.cross-locale-repeats-name', `${y.locale} keywords repeat ${repeats.join(', ')} from the ${x.locale} name/subtitle; both are indexed in ${store}.`, { locale: y.locale, field: 'keywords' });
    }
  }

  // ---- app level ----
  if (appMetadata) {
    if (!/^\d{4}\s+\S/.test(appMetadata.copyright)) {
      issues.error('copyright.format', `Copyright must be in the form “2026 Company Name”: “${appMetadata.copyright}”.`, { field: 'copyright', file: 'metadata/listing/app.json' });
    }
    if (appMetadata.reviewNotes.trim().length < 40) {
      issues.warn('review.notes-short', 'Review notes are empty or very short; describe new features specifically, how to reach them and any demo account or demo mode (App Review 2.1, 2.3.1).', { field: 'reviewNotes', file: 'metadata/listing/app.json' });
    } else if (findPlaceholder(appMetadata.reviewNotes)) {
      issues.error('text.placeholder', 'Review notes contain template text; App Review rejects placeholder content (2.1).', { field: 'reviewNotes', file: 'metadata/listing/app.json' });
    }
    if (appMetadata.copyright.includes('©')) issues.warn('copyright.symbol', 'Do not include the © symbol; the App Store adds it.', { field: 'copyright' });
    const notesBytes = byteLength(appMetadata.reviewNotes);
    if (notesBytes > TEXT_LIMITS.reviewNotes.max) issues.error('text.too-long', `Review notes are ${notesBytes}/4000 bytes.`, { field: 'reviewNotes' });
    if (appMetadata.secondaryCategory && appMetadata.secondaryCategory === appMetadata.primaryCategory) {
      issues.error('category.same', 'Primary and secondary category cannot be the same.', { field: 'secondaryCategory' });
    }
  } else {
    issues.error('metadata.app-missing', 'metadata/listing/app.json is missing (copyright, categories, review notes).');
  }

  return { issues, measurements };
}

/** Very small plural heuristic used only to warn about singular/plural pairs. */
export function pluralForms(term: string, locale: string): string[] {
  const base = baseLanguage(locale);
  if (base === 'en') return [`${term}s`, `${term}es`, term.endsWith('y') ? `${term.slice(0, -1)}ies` : ''].filter(Boolean);
  if (base === 'tr') return [`${term}lar`, `${term}ler`];
  if (base === 'de') return [`${term}e`, `${term}n`, `${term}en`];
  if (['fr', 'es', 'pt', 'it'].includes(base)) return [`${term}s`, `${term}es`];
  return [];
}

/** Apps in the Kids Category declare a kids age band; only they may use "for kids" wording. */
function isKidsCategory(app?: AppMetadata): boolean {
  const answers = (app?.ageRatingDraft?.answers ?? {}) as Record<string, unknown>;
  return Boolean(answers.kidsAgeBand ?? answers.madeForKids);
}
