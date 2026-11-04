import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { writeJson } from '@vitrin/core';
import { metadataBrief, profileBrief } from '../src/briefs.js';
import { createContext } from '../src/context.js';
import { makeFixture } from './fixture.js';
import { profileWith } from './helpers.js';

async function setup(userRatingCount?: number) {
  const fx = await makeFixture();
  const ctx = await createContext({ cwd: fx.root });
  const competitors = { generatedAt: '2026-11-04T00:00:00Z', storefronts: ['us'], seeds: [], apps: [], topCharts: [], analysis: { nameTerms: [] }, ...(userRatingCount === undefined ? {} : { self: { trackId: 1, name: 'Ritim', storefront: 'us', userRatingCount } }) };
  await writeJson(ctx.paths.competitors, competitors);
  return ctx;
}

describe('metadata brief', () => {
  const profile = profileWith({ displayName: 'Ritim' });

  it('leads with the keyword for an unknown brand', async () => {
    const body = readFileSync(await metadataBrief(await setup(), profile), 'utf8');
    expect(body).toContain('`Keyword: Ritim`');
    expect(body).not.toContain('`Ritim: keyword`');
  });

  it('lets a known brand lead', async () => {
    const body = readFileSync(await metadataBrief(await setup(50_000), profile), 'utf8');
    expect(body).toContain('`Ritim: keyword`');
    expect(body).not.toContain('`Keyword: Ritim`');
  });

  it('marks stretch terms, asks for single words and says what does not rank', async () => {
    const ctx = await setup();
    await writeJson(ctx.paths.keywordFile(ctx.config.app.locales[0]!), {
      locale: ctx.config.app.locales[0], storefront: 'us', generatedAt: '2026-11-04T00:00:00Z',
      candidates: [
        { term: 'habit tracker', relevance: 1, total: 0.4, ownRank: null, popularity: { score: 0.8, source: 'estimate' }, competition: { resultCount: 50, top10MedianRatings: 500_000, score: 0.8 } },
        { term: 'habit calendar', relevance: 1, total: 0.5, ownRank: null, popularity: { score: 0.4, source: 'estimate' }, competition: { resultCount: 50, top10MedianRatings: 200, score: 0.2 } },
      ],
    });
    const body = readFileSync(await metadataBrief(ctx, profile), 'utf8');
    expect(body).toMatch(/habit tracker \([^)]*, stretch\)/);
    expect(body).not.toMatch(/habit calendar \([^)]*stretch\)/);
    expect(body).toContain('**single words**');
    expect(body).toContain('The description and promotional text do not');
  });

  it('mentions the review prompt only when the code has none', async () => {
    const ctx = await setup();
    expect(readFileSync(await metadataBrief(ctx, profile), 'utf8')).toContain('No native review prompt was found');
    const withPrompt = { ...profile, signals: { 'ratings.prompt': [{ path: 'App.swift', line: 3 }] } };
    expect(readFileSync(await metadataBrief(ctx, withPrompt), 'utf8')).not.toContain('No native review prompt was found');
  });

  it('asks for seeds from each market, not a translation', async () => {
    const body = readFileSync(await profileBrief(await setup(), profile), 'utf8');
    expect(body).toContain('not a translation of another locale');
  });
});
