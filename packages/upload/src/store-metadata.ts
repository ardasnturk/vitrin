import { ensureDir, existsSync, log, writeText, type AppPaths } from '@vitrin/core';
import type { AppMetadata, LocaleMetadata, VitrinConfig } from '@vitrin/schemas';
import { readdir, rm } from 'node:fs/promises';
import { join } from 'node:path';

/** Per-locale text files of the store tree (metadata/store/metadata/<locale>/<name>.txt); `asc metadata push` input is built from them. */
export const LOCALE_FILES: Record<string, (m: LocaleMetadata, c: VitrinConfig) => string | undefined> = {
  'name.txt': (m) => m.name,
  'subtitle.txt': (m) => m.subtitle,
  'description.txt': (m) => m.description,
  'keywords.txt': (m) => m.keywords,
  'promotional_text.txt': (m) => m.promotionalText,
  'release_notes.txt': (m) => m.whatsNew || undefined,
  'support_url.txt': (m, c) => m.supportUrl ?? c.urls.support,
  'marketing_url.txt': (m, c) => m.marketingUrl ?? c.urls.marketing,
  'privacy_url.txt': (m, c) => m.privacyUrl ?? c.urls.privacy,
};

/** Optional fields that must be cleared remotely when emptied locally (release notes stay absent: first versions reject them). */
const CLEARABLE = new Set(['subtitle.txt', 'promotional_text.txt', 'marketing_url.txt']);

/**
 * Writes the App Store text tree (metadata/store/metadata): one `.txt` per field, the files the user reviews and
 * approves, and the source of the asc CLI's metadata export (asc-cli.ts). Demo account credentials are NOT written
 * to disk (.env REVIEW_DEMO_USER / REVIEW_DEMO_PASSWORD only).
 */
export async function exportStoreMetadata(paths: AppPaths, config: VitrinConfig, app: AppMetadata, locales: LocaleMetadata[]): Promise<string[]> {
  const root = paths.storeMetadata;
  const written: string[] = [];
  const write = async (rel: string, value: string | undefined, clearable = false) => {
    const file = join(root, rel);
    if (value === undefined || value === '') {
      // A missing file means "leave the remote value alone"; an empty file clears it.
      if (clearable) await writeText(file, '');
      else if (existsSync(file)) await rm(file);
      return;
    }
    await writeText(file, value.trim() + '\n');
    written.push(file);
  };
  await ensureDir(root);
  for (const m of locales) {
    // Remove files of fields that became empty so no stale text is uploaded.
    for (const [file, get] of Object.entries(LOCALE_FILES)) await write(join(m.locale, file), get(m, config), CLEARABLE.has(file));
  }
  await write('copyright.txt', app.copyright);
  await write('primary_category.txt', app.primaryCategory);
  await write('secondary_category.txt', app.secondaryCategory);
  await write('primary_first_sub_category.txt', app.primarySubcategories[0]);
  await write('primary_second_sub_category.txt', app.primarySubcategories[1]);
  await write('secondary_first_sub_category.txt', app.secondarySubcategories[0]);
  await write('secondary_second_sub_category.txt', app.secondarySubcategories[1]);
  const r = config.review;
  await write('review_information/first_name.txt', r.firstName);
  await write('review_information/last_name.txt', r.lastName);
  await write('review_information/phone_number.txt', r.phone);
  await write('review_information/email_address.txt', r.email);
  await write('review_information/notes.txt', app.reviewNotes);
  for (const legacy of ['demo_user.txt', 'demo_password.txt']) {
    const f = join(root, 'review_information', legacy);
    if (existsSync(f)) {
      await rm(f);
      log.warn(`${legacy} deleted: demo account credentials are never stored in files; .env (REVIEW_DEMO_*) is used instead.`);
    }
  }
  return written;
}

/**
 * Locale folders left from an earlier run whose locale is no longer in app.locales: they would be reviewed and uploaded too.
 * Only folders Vitrin wrote (nothing but the per-locale files above) are removed; a downloaded or hand-made one stays.
 */
export async function pruneStrayLocales(paths: AppPaths, config: VitrinConfig): Promise<string[]> {
  const root = paths.storeMetadata;
  if (!existsSync(root)) return [];
  const removed: string[] = [];
  for (const e of await readdir(root, { withFileTypes: true })) {
    if (!e.isDirectory() || e.name.startsWith('.') || ['default', 'android', 'review_information'].includes(e.name) || config.app.locales.includes(e.name)) continue;
    const dir = join(root, e.name);
    const files = (await readdir(dir)).filter((f) => !f.startsWith('.'));
    if (files.some((f) => !Object.hasOwn(LOCALE_FILES, f))) continue;
    await rm(dir, { recursive: true, force: true });
    removed.push(e.name);
  }
  return removed;
}
