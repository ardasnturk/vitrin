import { appPaths } from '@vitrin/core';
import { RenderTarget, VitrinConfig, type LocaleMetadata, type RenderManifest } from '@vitrin/schemas';
import { generateKeyPairSync } from 'node:crypto';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import sharp from 'sharp';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  applePlatformsOf,
  AscClient,
  buildPlan,
  collectRenderedAssets,
  appStorePlatformFor,
  formatPlan,
  readBack,
  resolveScope,
  routeAssets,
  type RenderedAsset,
} from '../src/index.js';

// ---- fixtures ------------------------------------------------------------------------------------

function target(id: string, over: Partial<RenderTarget>): RenderTarget {
  return RenderTarget.parse({
    id,
    kind: 'screenshot',
    label: id,
    family: 'iphone',
    width: 100,
    height: 200,
    logical: { width: 100, height: 200, scale: 1 },
    requirement: 'optional',
    defaultEnabled: true,
    formats: ['png'],
    ...over,
  });
}

const TARGETS: RenderTarget[] = [
  target('iphone-6.9', { family: 'iphone', width: 1320, height: 2868 }),
  target('ipad-13', { family: 'ipad', width: 2064, height: 2752 }),
  target('watch-ultra', { family: 'watch', platform: 'watchos', width: 422, height: 514 }),
  target('mac-16x10', { family: 'mac', platform: 'macos', width: 2880, height: 1800 }),
  target('appletv-4k', { family: 'tv', platform: 'tvos', width: 3840, height: 2160 }),
  target('vision-pro', { family: 'vision', platform: 'visionos', width: 3840, height: 2160 }),
  target('preview-iphone', { kind: 'preview', family: 'iphone', width: 886, height: 1920, formats: ['mp4'] }),
  target('preview-mac', { kind: 'preview', family: 'mac', platform: 'macos', width: 1920, height: 1080, formats: ['mp4'] }),
  target('header', { kind: 'creative', family: 'any', width: 3840, height: 1646 }),
];

async function png(file: string, w: number, h: number, alpha = false): Promise<string> {
  mkdirSync(join(file, '..'), { recursive: true });
  await sharp({ create: { width: w, height: h, channels: alpha ? 4 : 3, background: alpha ? { r: 1, g: 2, b: 3, alpha: 0.5 } : { r: 1, g: 2, b: 3 } } })
    .png()
    .toFile(file);
  return file;
}

function touch(file: string, content = 'x'): string {
  mkdirSync(join(file, '..'), { recursive: true });
  writeFileSync(file, content);
  return file;
}

interface Fixture {
  root: string;
  paths: ReturnType<typeof appPaths>;
  manifest: RenderManifest;
  assets: RenderedAsset[];
}

/** One locale (tr) with screenshots for every Apple platform. */
async function fixture(): Promise<Fixture> {
  const root = mkdtempSync(join(tmpdir(), 'vitrin-stores-'));
  const paths = appPaths(root);
  const s = (n: string, t: string) => join(paths.screenshots, 'tr', `${n}_home_${t}.png`);
  const images: RenderManifest['images'] = [];
  const add = async (file: string, t: string, shot: string, w: number, h: number) => {
    await png(file, w, h);
    images.push({ file, target: t, locale: 'tr', shot, width: w, height: h, overflow: [], safeAreaViolations: [] });
  };
  await add(s('01', 'iphone-6.9'), 'iphone-6.9', '01', 1320, 2868);
  await add(s('01', 'watch-ultra'), 'watch-ultra', '01', 422, 514);
  await add(s('01', 'mac-16x10'), 'mac-16x10', '01', 2880, 1800);
  await add(s('01', 'appletv-4k'), 'appletv-4k', '01', 3840, 2160);
  await add(s('01', 'vision-pro'), 'vision-pro', '01', 3840, 2160);
  await add(join(paths.creative, 'tr', 'header_header.png'), 'header', 'header', 3840, 1646);
  const videos: RenderManifest['videos'] = [
    { file: touch(join(paths.appPreviews, 'tr', '01_IPHONE_67.mp4')), target: 'preview-iphone', locale: 'tr', id: '01' },
    { file: touch(join(paths.appPreviews, 'tr', '01_DESKTOP.mp4')), target: 'preview-mac', locale: 'tr', id: '01' },
  ];
  const manifest: RenderManifest = { generatedAt: 'now', artDirection: 'a', images, videos };
  // Text metadata as exportStoreMetadata writes it.
  touch(join(paths.storeMetadata, 'tr', 'name.txt'), 'Ritim\n');
  touch(join(paths.storeMetadata, 'tr', 'release_notes.txt'), 'Yeni\n');
  touch(join(paths.storeMetadata, 'copyright.txt'), '2026 X\n');
  const { assets } = await collectRenderedAssets(paths, TARGETS, manifest);
  return { root, paths, manifest, assets };
}

// ---- Apple platforms -----------------------------------------------------------------------------

describe('Apple platforms', () => {
  it('maps platforms to App Store versions; watchOS belongs to the iOS version', () => {
    expect(appStorePlatformFor('watchos')).toBe('ios');
    expect(appStorePlatformFor('macos')).toBe('osx');
    expect(appStorePlatformFor('tvos')).toBe('appletvos');
    expect(appStorePlatformFor('visionos')).toBe('xros');
    expect(applePlatformsOf(['visionos', 'watchos', 'ios', 'macos'])).toEqual(['ios', 'osx', 'xros']);
  });

  it('routes rendered files by platform from the manifest', async () => {
    const f = await fixture();
    const r = routeAssets(f.assets);
    expect(r.apple.ios.map((a) => a.target.id).sort()).toEqual(['iphone-6.9', 'preview-iphone', 'watch-ultra']);
    expect(r.apple.osx.map((a) => a.target.id).sort()).toEqual(['mac-16x10', 'preview-mac']);
    expect(r.apple.appletvos.map((a) => a.target.id)).toEqual(['appletv-4k']);
    expect(r.apple.xros.map((a) => a.target.id)).toEqual(['vision-pro']);
    expect(r.appleCreatives.map((a) => a.target.id)).toEqual(['header']);
  });

  it('falls back to the folders when there is no manifest and reports unknown targets', async () => {
    const f = await fixture();
    touch(join(f.paths.screenshots, 'tr', '03_x_unknown-target.png'));
    const { assets, unknown } = await collectRenderedAssets(f.paths, TARGETS);
    expect(assets.filter((a) => a.kind === 'screenshot')).toHaveLength(5);
    expect(unknown.some((u) => u.endsWith('03_x_unknown-target.png'))).toBe(true);
  });

});

describe('multi-platform plan', () => {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const creds = { keyId: 'KEY1234567', issuerId: '69a6de7e-0000-0000-0000-000000000000', privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString() };
  const version = (id: string, v: string, state = 'PREPARE_FOR_SUBMISSION') => ({ data: [{ type: 'appStoreVersions', id, attributes: { versionString: v, appVersionState: state } }] });
  function ascFetch(): typeof fetch {
    const routes: Record<string, unknown> = {
      '/v1/apps?filter': { data: [{ type: 'apps', id: '1', attributes: { bundleId: 'com.x', name: 'X' } }] },
      '/v1/apps/1/appStoreVersions?filter[platform]=IOS': { data: [...version('v1', '1.2.0').data, { type: 'appStoreVersions', id: 'v0', attributes: { versionString: '1.1.0', appVersionState: 'READY_FOR_DISTRIBUTION' } }] },
      '/v1/apps/1/appStoreVersions?filter[platform]=MAC_OS': version('m1', '1.0.0'),
      '/v1/apps/1/appStoreVersions?filter[platform]=VISION_OS': { data: [] },
      '/v1/appStoreVersions/v1/appStoreVersionLocalizations': { data: [{ type: 'l', id: 'l1', attributes: { locale: 'tr', description: 'Yeni', keywords: 'a,b', whatsNew: 'Notlar' } }] },
      '/v1/appStoreVersions/m1/appStoreVersionLocalizations': { data: [{ type: 'l', id: 'l2', attributes: { locale: 'tr', description: 'Eski', keywords: 'a,b' } }] },
      '/v1/apps/1/appInfos': { data: [{ type: 'appInfos', id: 'i1', attributes: { state: 'PREPARE_FOR_SUBMISSION' } }] },
      '/v1/appInfos/i1/appInfoLocalizations': { data: [{ type: 'appInfoLocalizations', id: 'il1', attributes: { locale: 'tr', name: 'Ritim' } }] },
    };
    return (async (url: string) => {
      const path = decodeURIComponent(String(url).replace('https://api.appstoreconnect.apple.com', ''));
      const key = Object.keys(routes).find((k) => path.startsWith(k));
      return key ? new Response(JSON.stringify(routes[key]), { status: 200 }) : new Response(JSON.stringify({ errors: [{ detail: path }] }), { status: 404 });
    }) as typeof fetch;
  }

  let f: Fixture;
  beforeAll(async () => {
    f = await fixture();
  });
  const config = VitrinConfig.parse({ app: { locales: ['tr'] }, urls: {} });
  const meta = { locale: 'tr', name: 'Ritim', subtitle: '', promotionalText: '', description: 'Yeni', keywords: 'a,b', whatsNew: 'Notlar', claims: [] } as LocaleMetadata;

  it('plans every Apple platform version and the shared app info once', async () => {
    const client = new AscClient(creds, ascFetch());
    const plan = await buildPlan({
      paths: f.paths,
      config,
      bundleId: 'com.x',
      metadata: [meta],
      client,
      include: { creatives: false, cpp: false, events: false },
      platforms: ['ios', 'watchos', 'macos', 'visionos'],
      assets: f.assets,
    });
    expect(plan.platforms.map((p) => `${p.platform}:${p.version?.versionString ?? '-'}:${p.firstRelease}`)).toEqual(['ios:1.2.0:false', 'osx:1.0.0:true', 'xros:-:true']);
    expect(plan.version?.versionString).toBe('1.2.0');
    expect(plan.blockers).toEqual([expect.stringContaining('visionOS (VISION_OS)')]);
    const md = plan.items.filter((i) => i.area === 'metadata');
    expect(md.filter((i) => i.field === 'name')).toHaveLength(1);
    expect(md.find((i) => i.platform === 'ios' && i.field === 'description')?.change).toBe('unchanged');
    expect(md.find((i) => i.platform === 'osx' && i.field === 'description')?.change).toBe('update');
    // First Mac release: no What's New.
    expect(md.some((i) => i.platform === 'osx' && i.field === 'whatsNew')).toBe(false);
    const shots = plan.items.filter((i) => i.area === 'screenshots').map((i) => `${i.platform}/${i.field}`);
    expect(shots.sort()).toEqual(['ios/iphone-6.9', 'ios/watch-ultra', 'osx/mac-16x10', 'xros/vision-pro']);
    const previews = plan.items.filter((i) => i.area === 'previews');
    expect(previews.map((i) => `${i.platform}/${i.via}`).sort()).toEqual(['ios/asc-cli', 'osx/asc-cli']);
    // Each preview set is replaced on its own, the Mac's classic DESKTOP set included.
    expect(previews.find((i) => i.platform === 'osx')!.note).toMatch(/replaces only the DESKTOP preview set of tr; other display types stay untouched \(asc video-previews upload --replace\)/);
    const text = formatPlan(plan);
    expect(text).toContain('Version (macOS): 1.0.0 — PREPARE_FOR_SUBMISSION (first release)');
    expect(text).toContain('[metadata · macOS]');
    expect(text).toContain('“Eski” → “Yeni”');
  });

  it('reads back every platform', async () => {
    const client = new AscClient(creds, ascFetch());
    const diffs = await readBack({ paths: f.paths, config, bundleId: 'com.x', metadata: [meta], client, platforms: ['ios', 'macos'] });
    expect(diffs).toEqual([expect.stringMatching(/^osx tr description: ASC “Eski”/)]);
  });
  // ---- partial uploads (config.selection) ----

  const enabled = TARGETS.filter((t) => ['iphone-6.9', 'watch-ultra', 'mac-16x10', 'vision-pro', 'preview-iphone', 'preview-mac'].includes(t.id));
  const shipping = ['ios', 'watchos', 'macos', 'visionos'] as const;
  const scopeWith = (selection: VitrinConfig['selection']) => resolveScope({ shipping: [...shipping], selection, assets: f.assets, enabledTargets: enabled, locales: ['tr'] });

  it('replaces every selected set one display type at a time, for selected platforms only', () => {
    const all = scopeWith({});
    const ios = all.apple.find((s) => s.platform === 'ios')!;
    expect(ios).toMatchObject({ metadata: true, screenshots: 'per-display-type', previews: 'per-display-type', screenshotTargets: ['iphone-6.9', 'watch-ultra'] });

    // "I already uploaded iPhone screenshots; now only watchOS screenshots."
    const watch = scopeWith({ platforms: ['watchos'], assets: ['screenshots'] });
    const w = watch.apple.find((s) => s.platform === 'ios')!;
    expect(w).toMatchObject({ metadata: false, screenshots: 'per-display-type', previews: 'skip', screenshotTargets: ['watch-ultra'] });
    expect(w.untouched.join('\n')).toMatch(/ios not selected[\s\S]*text metadata not selected[\s\S]*only watch-ultra replaced; iphone-6.9/);
    expect(watch.apple.find((s) => s.platform === 'osx')!.untouched[0]).toMatch(/macos not selected/);

    // A locale missing one enabled target: the other sets stay as they are.
    const noIphone = resolveScope({ shipping: ['ios', 'watchos'], selection: {}, assets: f.assets.filter((a) => a.target.id !== 'iphone-6.9'), enabledTargets: enabled, locales: ['tr'] });
    expect(noIphone.apple[0]).toMatchObject({ screenshots: 'per-display-type', screenshotTargets: ['watch-ultra'] });
    expect(noIphone.apple[0]!.untouched.join('\n')).toMatch(/only watch-ultra replaced; iphone-6.9 and every other display type stay untouched/);
    // "Only update the App Preview."
    const prev = scopeWith({ platforms: ['ios'], assets: ['previews'] }).apple[0]!;
    expect(prev).toMatchObject({ metadata: false, screenshots: 'skip', previews: 'per-display-type', previewTargets: ['preview-iphone'] });
  });

  it('replaces only the chosen formats (selection.targets) and never overwrites the rest', () => {
    const ios = scopeWith({ platforms: ['ios', 'watchos'], targets: ['watch-ultra'] }).apple.find((s) => s.platform === 'ios')!;
    expect(ios).toMatchObject({ screenshots: 'per-display-type', screenshotTargets: ['watch-ultra'] });
    expect(ios.untouched.join('\n')).toMatch(/only watch-ultra replaced; iphone-6.9/);
  });

  it('plans a watch-only run without touching text, iPhone or other platforms', async () => {
    const asked: string[] = [];
    const inner = ascFetch();
    const client = new AscClient(creds, (async (url: string, init?: RequestInit) => {
      asked.push(decodeURIComponent(String(url)));
      return inner(url, init);
    }) as typeof fetch);
    const cfg = VitrinConfig.parse({ app: { locales: ['tr'] }, urls: {}, selection: { platforms: ['watchos'], assets: ['screenshots'] } });
    const plan = await buildPlan({ paths: f.paths, config: cfg, bundleId: 'com.x', metadata: [meta], client, include: { creatives: true, cpp: false, events: false }, platforms: [...shipping], assets: f.assets, enabledTargets: enabled });
    // Only the iOS version is read; the untouched Mac and Vision versions cannot block this run.
    expect(asked.some((u) => u.includes('MAC_OS') || u.includes('VISION_OS'))).toBe(false);
    expect(plan.blockers).toEqual([]);
    expect(plan.items.filter((i) => i.area === 'metadata')).toEqual([]);
    const shots = plan.items.filter((i) => i.area === 'screenshots');
    expect(shots).toHaveLength(1);
    expect(shots[0]).toMatchObject({ platform: 'ios', field: 'watch-ultra', via: 'asc-cli' });
    expect(shots[0]!.note).toMatch(/replaces only the APP_WATCH_ULTRA screenshot set of tr; other display types stay untouched \(asc screenshots upload --replace\)/);
    expect(plan.items.find((i) => i.area === 'creatives')?.note).toMatch(/creatives not selected/);
    const text = formatPlan(plan);
    expect(text).toContain('[untouched · iOS]');
    expect(text).toContain('[untouched · macOS]');
    expect(text).toMatch(/iphone-6.9 and every other display type stay untouched/);
    expect(text).not.toContain('replaces EVERY');
  });

  it('plans text and every display type through asc, also for an old `uploader: deliver` config', async () => {
    const cfg = VitrinConfig.parse({ app: { locales: ['tr'] }, urls: {}, upload: { uploader: 'deliver' } });
    const plan = await buildPlan({ paths: f.paths, config: cfg, bundleId: 'com.x', metadata: [meta], include: { creatives: false, cpp: false, events: false }, platforms: ['ios', 'watchos'], assets: f.assets, enabledTargets: enabled });
    expect(plan.uploader).toBe('asc');
    expect(plan.scope!.apple[0]).toMatchObject({ screenshots: 'per-display-type', previews: 'per-display-type' });
    const media = plan.items.filter((i) => i.area === 'screenshots' || i.area === 'previews');
    expect(media.map((i) => `${i.field}:${i.via}`).sort()).toEqual(['iphone-6.9:asc-cli', 'preview-iphone:asc-cli', 'watch-ultra:asc-cli']);
    expect(media.find((i) => i.field === 'iphone-6.9')!.note).toMatch(/replaces only the APP_IPHONE_67 screenshot set of tr; .*asc screenshots upload --replace/);
    expect(plan.items.filter((i) => i.area === 'metadata').every((i) => i.via === 'asc-cli')).toBe(true);
    expect(plan.items.some((i) => /does not upload categories, copyright or review information/.test(i.note ?? ''))).toBe(true);
    expect(formatPlan(plan)).not.toContain('replaces EVERY');
  });
});
