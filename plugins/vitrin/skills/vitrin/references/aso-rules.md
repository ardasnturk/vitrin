# ASO rules

Text that earns ranking in App Store search comes from the **name**, the **subtitle**, the **keyword field** and the **category** (Apple: "matches for your app's title, subtitle, keywords, and primary category"); user behavior (downloads, ratings and reviews) counts too. The description does not count toward in-store ranking (it is used by web search), and Apple says promotional text does not affect it either. Write both for people: a keyword list there gains nothing (`text.keyword-list`).

## Keyword selection

1. Set `relevance` (0–1) for the candidates in `metadata/research/keywords/<locale>.json`: does the app really do the job of the person searching for this term? If not, 0.
2. `total = relevance × demand × (1 − 0.7 × competition)`, with `demand = 0.35 + 0.65 × popularity` fading to 0 below popularity 0.1: ranking #1 for a term nobody searches for brings nobody (`keywords.no-demand`). Computed by the CLI (`vitrin write` recomputes it after you set relevance). `popularity.source: "estimate"` is an estimate from the rating volume of the apps that rank for the term; do not present it as an exact number. `competition` = how many of the top 10 carry the term in their name, plus how entrenched they are (median ratings).
3. **Do not chase volume.** A popular term held by apps with far more ratings may be out of reach for a new or small app (Apple names this trade-off itself). `stretch` in the write brief marks such a term: the top 10's median rating count is over 100 times the app's own (a new app counts as 100 ratings; this is Vitrin's heuristic, not an Apple number). Prefer a smaller term the app can win and grow into the big ones later; when the name and subtitle hold only stretch terms and no field carries a closer one, validate warns (`keywords.out-of-reach`).
4. Distribution: the strongest 1–2 terms go into the **name**, the next 1–2 into the **subtitle**, the rest into the **keyword field**. Write them to the `selected` field — validate checks that each selected term really is in its field (`keywords.plan-mismatch`).
5. `ownRank` is where the app ranks for the term today (live apps). Keep the terms it ranks top 10 for (`keywords.drops-ranked-term`), and see `metadata/research/live-listing.json` for what the listing says now.

## Audit

`vitrin audit` scores where the listing stands today, per language, from what `vitrin research` and `vitrin rank` already measured (no new requests): 0–100, from rankings (50), listing (30) and competition (20), and never more than the rankings + 30, because a perfect listing nobody finds is not a good listing. Under 40 is `pivot` (change the keywords), under 70 `align` (fine-tune), above that `fine`. It judges the live listing when there is one; `--draft` judges `metadata/listing/` instead, to see what a rewrite would change. Results stay in `metadata/audits/<date>.json`, and the newest one's fixes open the write brief.

Volume and difficulty (0–100) are Vitrin's estimates from the apps that rank for a term, not Apple's search counts. Say so whenever you quote them. Scores are heuristics: use them to compare terms and runs, never as a promise.

`vitrin rank` records the top rivals' ranks next to the app's own, and prints who is ahead for each term. `research.rivals` in `vitrin.config.yaml` pins App Store ids to follow; otherwise the apps seen most often in the top 10 are used.

## Ideas before an app exists

`vitrin keywords "calorie tracker" --storefront us,de` works in any folder, with no project: it scores the terms and what the App Store's search box suggests for them in each country. Use it to size an idea or to find seeds. Suggestions come from an undocumented endpoint: an empty list is normal, and some countries have none.

## Pricing

`vitrin pricing --base 9.99 --country us [--method tiers]` proposes a price per country from purchasing power (World Bank GNI per capita, PPP; `data/ppp.json`, refreshed with `scripts/update-ppp.mjs`), held between `--floor` and `--ceiling` shares of the base price. It is a proposal in the base currency: Vitrin never changes prices, and App Store Connect snaps each one to a local price point. Show it to the user; lowering a price is a business decision.

## Measure

Run `vitrin rank` before a metadata change and again one to two weeks after it: it records the app's own rank for the selected and best-scored terms in `metadata/rankings/<date>.json` (kept in git, outside `research/`, so it survives the research clean-up) and prints the change since the previous snapshot. Use the result for the next iteration: keep what moved up, replace what did not.

Rank is not the goal, and a move does not prove the metadata caused it. Ask the user to compare impressions, conversion rate and downloads in App Analytics, with the source type set to App Store Search. A term that does not move may be too competitive or have the wrong intent. `vitrin rank` reads the iTunes Search API, which approximates the store's order; give it a week or two, not a day.

## Name (2–30)

- Primary keyword + brand, in natural wording, with the brand always in the name. The brand alone is not enough (`aso.name-brand-only`); a list of keywords is forbidden (`text.keyword-list`, App Review 2.3.7).
- **Order follows how known the brand is.** Nobody searches for a new app's name, so lead with what it does: `Alışkanlık Takibi: Ritim` (Turkish for "Habit Tracker: Ritim"). A brand people search for can lead: `Ritim: Alışkanlık Takibi`. Vitrin treats 10,000 ratings as known (`aso.name-keyword-first` is an info below that).
- This is for clarity in search results. Apple documents no position effect, so never promise a ranking gain from it, and do not reorder the name of a live app that already ranks for its own sake.

## Subtitle (≤ 30)

- Benefit + secondary keyword. **Do not repeat** words from the name (validate reports an error). Use it — an empty subtitle or one under 20 characters gives away the second most weighted field (`aso.subtitle-empty`, `aso.subtitle-short`).

## Keyword field (≤ 100 bytes)

- Comma-separated, **no spaces**: `goal,routine,streak`. Every space costs a byte.
- **Single words, each once.** The App Store combines words across the keyword field, name and subtitle, so `routine,goal,streak` next to the name "Habit Tracker" reaches "habit routine" and "habit goal" as well, while `habit routine,habit goal` spends bytes twice (`keywords.word-repeat`). That is the ASO community's observation; Apple only says phrases are allowed and that words should not be repeated. Not every combination will rank, so a phrase is fine when the exact wording matters (`keywords.phrase` is an info).
- **The byte trap:** Turkish ç ş ğ ı ö ü are 2 bytes each in UTF-8; Japanese/Chinese/Korean characters are 3 bytes. `alışkanlık` ("habit") = 13 bytes for 10 characters.
- Use the singular; plurals still match. Do not include words from the name/subtitle, the category (Apple: already indexed; `keywords.repeats-category` for English locales, check other languages yourself against the store's localized category name), the developer name, competitor/brand names, Apple marks (iPhone, iPad, Apple Watch…), prices, or "free".
- Every term longer than 2 characters (except CJK). Low-value words such as `app`, `game`, `iphone` or `uygulama` ("app"), filler such as `the` or `to`, and special characters such as `#` or `@` waste bytes (`keywords.noise`, `keywords.special-char`).
- Do not leave bytes unused (< 90 bytes triggers a warning).

## Localization is research, not translation

- People in different countries search differently, even for the same kind of app; the literal translation of "budget tracker" may not be what Germans type. Every locale gets its own `research.seeds`, its own scored candidates and its own name, subtitle and keywords (`research.shared-seeds`, `keywords.no-research`).
- Some markets also search in English. Try the English term as a seed there; with an English localization indexed in that storefront (Italy indexes en-GB alongside it-IT, see `data/storefront-languages.json`), it goes in that locale's fields, otherwise in the local keyword field.
- Seeds you write are ideas, not data: only `vitrin research` shows demand and competition.
- A keyword field belongs to a language, not a country. Check which languages a storefront indexes before planning for it (next section). Screenshots are localized too (`shots.json` copy, demo data in `strings/<locale>.json`).

## Storefront additional languages

- In each storefront, the default language and the additional languages are indexed (an observation, not an Apple commitment). E.g. US: en-US + es-MX, zh-Hans, …; Türkiye: en-GB + tr.
- Write **different** keywords for two languages that may count in the same storefront, and do not repeat the other locale's name/subtitle words in a keyword field: validate groups the locales by the storefronts in `storefronts` and warns about every shared term (`keywords.cross-locale-duplicate`, `keywords.cross-locale-repeats-name`). E.g. putting secondary English terms into the `es-MX` field for the US is a known strategy — but only if the app actually has metadata in that language. The write brief lists the indexing slots the app does not use yet; offer them to the user, never add a locale without a real localization.

## App Store tags (US only)

- Assigned from en-US metadata by AI plus human curation. Use the target concepts explicitly in the en-US name/subtitle/description. Remind the user to check the tags in ASC after upload.

## Custom Product Pages

- 2–5 suggestions: derive segments from competitor gaps and review clusters (e.g. "morning routine", "water intake goal"). Give each page a **non-overlapping** keyword set; keywords are assigned from the keyword field of the latest approved version.
- **Each page needs its own screenshots** — the same set with different promotional text barely moves conversion. Set `shots` (ids from shots.json, the segment's hero first) and per-shot `copy` overrides; `vitrin design` renders the page's set to `metadata/store/cpp/<page id>/<locale>/`, the review shows it, and `vitrin upload --cpp` places it on the page through the App Asset Library (`cpp.no-shots` warns when a page has none).

## Screenshot headlines

- Their ranking impact is disputed (Appfigures' 2025 observation vs. weak tests). Write for both possibilities: the first 3 headlines should be large, high-contrast and reinforce the primary keyword from the name/subtitle.
