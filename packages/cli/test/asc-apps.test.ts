import { mask } from '@vitrin/core';
import { AscClient } from '@vitrin/upload';
import { generateKeyPairSync } from 'node:crypto';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { ASC_APPS_PATH, ascAppsCommand, latestPerPlatform, listAscApps, platformLabel } from '../src/commands/asc.js';
import { NeedsInput } from '../src/context.js';
import { compareVersions } from '../src/commands/doctor.js';

// ---- a stubbed App Store Connect: `GET /v1/apps?include=appStoreVersions` as the API answers it ----------------------

const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
const creds = { keyId: 'KEY1234567', issuerId: '69a6de7e-0000-0000-0000-000000000000', privateKey: pem };

const app = (id: string, attributes: Record<string, unknown>, versionIds: string[]) => ({
  type: 'apps',
  id,
  attributes,
  relationships: { appStoreVersions: { data: versionIds.map((vid) => ({ type: 'appStoreVersions', id: vid })) } },
});
const version = (id: string, platform: string, versionString: string, appVersionState: string) => ({
  type: 'appStoreVersions',
  id,
  attributes: { platform, versionString, appVersionState },
});

const PAGE_1 = {
  data: [
    app('100', { name: 'Ritim', bundleId: 'com.jastech.ritim', sku: 'RITIM1', primaryLocale: 'en-US' }, ['v1', 'v2', 'v3', 'v4']),
    app('200', { name: 'Acorn', bundleId: 'com.jastech.acorn', sku: 'ACORN', primaryLocale: 'tr' }, []),
  ],
  included: [
    version('v1', 'IOS', '1.9.0', 'READY_FOR_SALE'),
    version('v2', 'IOS', '2.0.0', 'PREPARE_FOR_SUBMISSION'),
    version('v3', 'MAC_OS', '1.0.0', 'IN_REVIEW'),
    version('v4', 'IOS', '1.8.0', 'REPLACED_WITH_NEW_VERSION'),
  ],
  links: { next: 'https://api.appstoreconnect.apple.com/v1/apps?cursor=AQ' },
};
const PAGE_2 = {
  data: [app('300', { name: 'Zed', bundleId: 'com.jastech.zed', sku: 'ZED', primaryLocale: 'de-DE' }, ['v5'])],
  included: [{ type: 'appStoreVersions', id: 'v5', attributes: { platform: 'VISION_OS', versionString: '3.1', appStoreState: 'WAITING_FOR_REVIEW' } }],
};

function stubbedFetch(pages: Record<string, unknown> = { first: PAGE_1, 'cursor=AQ': PAGE_2 }) {
  const calls: Array<{ url: string; auth: string }> = [];
  const fetchImpl = (async (url: string, init?: RequestInit) => {
    const headers = init?.headers as Record<string, string>;
    calls.push({ url: String(url), auth: headers.Authorization });
    const body = String(url).includes('cursor=AQ') ? pages['cursor=AQ'] : pages.first;
    return new Response(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } });
  }) as typeof fetch;
  return { fetchImpl, calls };
}

describe('listAscApps', () => {
  it('lists every page, keeps the newest version per platform and derives the platforms', async () => {
    const { fetchImpl, calls } = stubbedFetch();
    const apps = await listAscApps(new AscClient(creds, fetchImpl));
    expect(calls.map((c) => c.url)).toEqual(['https://api.appstoreconnect.apple.com' + ASC_APPS_PATH, 'https://api.appstoreconnect.apple.com/v1/apps?cursor=AQ']);
    expect(calls[0]!.auth).toMatch(/^Bearer /);
    expect(apps.map((a) => a.name)).toEqual(['Acorn', 'Ritim', 'Zed']);
    const ritim = apps[1]!;
    expect(ritim).toMatchObject({ id: '100', bundleId: 'com.jastech.ritim', sku: 'RITIM1', primaryLocale: 'en-US', platforms: ['IOS', 'MAC_OS'] });
    expect(ritim.versions).toEqual([
      { id: 'v2', platform: 'IOS', version: '2.0.0', state: 'PREPARE_FOR_SUBMISSION' },
      { id: 'v3', platform: 'MAC_OS', version: '1.0.0', state: 'IN_REVIEW' },
    ]);
    // An app without a version yet, and one whose version only has the older appStoreState.
    expect(apps[0]).toMatchObject({ name: 'Acorn', platforms: [], versions: [] });
    expect(apps[2]!.versions).toEqual([{ id: 'v5', platform: 'VISION_OS', version: '3.1', state: 'WAITING_FOR_REVIEW' }]);
  });

  it('asks for the versions in the same request', () => {
    expect(ASC_APPS_PATH).toContain('include=appStoreVersions');
    expect(ASC_APPS_PATH).toContain('fields[appStoreVersions]=platform,versionString,appVersionState,appStoreState&');
    // ASC answers 400 "createdAt is not a valid field name" for fields[appStoreVersions]=…,createdAt.
    expect(ASC_APPS_PATH).not.toContain('createdAt');
    // A sparse fieldset drops every relationship it does not name: without appStoreVersions here, no app has versions.
    expect(ASC_APPS_PATH).toContain('fields[apps]=name,bundleId,sku,primaryLocale,appStoreVersions&');
  });

  it('compares version numbers part by part', () => {
    expect(compareVersions('1.10', '1.9')).toBeGreaterThan(0);
    expect(compareVersions('2.0', '1.99.1')).toBeGreaterThan(0);
    expect(compareVersions('1.0', '1.0.0')).toBe(0);
    expect(compareVersions('1.2.3', '1.2.4')).toBeLessThan(0);
  });

  it('orders the platforms iOS, macOS, tvOS, visionOS and labels them', () => {
    const latest = latestPerPlatform([
      { type: 'appStoreVersions', id: 'a', attributes: { platform: 'VISION_OS', versionString: '1' } },
      { type: 'appStoreVersions', id: 'b', attributes: { platform: 'IOS', versionString: '1' } },
      { type: 'appStoreVersions', id: 'c', attributes: { platform: 'IOS', versionString: '2' } },
      { type: 'appStoreVersions', id: 'd', attributes: { platform: 'TV_OS', versionString: '1' } },
    ]);
    expect(latest.map((v) => `${platformLabel(v.platform)} ${v.version}`)).toEqual(['iOS 2', 'tvOS 1', 'visionOS 1']);
    expect(platformLabel('WEB')).toBe('WEB');
  });
});

describe('vitrin asc apps', () => {
  const writes: string[] = [];
  const spy = vi.spyOn(process.stdout, 'write').mockImplementation((chunk: string | Uint8Array) => {
    writes.push(String(chunk));
    return true;
  });
  afterEach(() => {
    writes.length = 0;
  });

  it('needs the key: exit 2 with the variable names, nothing written', async () => {
    const err = await ascAppsCommand({ env: {}, json: true }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(NeedsInput);
    expect((err as NeedsInput).message).toContain('ASC_KEY_ID');
    expect((err as NeedsInput).code).toBe('keys-missing');
    expect(writes).toEqual([]);
  });

  it('works in any folder with the key in the environment and prints masked JSON', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'vitrin-asc-apps-'));
    const p8 = join(dir, 'AuthKey.p8');
    writeFileSync(p8, pem);
    const env = { ASC_KEY_ID: 'KEY1234567', ASC_ISSUER_ID: creds.issuerId, ASC_KEY_PATH: p8 };
    // No vitrin.config.yaml anywhere near: the command reads only the environment.
    const { fetchImpl } = stubbedFetch({ first: { data: [app('1', { name: 'Named KEY1234567', bundleId: 'com.x', sku: 'S', primaryLocale: 'en-US' }, [])] } });
    const code = await ascAppsCommand({ cwd: dir, env, json: true, fetchImpl });
    expect(code).toBe(0);
    const out = JSON.parse(writes.join('')) as { generatedAt: string; apps: Array<{ name: string; bundleId: string }> };
    expect(out.apps).toEqual([{ id: '1', bundleId: 'com.x', name: mask('Named KEY1234567'), sku: 'S', primaryLocale: 'en-US', platforms: [], versions: [] }]);
    expect(out.apps[0]!.name).not.toContain('KEY1234567');
    expect(out.generatedAt).toMatch(/^\d{4}-/);
  });

  it('prints one line per app without --json', async () => {
    const { fetchImpl } = stubbedFetch();
    spy.mockClear();
    const code = await ascAppsCommand({ env: { ASC_KEY_ID: creds.keyId, ASC_ISSUER_ID: creds.issuerId, ASC_KEY_CONTENT_BASE64: Buffer.from(pem).toString('base64') }, fetchImpl });
    expect(code).toBe(0);
    const text = writes.join('');
    expect(text).toContain('3 app(s) on the team');
    expect(text).toContain('com.jastech.ritim');
    expect(text).toContain('iOS 2.0.0');
    expect(text).toContain('no App Store version yet');
  });
});
