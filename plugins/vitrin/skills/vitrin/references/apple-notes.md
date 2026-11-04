# Apple notes (October 24, 2026)

The pages below were read before any code was written. When the master prompt ([docs/design/master-prompt.md](design/master-prompt.md)) and the current documentation disagree, the documentation wins; the differences are listed at the end.
The values are encoded in `data/targets.json`, `data/asc-locales.json`, `data/storefront-languages.json` and `packages/schemas/src/limits.ts`.

## Screenshots — Screenshot specifications

- 1–10 screenshots per device size and locale; `.jpeg`, `.jpg`, `.png`; no alpha/transparency. Missing sizes are scaled from a fallback class.
- **iPhone, Dynamic Island medium display: 1206×2622 or 1179×2556 — required (at least one set).** Fallback: Face ID large.
- iPhone, Dynamic Island large display: 1320×2868, 1290×2796, 1260×2736 — not required. Fallback: Face ID large.
- Face ID large: 1284×2778, 1242×2688 — required if the app runs on iPhone and no Dynamic Island large set is provided.
- **iPhone Duo outer: 1398×2034 / 2034×1398; inner: 2007×2853 / 2853×2007.** Required from April 2027 for apps built with the iOS 27.1 SDK. Once uploaded, the product page shows an "Optimized for iPhone Duo" badge.
- **iPad 13": 2064×2752 / 2048×2732 — required for apps that run on iPad.** 12.9" and 11" fall back to 13".

## Other Apple platforms (re-checked October 26, 2026)

Read from the screenshot and app preview specification pages on October 26, 2026 (`curl` of the live pages); encoded as `mac-16x10`, `watch-ultra`, `watch-series`, `appletv-4k`, `vision-pro`, `preview-mac`, `preview-tv` in `data/targets.json`.

- **Mac:** 16:10, one of 1280×800, 1440×900, 2560×1600, 2880×1800 — required for Mac apps. Vitrin renders 2880×1800 (1440×900 @2x).
- **Apple TV:** 1920×1080 or 3840×2160 — required for Apple TV apps. Vitrin renders 3840×2160.
- **Apple Vision Pro:** 3840×2160 — required for visionOS apps.
- **Apple Watch:** one of 422×514 (Ultra 4, Ultra 3), 410×502 (Ultra 2, Ultra), 416×496 (Series 12, 11, 10), 396×484 (Series 9, 8, 7), 368×448 (Series 6, 5, 4, SE 3, SE 2, SE), 312×390 (Series 3, 2, 1) — required for Apple Watch apps; **the same size must be used across all localizations.** Vitrin produces `watch-ultra` (422×514) by default; `watch-series` (416×496) is an opt-in alternative, never both.
- **App Previews:** Mac 1920×1080, Apple TV 1920×1080, Vision Pro 3840×2160 (all landscape, 16:9; Vision Pro only landscape). `preview-mac` / `preview-tv` / `preview-vision` are opt-in like `preview-ipad`. H.264 High@4.0 is the iPhone/iPad preview profile; the Vision Pro preview is 4K, so `preview-vision` pins no H.264 level.
- **Not verified:** the simctl device type names (`Apple Watch Ultra 3 (49mm)`, `Apple Watch Series 11 (46mm)`, `Apple TV 4K (3rd generation)`, `Apple Vision Pro`) — no Xcode on the machine that wrote this; `capture.simulators` overrides them. Their display types are in `data/asc-display-types.json` (see “ASC API 4.5.1”).

### Platform detection

`vitrin analyze` fills `app.platforms` from the Xcode targets that ship (applications and watch apps; not extensions, tests or the watch container stub):
SDKROOT / SUPPORTED_PLATFORMS `iphoneos` → iOS, `macosx` or `SUPPORTS_MACCATALYST = YES` → macOS, `watchos` → watchOS, `appletvos` → tvOS, `xros` (or TARGETED_DEVICE_FAMILY 7) → visionOS.
"Designed for iPad/iPhone" on Mac or Vision Pro (`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD`, `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD`) does **not** add a platform: App Store Connect shows the iPad screenshots there.

### iPhone Duo heuristic

Every iPhone app runs on iPhone Duo, but Duo screenshots are only asked for (and from April 2027 required) for apps built with the iOS 27.1 SDK, which also earns the "Optimized for iPhone Duo" badge. Project files cannot prove the SDK of a build, so `app.supportsDuo` is true when the app runs on iPhone **and** either `LastUpgradeCheck` / `LastSwiftUpdateCheck` ≥ 2710 (the project was upgraded in Xcode 27.1+) or `IPHONEOS_DEPLOYMENT_TARGET` ≥ 27.1. Otherwise Duo targets stay off and the analyzer leaves a todo; `targets.enable: [duo-outer, duo-inner]` overrides it. A false negative is possible for teams that build with Xcode 27.1 without accepting the project upgrade — check before April 2027.

## App Preview — App preview specifications

- iPhone Duo, 6.9", 6.5", 6.1" (Dynamic Island medium), 5.8": **886×1920** (reversed in landscape).
- iPad 13", 11", 10.5": **1200×1600**. Mac/Apple TV 1920×1080, Vision Pro 3840×2160.
- 15–30 s, at most 500 MB, at most 30 fps, default poster frame at 5 seconds, at most 3 per device and locale, processing can take up to 24 hours; previews appear before screenshots.
- H.264: `.mov/.m4v/.mp4`, 10–12 Mbps, progressive, at most High Profile Level 4.0, stereo AAC 256 kbps 44.1/48 kHz.
- ProRes 422 (HQ only): `.mov`, ~220 Mbps VBR, audio PCM or AAC 256 kbps.

## Creative assets — Creative assets specifications

- Product page header 21:9: **3840×1646** image or video (5–30 s, 30/60 fps).
- Search result 3:2: **1920×1280 – 3840×2560** image or video (5–30 s, 30/60 fps). Muted in search and cannot be unmuted.
- **16:9, 5244×2950, PNG only** — an alternative format for both the product page header and the search result asset (not rendered by Vitrin yet).
- In-App Event card 16:9 (1920×1080–3840×2160), detail 9:16 (1080×1920–2160×3840); video 15–30 s; 500 MB.
- Product page videos are muted by default; the user can turn sound on.

## Text fields — Platform version information, App information

| Field | Limit | Note |
| --- | --- | --- |
| Name | 2–30 characters | |
| Subtitle | 30 characters | |
| Promotional text | 170 characters | |
| Description | 4000 characters | plain text, no HTML |
| Keywords | 100 **bytes** | each keyword longer than 2 characters; do not repeat the app or company name |
| What's New | 4000 characters | not available for the first version |
| Review notes | 4000 **bytes** | the demo account must not expire |
| Copyright | — | starts with the year ("2026 Company"); © is added automatically |
| Support / Marketing URL | full URL with protocol | support URL is required |
| Privacy URL | — | required for iOS and macOS |
| Subcategory | — | 1–2 for Games/Stickers |

## Locales — App Store localizations

- 50 locales. The page gives language names; the codes were taken from the fastlane deliver language list (`ar-SA, bn-BD, ca, … zh-Hans, zh-Hant`).
- The full storefront → default + additional languages table is in `data/storefront-languages.json` (175 storefronts). Examples: Mexico = Spanish (Mexico) + English (U.K.); Türkiye = English (U.K.) + Turkish; United States = English (U.S.) + 9 additional languages.

## ASC API 4.5.1

Source: the **App Store Connect API OpenAPI specification 4.5.1** (`info.version` `4.5.1`; Apple's download `https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip`, read from the offline snapshot `docs/openapi/latest.json` of [rorkai/App-Store-Connect-CLI](https://github.com/rorkai/App-Store-Connect-CLI) (MIT), synced 2026-10-07). The enums and request schemas Vitrin uses are copied unchanged into `packages/upload/test/fixtures/asc-openapi-4.5.1-subset.json`, and every request body Vitrin sends is validated against them in `packages/upload/test/asc-media.test.ts`. The mapping per target is `data/asc-display-types.json`.

- **Release notes:** App Screenshot Sets, App Screenshots, App Preview Sets, App Previews, App Event Screenshots and App Event Video Clips are deprecated in favour of the App Asset Library. **The 4.5.1 spec still publishes all of their operations without a `deprecated` flag** (`POST /v1/appScreenshotSets`, `POST|PATCH|DELETE /v1/appScreenshots`, `PATCH /v1/appScreenshotSets/{id}/relationships/appScreenshots`, the `appPreview*` equivalents, `GET /v1/appStoreVersionLocalizations/{id}/appScreenshotSets?filter[screenshotDisplayType]=…`), and asc uses them.
- **Classic types:** `ScreenshotDisplayType` = `APP_IPHONE_67, 61, 65, 58, 55, 47, 40, 35`, `APP_IPAD_PRO_3GEN_129, APP_IPAD_PRO_3GEN_11, APP_IPAD_PRO_129, APP_IPAD_105, APP_IPAD_97`, `APP_DESKTOP`, `APP_WATCH_ULTRA, APP_WATCH_SERIES_10, 7, 4, 3`, `APP_APPLE_TV`, `APP_APPLE_VISION_PRO` and the `IMESSAGE_APP_*` variants. **There is no `APP_IPHONE_69` and no Duo type:** 6.9" screenshots (1320×2868, 1290×2796, 1260×2736) go into `APP_IPHONE_67` (asc's `internal/screenshotcatalog/catalog.go` maps its local alias `APP_IPHONE_69` → `APP_IPHONE_67` for the same reason). `PreviewType` = `IPHONE_67, 61, 65, 58, 55, 47, 40, 35`, `IPAD_PRO_3GEN_129, IPAD_PRO_3GEN_11, IPAD_PRO_129, IPAD_105, IPAD_97`, `DESKTOP`, `APPLE_TV`, `APPLE_VISION_PRO`.
- **Classic upload flow:** `POST /v1/appScreenshots` (`fileName`, `fileSize`, relationship `appScreenshotSet`) → `uploadOperations` (method, url, offset, length, requestHeaders) → `PATCH` with `uploaded: true` and `sourceFileChecksum` (MD5) → poll `assetDeliveryState.state` (`AWAITING_UPLOAD`, `UPLOAD_COMPLETE`, `COMPLETE`, `FAILED`). App Previews: `POST /v1/appPreviews` also takes `mimeType` and `previewFrameTimeCode`; `assetDeliveryState` is deprecated there in favour of `videoDeliveryState` (adds `PROCESSING`).
- **Asset Library enums:** `AppAssetLibraryPlacementType` = `APP_SCREENSHOT, IMESSAGE_APP_SCREENSHOT, APP_PREVIEW, PRODUCT_PAGE_HEADER_ASSET, APP_STORE_SEARCH_RESULTS_ASSET, SEARCH_RESULTS_ADS_ASSET, TODAY_TAB_ADS_ASSET, EVENT_CARD_ASSET, EVENT_DETAILS_PAGE_ASSET, RETENTION_MESSAGE_ASSET`. `AppAssetLibraryDisplayClass` = `DEFAULT, WATCH_ULTRA, WATCH_SERIES_10, 7, 4, 3, IPHONE_DUO, IPHONE_DYNAMIC_ISLAND_LARGE_DISPLAY, IPHONE_DYNAMIC_ISLAND_MEDIUM_DISPLAY, IPHONE_FACE_ID_LARGE_DISPLAY, IPHONE_FACE_ID_MEDIUM_DISPLAY, IPHONE_HOME_BUTTON_LARGE/MEDIUM/40/35_DISPLAY, IPAD_13_DISPLAY, IPAD_11_DISPLAY, IPAD_129_DISPLAY, IPAD_105_DISPLAY, IPAD_97_DISPLAY` — there is no Mac, TV or Vision class: those use `DEFAULT` with `AppAssetLibraryPlacementPlatform` `MAC_APP_STORE`, `TV_APP_STORE`, `VISION_PRO_APP_STORE` (others: `IPHONE_APP_STORE, IPAD_APP_STORE, WATCH_APP_STORE, IMESSAGE_APP_STORE, ANY`). `AppAssetLibraryAssetCategory` = `CREATIVE_ASSETS, APP_SCREENSHOTS_AND_PREVIEWS`.
- **Asset Library requests:** `POST /v1/appAssetLibraryImages|Videos` requires `fileName`, `fileSize`, `category` and the `assetLibrary` relationship (`GET /v1/apps/{id}/assetLibrary` gives its id); videos may carry `previewFrameTimeCode`. The commit is `PATCH` with `uploaded: true` — **no `sourceFileChecksum`** on these resources. Processing is the top-level `state` (`AppAssetLibraryAssetState`: `AWAITING_UPLOAD, UPLOAD_COMPLETE, FAILED, COMPLETE, PREPARE_FOR_SUBMISSION, … APPROVED, REJECTED, ARCHIVED`) with `stateDetails`. `POST /v1/appAssetLibraryPlacements` takes attributes `placementType` (required) and `placementGroup`, and relationships `image` or `video` plus exactly one of `appStoreVersionLocalization`, `appCustomProductPageLocalization`, `appEventLocalization`, `appStoreVersionExperimentTreatmentLocalization`. **Placements have no `displayClass` attribute**: the device set is the `placementGroup`, an id from `GET /v1/appAssetLibraryRefData` → `placementProfileGroups[] { placementProfileGroupId, platform, displayClassId }` (refData also lists `placementTypes[].specMappings[].placementGroupId`, `displayClasses[].screenDimensions`, `imageSpecs`, `videoSpecs`, `features`). `GET /v1/{owner}/{id}/placements` filters by `placementType`, `placementGroup`, `state`. Order: `POST /v1/appAssetLibraryPlacementOrderingRequests` with `placementGroup` + `orderedPlacements` + the owner localization (not for In-App Event localizations).
- `IPHONE_DUO` is in `AppAssetLibraryDisplayClass` (also in the release notes).

### How Vitrin uploads (packages/upload)

- **Every set, one display type at a time** through the asc CLI: `asc screenshots|video-previews upload --replace` (see “asc as the only App Store uploader” below). Vitrin's own classic client, `screenshot-sets.ts`, does the same and stays available (`uploadPerDisplayType({ classic: 'api' })`): find the set of that localization and type (`filter[screenshotDisplayType]` / `filter[previewType]`, refusing if the response holds another type), create it if missing, delete only its items, reserve → upload operations → commit with MD5 → poll, then set the order (`PATCH …/relationships/appScreenshots|appPreviews`). Limits (10 screenshots, 3 previews) and every file are checked before anything is deleted. Other display types and locales are never read or written.
- **App Asset Library** only where the classic API has no type: iPhone Duo screenshots, product page header and search creatives (`--creatives`). `asset-library.ts` resolves the `placementGroup` from refData (platform + displayClassId), deletes only placements whose `placementType` **and** `placementGroup` match (refusing if the filtered list contains anything else), uploads with the right `category`, places and requests the order. Header, search and event creatives use `DEFAULT_PROFILE` when refData lists no group for them (the value asc sends).
- `vitrin doctor` saves refData to `metadata/.cache/refdata.json` and checks that every screenshot/preview mapping has a placement group, that the target sizes are among the class's `screenDimensions`, and that refData has no display class the spec does not list.

### Open points (not settled by the spec)

1. **Which display class a size belongs to** is not in the spec: Vitrin maps 6.3" → `IPHONE_DYNAMIC_ISLAND_MEDIUM_DISPLAY`, 6.9" → `…_LARGE_DISPLAY`, iPad 13" → `IPAD_13_DISPLAY`, and the 886×1920 iPhone preview → `…_LARGE_DISPLAY` (classic `IPHONE_67`). The live refData (`displayClasses[].screenDimensions`) confirms or refutes this; doctor reports any mismatch.
2. **`placementGroup` ids** are runtime data (refData), not an enum. asc documents `IPHONE_DUO_PROFILE` and `DEFAULT_PROFILE`; Vitrin never hard-codes a device group.
3. **iPhone Duo in the classic API:** not in 4.5.1's `ScreenshotDisplayType`/`PreviewType`. asc accepts `APP_IPHONE_DUO` / `IPHONE_DUO` as device types anyway (unverified against the spec); Vitrin uses the Asset Library for Duo in every uploader. Whether a Duo App Preview has its own placement group is unknown (Vitrin renders no Duo preview).
4. **Processing states:** which `AppAssetLibraryAssetState` a finished `APP_SCREENSHOTS_AND_PREVIEWS` image reports first (`COMPLETE` or `PREPARE_FOR_SUBMISSION`); Vitrin accepts either. asc waits for `PREPARE_FOR_SUBMISSION` on creative images.
5. **Deprecation timeline** of the classic set endpoints: the release notes deprecate them, the spec still lists them, and asc uses them. If Apple starts rejecting them, the per-display-type sets have to move to the App Asset Library (`asset-library.ts` already handles Duo that way).

## Store metadata layout

- `metadata/store/metadata`, which the asc export reads: `<locale>/{name,subtitle,privacy_url,description,keywords,release_notes,support_url,marketing_url,promotional_text}.txt`; root: `copyright.txt`, `primary_category.txt`, `secondary_category.txt`, subcategory files; `review_information/{first_name,last_name,phone_number,email_address,notes}.txt`.
- Vitrin names previews after their `PreviewType`: `NN_IPHONE_67.mp4`, `NN_IPAD_PRO_3GEN_129.mp4`, `NN_DESKTOP.mp4`, `NN_APPLE_TV.mp4`, `NN_APPLE_VISION_PRO.mp4` (886×1920 covers all modern iPhone classes; the classic enum has no 6.9" type), and screenshots `NN_<slug>_<target>.png`.
- There is no watchOS App Store version: **Apple Watch screenshots belong to the iOS version**. Display types by pixel size: `APP_WATCH_ULTRA` 410×502 / 422×514, `APP_WATCH_SERIES_10` 416×496, `SERIES_7` 396×484, `SERIES_4` 368×448, `SERIES_3` 312×390. Mac (`APP_DESKTOP`): 1280×800, 1440×900, 2560×1600, 2880×1800. Apple TV: 1920×1080, 3840×2160. Vision Pro: 3840×2160.

## Differences from the master prompt and open questions

1. **Duo in the classic API:** the 4.5.1 spec has no Duo `ScreenshotDisplayType`; Duo sets go through the App Asset Library (`IPHONE_DUO`, in the spec). Verify on the first real run.
2. **The preview file name list** does not include 6.9"/Duo; 886×1920 is uploaded under the `IPHONE_67` name — the only 6.7"/6.9" `PreviewType` in the spec. According to Apple, this resolution is accepted for all modern classes.
3. **Asset Library attribute names — settled by the 4.5.1 spec** (see “ASC API 4.5.1”). The earlier guesses (`SCREENSHOT`, `PRODUCT_PAGE_HEADER`, `SEARCH_RESULT`, a `displayClass` attribute, `IPHONE_61`/`IPHONE_69`/`IPAD_PRO_3GEN_129`/`DESKTOP`/`APPLE_TV`/`APPLE_VISION_PRO` as display classes) were wrong and are gone. What remains open is listed under “Open points”.
4. **5244×2950 PNG variant — answered:** Apple's creative assets specifications list a 16:9 5244×2950 PNG as an alternative format for both the product page header and the search result asset. Vitrin does not render it yet (it renders the 21:9 header and the 3:2 search result).
5. **Apple Ads popularity:** the Apple Ads Campaign Management API has no endpoint that returns popularity for an arbitrary term (the 1–5 indicator exists only in the web UI). If a key is present, this is reported explicitly and popularity is marked as an "estimate"; if an AppTweak key is present, popularity is read from AppTweak.
6. **New age rating questions** (social media, September 2026): Vitrin only produces draft answers, and the final approval stays with the user.

## Sources

- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications
- https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications
- https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations
- https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-5-1-release-notes
- App Store Connect API OpenAPI specification 4.5.1 (https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip; offline snapshot `docs/openapi/latest.json` in rorkai/App-Store-Connect-CLI, MIT)
- https://github.com/rorkai/App-Store-Connect-CLI (MIT): `commands/{metadata,screenshots,video-previews,validate}.mdx`, `authentication.mdx`, `internal/{asc,screenshotcatalog,cli/assets,cli/metadata,cli/shared}`

## asc as an optional uploader (October 26, 2026)

Superseded on November 3, 2026: asc is now the only App Store uploader (last section). The command details below are current.

`upload.uploader: asc` in `vitrin.config.yaml` (or `vitrin upload --uploader=asc`) uploads to App Store Connect with the [`asc` CLI](https://github.com/rorkai/App-Store-Connect-CLI) (MIT, `brew install asc`). Read from asc's `commands/*.mdx`, `authentication.mdx` and Go source; implementation in `packages/upload/src/asc-cli.ts` (pure command builders, tested with a recorded runner — the binary is never run in tests).

- **Text:** `asc metadata push --app <id> --version <v> --platform IOS|MAC_OS|TV_OS|VISION_OS --dir metadata/asc/<platform>/metadata` (`--dry-run` during `vitrin upload --dry-run`). Layout (`internal/cli/metadata/foundation.go`; the docs' tree says `versions/`, the code reads `version/`): `app-info/<locale>.json` (`name`, `subtitle`, `privacyPolicyUrl`) and `version/<version>/<locale>.json` (`description`, `keywords`, `marketingUrl`, `promotionalText`, `supportUrl`, `whatsNew`), generated from the store text export. A missing field leaves the remote value; an emptied `subtitle`/`promotionalText`/`privacyPolicyUrl` is written as `null` (asc's only clearable fields; the push then adds `--confirm`, which never enables deletes — that is `--allow-deletes`, which Vitrin never passes). App info is pushed with the first platform only. asc's metadata push does not cover categories, copyright or review information; the plan says so.
- **Media:** per locale and classic display type, `asc screenshots upload --version-localization <id> --path <dir> --device-type <APP_…> --replace --confirm` and `asc video-previews upload … --device-type <PreviewType> --replace --confirm`. `--replace` deletes the existing items of that one set only. Files are staged in `metadata/asc/<platform>/media/<locale>/<type>/` with an `NN_` prefix so asc's sorted directory read keeps Vitrin's order. iPhone Duo is not sent through asc (see open point 3); it goes through the App Asset Library.
- **Auth:** asc's documented environment credential — `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_TYPE=team` and one of `ASC_PRIVATE_KEY_PATH` / `ASC_PRIVATE_KEY_B64` — built from Vitrin's `.env` (`ASC_KEY_PATH` → absolute `ASC_PRIVATE_KEY_PATH`, `ASC_KEY_CONTENT_BASE64` → `ASC_PRIVATE_KEY_B64`); `ASC_PROFILE` and the other key sources are cleared so a stored profile cannot win (authentication.mdx resolution matrix). Values only go into the child environment and are registered for log masking.
- **doctor:** with `uploader: asc`, `asc version` must succeed (fix: `brew install asc`). With `upload.ascValidate: true`, doctor also runs `asc validate --app <id> --platform <p>` (submission readiness: build, metadata, screenshots, age rating, pricing, review contact); a non-zero exit is a warning.
- Not verified on a real account: asc's exit codes for partial failures (it documents `0`/`1` and `10–99` for HTTP errors), the exact `asc version` output format (`asc --version` prints `v1.2.3 (commit: …)`), and whether an empty `ASC_PROFILE`/`ASC_PRIVATE_KEY` counts as unset for asc.

## asc as the only App Store uploader (November 3, 2026)

The deliver uploader and the App-Asset-Library-only mode were removed; every App Store upload uses the asc CLI (checked against asc 5.17.1: `asc auth --help`, `asc auth status --help`, `asc api --help`, `asc versions create --help`, `asc review submit --help`).

- **Config:** `upload.uploader` is `asc` or unset. An old `deliver` / `asset-library` still parses, behaves like asc, and `loadConfig` warns once per file; `vitrin select` deletes the line. `vitrin uploader --json` keeps its shape and lists only asc; `--uploader` on `init`, `select` and `upload` is hidden and accepts only `asc` (`init`/`select` warn about other values, `upload` refuses them).
- **Plan:** every selected set is replaced one display type at a time (`ReplaceMode` is `per-display-type` or `skip`); there is no overwrite of a whole locale any more.
- **Auth:** a Vitrin key (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` | `ASC_KEY_CONTENT_BASE64`) is mapped to asc's environment credential as before. With none of these set, Vitrin overrides nothing and asc resolves its own credential (`--profile`/`ASC_PROFILE`, then the keychain or `.asc/config.json` profile from `asc auth login`). `asc auth status --output json` (`credentials[]`, `environmentCredentialsComplete`) tells whether one exists; then doctor and the Studio do not ask for the ASC keys, and Vitrin's own API calls go through `asc api <METHOD> <path> --allow-unknown-path [--confirm --body-file -]` (`AscCliClient`), which prints Apple's JSON envelope and accepts full `links.next` URLs. A half-filled Vitrin key is an error.
- **Versions and submit:** `vitrin doctor --create-version <v>` runs `asc versions create --app <id> --version <v> --platform <p> --if-exists skip`; `vitrin submit` runs `asc review submit --app <id> --version-id <id> --platform <p> --latest --confirm` (attaches the newest eligible build of that version).
- **Not covered by asc metadata push:** categories, copyright and review information (they were uploaded by deliver before). They stay as they are in App Store Connect.

