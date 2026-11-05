import { ensureDir, existsSync, log, readJsonIfExists, writeJson } from '@vitrin/core';
import { checkRanks, compareRanks, rankHighlights, rivalsToTrack, storefrontPlan } from '@vitrin/research';
import { Competitors, KeywordPlan, RankSnapshot } from '@vitrin/schemas';
import { readdir } from 'node:fs/promises';
import { join } from 'node:path';
import pc from 'picocolors';
import { bundleIdOf, EXIT, loadProfile, type Ctx } from '../context.js';

/**
 * `vitrin rank`: the app's own search rank for its chosen terms today, saved as metadata/rankings/<date>.json and
 * compared with the previous snapshot. Run it before a metadata change and again one to two weeks after it.
 */
export async function rankCommand(ctx: Ctx): Promise<number> {
  const profile = await loadProfile(ctx);
  const bundleId = bundleIdOf(ctx, profile);
  const plans = new Map<string, KeywordPlan>();
  for (const locale of ctx.config.app.locales) {
    const plan = await readJsonIfExists(ctx.paths.keywordFile(locale), KeywordPlan).catch(() => undefined);
    if (plan) plans.set(locale, plan);
  }
  const today = new Date().toISOString().slice(0, 10);
  const previous = await latestSnapshot(ctx.paths.rankings, today);
  const competitors = await readJsonIfExists(ctx.paths.competitors, Competitors).catch(() => undefined);
  const rivals = rivalsToTrack(ctx.config.research.rivals, previous, competitors, storefrontPlan(ctx.config).map((p) => p.storefront));
  const snapshot = await checkRanks({ paths: ctx.paths, config: ctx.config, bundleId, plans, rivals });
  await ensureDir(ctx.paths.rankings);
  const file = join(ctx.paths.rankings, `${snapshot.date}.json`);
  await writeJson(file, snapshot);

  const rank = (r: number | null) => (r === null ? '—' : `#${r}`);
  for (const row of compareRanks(previous, snapshot)) {
    const move = row.delta === null ? (row.before === null && row.after !== null && previous ? pc.green(' new') : '') : row.delta > 0 ? pc.green(` ▲${row.delta}`) : row.delta < 0 ? pc.red(` ▼${-row.delta}`) : pc.dim(' =');
    log.info(`${pc.dim(row.locale)} ${row.term}: ${rank(row.after)}${previous ? pc.dim(` (was ${rank(row.before)})`) : ''}${move}${rivalLine(snapshot, row)}`);
  }
  if (snapshot.entries.every((e) => e.rank === null)) log.warn(`The app is not in the first ${ctx.config.research.limit} results for any tracked term (not live yet, or ranked lower).`);
  const changes = compareRanks(previous, snapshot);
  log.result({ date: snapshot.date, previous: previous?.date ?? null, highlights: previous ? rankHighlights(changes) : null });
  log.ok(`${previous ? `Compared with ${previous.date}; s` : 'S'}aved metadata/rankings/${snapshot.date}.json`);
  return EXIT.OK;
}

/** Rivals ahead of the app for this term, nearest first. */
function rivalLine(snapshot: RankSnapshot, row: { locale: string; term: string; after: number | null }): string {
  const entry = snapshot.entries.find((e) => e.locale === row.locale && e.term === row.term);
  const ahead = Object.entries(entry?.rivals ?? {})
    .filter((e): e is [string, number] => e[1] !== null && (row.after === null || e[1] < row.after))
    .sort((a, b) => a[1] - b[1])
    .map(([id, r]) => `${snapshot.rivalNames?.[id] ?? id} #${r}`);
  return ahead.length ? pc.dim(`  behind ${ahead.join(', ')}`) : '';
}

/** The newest snapshot written before `date` (a re-run on the same day compares with the day before, not itself). */
export async function latestSnapshot(dir: string, date: string): Promise<RankSnapshot | undefined> {
  if (!existsSync(dir)) return undefined;
  const last = (await readdir(dir))
    .filter((f) => /^\d{4}-\d{2}-\d{2}\.json$/.test(f) && f.slice(0, 10) < date)
    .sort()
    .at(-1);
  return last ? readJsonIfExists(join(dir, last), RankSnapshot) : undefined;
}
