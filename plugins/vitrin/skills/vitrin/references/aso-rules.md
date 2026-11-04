# ASO rules

Text that earns ranking in App Store search comes from three fields: **name**, **subtitle**, **keyword field**. The description does not count toward in-store ranking (it is used by web search).

## Keyword selection

1. Set `relevance` (0–1) for the candidates in `metadata/research/keywords/<locale>.json`: does the app really do the job of the person searching for this term? If not, 0.
2. `total = relevance × (0.35 + 0.65 × popularity) × (1 − 0.7 × competition)` — computed by the CLI (`vitrin write` recomputes it after you set relevance). `popularity.source: "estimate"` is an estimate from the rating volume of the apps that rank for the term; do not present it as an exact number. `competition` = how many of the top 10 carry the term in their name, plus how entrenched they are (median ratings).
3. Distribution: the strongest 1–2 terms go into the **name**, the next 1–2 into the **subtitle**, the rest into the **keyword field**. Write them to the `selected` field — validate checks that each selected term really is in its field (`keywords.plan-mismatch`).
4. `ownRank` is where the app ranks for the term today (live apps). Keep the terms it ranks top 10 for (`keywords.drops-ranked-term`), and see `metadata/research/live-listing.json` for what the listing says now.

## Measure

Run `vitrin rank` before a metadata change and again one to two weeks after it: it records the app's own rank for the selected and best-scored terms in `metadata/rankings/<date>.json` (kept in git, outside `research/`, so it survives the research clean-up) and prints the change since the previous snapshot. Use the result for the next iteration: keep what moved up, replace what did not.

## Name (2–30)

- Brand + primary keyword: `Ritim: Alışkanlık Takibi` (Turkish for "Ritim: Habit Tracker"). The brand alone is not enough (`aso.name-brand-only`); keyword stuffing is also forbidden.

## Subtitle (≤ 30)

- Benefit + secondary keyword. **Do not repeat** words from the name (validate reports an error). Use it — an empty subtitle or one under 20 characters gives away the second most weighted field (`aso.subtitle-empty`, `aso.subtitle-short`).

## Keyword field (≤ 100 bytes)

- Comma-separated, **no spaces**: `goal,routine,streak`. Every space costs a byte.
- **The byte trap:** Turkish ç ş ğ ı ö ü are 2 bytes each in UTF-8; Japanese/Chinese/Korean characters are 3 bytes. `alışkanlık` ("habit") = 13 bytes for 10 characters.
- Use the singular; plurals still match. Do not include words from the name/subtitle, the developer name, competitor/brand names, Apple marks (iPhone, iPad, Apple Watch…), prices, or "free".
- Every term longer than 2 characters (except CJK). Low-value words such as `app`, `iphone` or `uygulama` ("app") waste bytes.
- Do not leave bytes unused (< 90 bytes triggers a warning).

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
