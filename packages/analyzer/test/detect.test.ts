import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  analyzeProject,
  detectDuo,
  detectFramework,
  normalizeLocale,
  readPbxproj,
  splitFlutterVersion,
  targetPlatforms,
  xcodeVersionOf,
} from '../src/index.js';

const FIXTURES = join(fileURLToPath(new URL('.', import.meta.url)), 'fixtures');
const RITIM = join(fileURLToPath(new URL('.', import.meta.url)), '..', '..', '..', 'examples', 'Ritim');
const analyze = (name: string) => analyzeProject({ root: join(FIXTURES, name) });
const ids = (p: { features: Array<{ id: string }> }) => p.features.map((f) => f.id);

describe('Xcode platform detection', () => {
  it('maps SDKROOT, SUPPORTED_PLATFORMS and device families to platforms', () => {
    expect(targetPlatforms({ SDKROOT: 'iphoneos', TARGETED_DEVICE_FAMILY: '1,2' }).platforms).toEqual(['ios']);
    expect(targetPlatforms({ SDKROOT: 'macosx' }).platforms).toEqual(['macos']);
    expect(targetPlatforms({ SDKROOT: 'watchos', TARGETED_DEVICE_FAMILY: '4' }).platforms).toEqual(['watchos']);
    expect(targetPlatforms({ SDKROOT: 'appletvos' }).platforms).toEqual(['tvos']);
    expect(targetPlatforms({ SDKROOT: 'xros' }).platforms).toEqual(['visionos']);
    expect(targetPlatforms({ SDKROOT: 'auto', SUPPORTED_PLATFORMS: 'iphoneos iphonesimulator macosx xros xrsimulator' }).platforms).toEqual(['ios', 'macos', 'visionos']);
    expect(targetPlatforms({}).platforms).toEqual(['ios']); // Xcode's default SDK
  });

  it('counts Mac Catalyst as macOS but not "Designed for iPad"', () => {
    const catalyst = targetPlatforms({ SDKROOT: 'iphoneos', TARGETED_DEVICE_FAMILY: '1,2,6', SUPPORTS_MACCATALYST: 'YES' });
    expect(catalyst).toEqual({ platforms: ['ios', 'macos'], macCatalyst: true });
    const designedForIPad = targetPlatforms({ SDKROOT: 'iphoneos', TARGETED_DEVICE_FAMILY: '1,2', SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: 'YES', SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: 'YES' });
    expect(designedForIPad).toEqual({ platforms: ['ios'], macCatalyst: false });
    expect(targetPlatforms({ SDKROOT: 'iphoneos', TARGETED_DEVICE_FAMILY: '1,2,7' }).platforms).toEqual(['ios', 'visionos']);
  });

  it('ignores the watch container stub and counts legacy WatchKit apps', () => {
    expect(targetPlatforms({ SDKROOT: 'iphoneos' }, 'com.apple.product-type.application.watchapp2-container').platforms).toEqual([]);
    expect(targetPlatforms({ SDKROOT: 'watchos' }, 'com.apple.product-type.application.watchapp2').platforms).toEqual(['watchos']);
  });

  it('reads the Xcode version from LastUpgradeCheck', () => {
    expect(xcodeVersionOf('2710')).toBe(27.1);
    expect(xcodeVersionOf('1430')).toBe(14.3);
    expect(xcodeVersionOf('2600')).toBe(26);
    expect(xcodeVersionOf(undefined)).toBeUndefined();
    const pbx = readPbxproj('{ objects = { P = { isa = PBXProject; attributes = { LastUpgradeCheck = 2710; BuildIndependentTargetsInParallel = 1; }; targets = (); }; }; rootObject = P; }');
    expect(pbx.attributes.LastUpgradeCheck).toBe('2710');
  });

  it('iPhone Duo heuristic: Xcode 27.1+ or an iOS 27.1 deployment target, iPhone only', () => {
    const base = { supportsIPhone: true, pbxprojPath: 'A.xcodeproj/project.pbxproj' };
    expect(detectDuo({ ...base, attributes: { LastUpgradeCheck: '2710' } }).supported).toBe(true);
    expect(detectDuo({ ...base, attributes: { LastSwiftUpdateCheck: '2800' } }).supported).toBe(true);
    expect(detectDuo({ ...base, attributes: { LastUpgradeCheck: '2700' } }).supported).toBe(false);
    expect(detectDuo({ ...base, attributes: {}, deploymentTarget: '27.1' }).supported).toBe(true);
    expect(detectDuo({ ...base, attributes: { LastUpgradeCheck: '2710' }, supportsIPhone: false }).supported).toBe(false);
    expect(detectDuo({ ...base, attributes: { LastUpgradeCheck: '2710' } }).evidence).toMatchObject({ path: base.pbxprojPath, note: expect.stringContaining('LastUpgradeCheck=2710') });
  });
});

describe('framework file readers', () => {
  it('normalises locale spellings', () => {
    expect(normalizeLocale('pt_BR')).toBe('pt-BR');
    expect(normalizeLocale('zh_Hans')).toBe('zh-Hans');
    expect(normalizeLocale('night')).toBeUndefined();
  });

  it('splits Flutter versions', () => {
    expect(splitFlutterVersion('2.3.1+45')).toEqual({ name: '2.3.1', build: '45' });
    expect(splitFlutterVersion('1.0.0')).toEqual({ name: '1.0.0', build: undefined });
  });

  it('detects each project kind', async () => {
    expect((await detectFramework(join(FIXTURES, 'flutter'))).kind).toBe('flutter');
    expect((await detectFramework(join(FIXTURES, 'react-native'))).kind).toBe('react-native');
    expect((await detectFramework(join(FIXTURES, 'expo'))).kind).toBe('expo');
    expect((await detectFramework(join(FIXTURES, 'mac'))).kind).toBe('native');
  });
});

describe('analyzeProject per project kind', () => {
  it('Flutter: Runner host, pubspec version, ARB locales, macOS; its android/ folder is ignored', async () => {
    const p = await analyze('flutter');
    expect(p.project).toMatchObject({ kind: 'flutter', iosDir: 'ios', macosDir: 'macos', xcodeproj: 'ios/Runner.xcodeproj', scheme: 'Runner' });
    expect(p.app).toMatchObject({ displayName: 'Habit Flow', bundleId: 'com.example.habitflow', version: '2.3.1', build: '45', supportsIPhone: true, supportsIPad: true, supportsDuo: false });
    expect(p.app.platforms).toEqual(['ios', 'macos']);
    expect(p.app.locales.map((l) => l.xcode)).toEqual(['en', 'pt-BR', 'tr']);
    expect(ids(p)).toEqual(expect.arrayContaining(['ipad', 'mac-app', 'charts', 'localization']));
    expect(p.signals['vitrin.demo-mode']).toBeDefined();
  });

  it('React Native: workspace; its android/ folder and Pods are ignored', async () => {
    const p = await analyze('react-native');
    expect(p.project).toMatchObject({ kind: 'react-native', xcodeproj: 'ios/Pocket.xcodeproj', workspace: 'ios/Pocket.xcworkspace', scheme: 'Pocket' });
    expect(p.project.targets.map((t) => t.name)).toEqual(['Pocket']);
    expect(p.app).toMatchObject({ displayName: 'Pocket Budget', version: '1.4.0', build: '7', supportsIPad: false });
    expect(p.app.platforms).toEqual(['ios']);
    expect(p.app.locales.map((l) => l.xcode)).toEqual(['de', 'en']);
    expect(p.signals['vitrin.demo-mode']?.[0]?.path).toBe('App.tsx');
  });

  it('Expo without native folders: app.json identity, prebuild needed', async () => {
    const p = await analyze('expo');
    expect(p.project).toMatchObject({ kind: 'expo', needsPrebuild: true, iosDir: 'ios' });
    expect(p.project.xcodeproj).toBeUndefined();
    expect(p.app).toMatchObject({ displayName: 'Trail Notes', bundleId: 'com.trailnotes.app', version: '3.0.0', build: '12', supportsIPhone: true, supportsIPad: true });
    expect(p.app.platforms).toEqual(['ios']);
    expect(p.app.locales.map((l) => l.xcode)).toEqual(['en', 'tr']);
    expect(p.todo.some((t) => t.includes('expo prebuild'))).toBe(true);
    expect(p.features.find((f) => f.id === 'ipad')!.evidence[0]!.path).toBe('app.json');
  });

  it('a native Android project gets a clear message: Apple platforms only', async () => {
    await expect(analyze('android')).rejects.toThrow(/This is an Android project.*Vitrin supports Apple platforms only/);
  });

  it('a Flutter project without an iOS host gets the same message', async () => {
    const root = mkdtempSync(join(tmpdir(), 'vitrin-flutter-'));
    writeFileSync(join(root, 'pubspec.yaml'), 'name: a\ndependencies:\n  flutter:\n    sdk: flutter\n');
    await expect(analyzeProject({ root })).rejects.toThrow(/flutter project has no iOS or macOS host project.*Apple platforms only/);
  });

  it('macOS-only app is not an iPhone app', async () => {
    const p = await analyze('mac');
    expect(p.app.platforms).toEqual(['macos']);
    expect(p.app.supportsIPhone).toBe(false);
    expect(p.project.targets[0]!.devices).toContain('mac');
    expect(ids(p)).toContain('mac-app');
  });

  it('watchOS: single-target watch app next to the iOS app', async () => {
    const p = await analyze('watch');
    expect(p.app.platforms).toEqual(['ios', 'watchos']);
    expect(p.project.scheme).toBe('Pulse');
    expect(p.project.targets.find((t) => t.name === 'Pulse Watch App')).toMatchObject({ kind: 'watch', platforms: ['watchos'], bundleId: 'com.example.pulse.watchkitapp' });
    expect(ids(p)).toContain('apple-watch');
  });

  it('tvOS and visionOS', async () => {
    const tv = await analyze('tv');
    expect(tv.app.platforms).toEqual(['tvos']);
    expect(tv.app.supportsIPhone).toBe(false);
    expect(ids(tv)).toContain('apple-tv');
    const vision = await analyze('vision');
    expect(vision.app.platforms).toEqual(['ios', 'visionos']); // "Designed for iPad" on Mac does not add macOS
    expect(ids(vision)).toContain('vision-pro');
  });

  it('iPhone Duo from Xcode 27.1, with evidence', async () => {
    const p = await analyze('duo');
    expect(p.app.supportsDuo).toBe(true);
    expect(p.features.find((f) => f.id === 'iphone-duo')).toMatchObject({ kind: 'platform', confidence: 'medium' });
  });

  it('native Swift example keeps its previous profile', async () => {
    const p = await analyzeProject({ root: RITIM });
    expect(p.project).toMatchObject({ kind: 'native', iosDir: '.', xcodeproj: 'Ritim.xcodeproj', scheme: 'Ritim' });
    expect(p.app).toMatchObject({ displayName: 'Ritim', bundleId: 'com.jastech.ritim', version: '1.2.0', supportsIPhone: true, supportsIPad: true, platforms: ['ios'] });
    expect(p.app.locales.map((l) => l.asc)).toEqual(['en-US', 'tr']);
    expect(p.signals['vitrin.demo-mode']).toBeDefined();
  });

  it('fails clearly when there is no app at all', async () => {
    await expect(analyzeProject({ root: join(FIXTURES, 'flutter', 'lib') })).rejects.toThrow(/No Xcode project found/);
  });
});
