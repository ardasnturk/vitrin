import { z } from 'zod';
import { AscLocale, FeatureId } from './common.js';
import { ShotCopy } from './design.js';

/** A sentence or phrase in the copy that makes a product claim, linked to app_profile features. */
export const Claim = z.object({
  text: z.string().min(1),
  featureIds: z.array(FeatureId).min(1),
});
export type Claim = z.infer<typeof Claim>;

/** `metadata/listing/<locale>.json` — written by Claude, validated by the CLI. */
export const LocaleMetadata = z.object({
  locale: AscLocale,
  name: z.string(),
  subtitle: z.string().default(''),
  promotionalText: z.string().default(''),
  description: z.string(),
  /** Comma separated, no spaces after commas. Byte-limited (100 UTF-8 bytes). */
  keywords: z.string(),
  whatsNew: z.string().default(''),
  supportUrl: z.string().optional(),
  marketingUrl: z.string().optional(),
  privacyUrl: z.string().optional(),
  claims: z.array(Claim).default([]),
  /** Optional free-form notes from Claude (not uploaded). */
  notes: z.string().optional(),
});
export type LocaleMetadata = z.infer<typeof LocaleMetadata>;

/** `metadata/listing/app.json` — non-localized, app level. */
export const AppMetadata = z.object({
  copyright: z.string(),
  primaryCategory: z.string(),
  secondaryCategory: z.string().optional(),
  primarySubcategories: z.array(z.string()).max(2).default([]),
  secondarySubcategories: z.array(z.string()).max(2).default([]),
  reviewNotes: z.string().default(''),
  ageRatingDraft: z
    .object({
      answers: z.record(z.string(), z.string()),
      rationale: z.string(),
      needsUserConfirmation: z.literal(true).default(true),
    })
    .optional(),
  accessibilityDraft: z
    .array(z.object({ criterion: z.string(), supported: z.enum(['yes', 'partial', 'no', 'unknown']), evidence: z.string().optional() }))
    .optional(),
});
export type AppMetadata = z.infer<typeof AppMetadata>;

export const CustomProductPage = z.object({
  id: z.string().regex(/^[a-z0-9-]+$/),
  name: z.string().max(30),
  segment: z.string(),
  rationale: z.string(),
  deepLink: z.string().optional(),
  keywords: z.array(z.string()).default([]),
  promotionalText: z.record(AscLocale, z.string()).default({}),
  /**
   * Shot ids from shots.json, in this page's order: `vitrin design` renders them as the page's own screenshot set
   * (metadata/store/cpp/<page id>/) and `vitrin upload --cpp` places them on the page. Lead with the segment's hero.
   */
  shots: z.array(z.string()).default([]),
  /** Per-shot copy for this page's audience: `{ "<shot id>": { "<locale>": { headline, subheadline?, kicker? } } }`. */
  copy: z.record(z.string(), z.record(AscLocale, ShotCopy)).default({}),
  featureIds: z.array(FeatureId).default([]),
});
export type CustomProductPage = z.infer<typeof CustomProductPage>;

export const CppSuggestions = z.object({ pages: z.array(CustomProductPage).max(70) });
export type CppSuggestions = z.infer<typeof CppSuggestions>;
