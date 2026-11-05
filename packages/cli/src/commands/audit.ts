import { ensureDir, existsSync, log, readJsonIfExists, writeJson } from '@vitrin/core';
import { auditLocale, auditTotal, storefrontPlan, type AuditListing } from '@vitrin/research';
import { AuditReport, Competitors, KeywordPlan, LiveListing, type AuditLocale } from '@vitrin/schemas';
import { join } from 'node:path';
import pc from 'picocolors';
import { EXIT, type Ctx } from '../context.js';
import { loadLocaleMetadata } from './pipeline.js';
import { latestSnapshot } from './rank.js';

/**
 * `vitrin audit`: where the listing stands, from what research already measured, with no new requests. Scores the
 * live listing when there is one, so it answers "how are we doing" before anything is rewritten.
 */
export async function auditCommand(ctx: Ctx, o: { draft?: boolean } = {}): Promise<number> {
  const competitors = await readJsonIfExists(ctx.paths.competitors, Competitors).catch(() => undefined);
  const live = await readJsonIfExists(ctx.paths.liveListing, LiveListing).catch(() => undefined);
  const drafts = new Map((await loadLocaleMetadata(ctx)).map((m) => [m.locale, m]));
  const today = new Date().toISOString().slice(0, 10);
  const ranks = await latestSnapshot(ctx.paths.rankings, `${today}~`);
  const locales: AuditLocale[] = [];
  for (const { locale } of storefrontPlan(ctx.config)) {
    const plan = await readJsonIfExists(ctx.paths.keywordFile(locale), KeywordPlan).catch(() => undefined);
    if (!plan) continue;
    const draft = drafts.get(locale);
    const liveFields = live?.locales[locale];
    let listing: AuditListing | undefined;
    let listingSource: AuditLocale['listingSource'] = 'none';
    if (liveFields && !o.draft) {
      listing = liveFields;
      listingSource = 'live';
    } else if (draft) {
      listing = { name: draft.name, subtitle: draft.subtitle, keywords: draft.keywords };
      listingSource = 'draft';
    }
    locales.push(auditLocale({ plan, listing, listingSource, ownRatings: competitors?.self?.userRatingCount ?? 0, competitors, ranks }));
  }
  if (!locales.length) {
    log.error('Nothing to audit yet: run `vitrin research` first, the audit reads what it measured.');
    return EXIT.FAIL;
  }
  const report: AuditReport = { date: today, score: auditTotal(locales), locales };
  await ensureDir(ctx.paths.audits);
  await writeJson(join(ctx.paths.audits, `${today}.json`), report);

  for (const l of locales) {
    const s = l.sections;
    const number = (n: number | null) => (n === null ? '—' : String(n));
    log.info(`${pc.bold(`${l.locale} (${l.storefront.toUpperCase()})`)}: ${number(l.score)}/100 ${l.verdict ? pc.dim(l.verdict) : ''}  ${pc.dim(`rankings ${number(s.rankings)} · listing ${number(s.listing)} (${l.listingSource}) · competition ${number(s.competition)}`)}`);
    if (l.ranked.length) log.info(`  ${pc.green('top 10:')} ${l.ranked.slice(0, 5).map((t) => `${t.term} #${t.rank}`).join(', ')}`);
    if (l.gaps.length) log.info(`  ${pc.yellow('gaps:')} ${l.gaps.slice(0, 5).map((t) => `${t.term} (vol ${t.volume}, diff ${t.difficulty})`).join(', ')}`);
    if (l.rivals.length) log.info(`  ${pc.dim('rivals:')} ${l.rivals.slice(0, 3).map((r) => r.name).join(', ')}`);
    for (const t of l.takeaways) log.info(`  → ${t}`);
  }
  if (existsSync(ctx.paths.liveListing) && !o.draft) log.dim('Volume and difficulty are estimates from the apps that rank for a term, not Apple search counts.');
  log.ok(`Saved metadata/audits/${today}.json${report.score === null ? '' : `: ${report.score}/100`}`);
  return EXIT.OK;
}
