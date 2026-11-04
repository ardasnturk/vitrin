import type { ExecOptions, ExecResult } from '@vitrin/core';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { parse as parseYaml } from 'yaml';
import { appIdentity, artifactDir, buildApp, compileSteps, effectiveConfiguration, prepareSteps, xcodeDestination, type BuildInput, type Runner } from '../src/build.js';
import { captureKinds, familiesToCapture, requiredTools } from '../src/commands/pipeline.js';
import { applySelection, parseChoice, platformsReport, sampleLocale, uploaderReport } from '../src/commands/select.js';
import type { Ctx } from '../src/context.js';
import { ensureSimulator, macLaunchArgs, pickMainWindow, pickRuntime, runtimeMatches, screencaptureArgs, screenRecordArgs, statusBarArgs, type SimList } from '../src/simulator.js';
import { configWith, profileWith } from './helpers.js';

/** Records every command and answers from a table (first matching prefix wins). */
function mockRunner(answers: Array<[string, Partial<ExecResult>]> = []) {
  const calls: Array<{ cmd: string; args: string[]; opts?: ExecOptions }> = [];
  const runner: Runner = async (cmd, args, opts) => {
    calls.push({ cmd, args, opts });
    const line = [cmd, ...args].join(' ');
    const hit = answers.find(([prefix]) => line.startsWith(prefix) || line.includes(prefix));
    return { code: 0, stdout: '', stderr: '', ...(hit?.[1] ?? {}) };
  };
  return { runner, calls, lines: () => calls.map((c) => [c.cmd, ...c.args].join(' ')) };
}

const base: BuildInput = { root: '/app', kind: 'native', platform: 'ios', iosDir: '.', xcodeproj: 'App.xcodeproj', scheme: 'App', configuration: 'Debug', derivedData: '/app/metadata/.cache/DerivedData' };
const never = () => false;
const always = () => true;

describe('build commands per kind and platform', () => {
  it('native iOS: xcodebuild for the simulator without signing', () => {
    expect(prepareSteps(base, never)).toEqual([]);
    const [step] = compileSteps(base);
    expect(step!.cmd).toBe('xcodebuild');
    expect(step!.args).toEqual(['-project', '/app/App.xcodeproj', '-scheme', 'App', '-configuration', 'Debug', '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', base.derivedData, 'build', 'CODE_SIGNING_ALLOWED=NO', 'COMPILER_INDEX_STORE_ENABLE=NO']);
    expect(artifactDir(base)).toEqual({ dir: '/app/metadata/.cache/DerivedData/Build/Products/Debug-iphonesimulator', ext: '.app', preferred: 'App.app' });
  });

  it('simulator SDKs and macOS variants', () => {
    expect(xcodeDestination('watchos').destination).toBe('generic/platform=watchOS Simulator');
    expect(xcodeDestination('tvos').products('Debug')).toBe('Debug-appletvsimulator');
    expect(xcodeDestination('visionos').products('Debug')).toBe('Debug-xrsimulator');
    expect(xcodeDestination('macos')).toMatchObject({ destination: 'platform=macOS' });
    expect(xcodeDestination('macos', true).destination).toBe('platform=macOS,variant=Mac Catalyst');
    expect(xcodeDestination('macos', true).products('Debug')).toBe('Debug-maccatalyst');
    const mac = compileSteps({ ...base, platform: 'macos' })[0]!;
    expect(mac.args).toContain('CODE_SIGN_IDENTITY=-'); // ad-hoc: unsigned Mac apps do not launch on Apple silicon
    expect(mac.args).not.toContain('CODE_SIGNING_ALLOWED=NO');
    expect(compileSteps({ ...base, platform: 'watchos', scheme: 'App Watch App' })[0]!.args).toContain('App Watch App');
  });

  it('Flutter: flutter build for iOS simulator and macOS', () => {
    const f = { ...base, kind: 'flutter' as const, iosDir: 'ios', xcodeproj: 'ios/Runner.xcodeproj', scheme: 'Runner' };
    expect(compileSteps(f)[0]).toMatchObject({ cmd: 'flutter', args: ['build', 'ios', '--simulator', '--debug'], cwd: '/app' });
    expect(artifactDir(f)).toMatchObject({ dir: '/app/build/ios/iphonesimulator', preferred: 'Runner.app' });
    expect(compileSteps({ ...f, platform: 'macos' })[0]!.args).toEqual(['build', 'macos', '--debug']);
    expect(() => compileSteps({ ...f, platform: 'watchos' })).toThrow(/Flutter does not build for watchos/);
  });

  it('React Native: pod install, then xcodebuild on the workspace (Release)', () => {
    const rn = { ...base, kind: 'react-native' as const, iosDir: 'ios', workspace: 'ios/Pocket.xcworkspace', scheme: 'Pocket' };
    expect(prepareSteps(rn, (p) => p === '/app/Gemfile')).toEqual([expect.objectContaining({ cmd: 'bundle', args: ['exec', 'pod', 'install'], cwd: '/app/ios' })]);
    expect(prepareSteps(rn, never)[0]).toMatchObject({ cmd: 'pod', args: ['install'] });
    expect(prepareSteps({ ...rn, podInstall: false }, never)).toEqual([]);
    const xb = compileSteps(rn)[0]!;
    expect(xb.args.slice(0, 6)).toEqual(['-workspace', '/app/ios/Pocket.xcworkspace', '-scheme', 'Pocket', '-configuration', 'Release']);
    expect(xb.env).toEqual({ RCT_NO_LAUNCH_PACKAGER: '1' });
    // Metro mode: Debug.
    expect(effectiveConfiguration({ ...rn, metro: true })).toBe('Debug');
  });

  it('Expo: prebuild only when the native folder is missing', () => {
    const expo = { ...base, kind: 'expo' as const, iosDir: 'ios', xcodeproj: undefined, scheme: undefined };
    const ios = prepareSteps(expo, never);
    expect(ios.map((s) => s.label)).toEqual(['npx expo prebuild (ios)', 'pod install']);
    expect(ios[0]).toMatchObject({ cmd: 'npx', args: ['expo', 'prebuild', '--platform', 'ios', '--no-install'], cwd: '/app', env: { CI: '1', EXPO_NO_GIT_STATUS: '1' } });
    expect(prepareSteps(expo, always).map((s) => s.label)).toEqual(['pod install']);
    expect(() => prepareSteps({ ...expo, prebuild: false }, never)).toThrow(/prebuild is false/);
  });

  it('buildApp runs prepare + compile, resolves the Expo workspace after prebuild and returns the artifact', async () => {
    const root = mkdtempSync(join(tmpdir(), 'vitrin-build-'));
    const derived = join(root, 'dd');
    const { runner, lines } = mockRunner();
    // Simulate what prebuild + pod install + xcodebuild leave behind.
    mkdirSync(join(root, 'ios', 'TrailNotes.xcworkspace'), { recursive: true });
    mkdirSync(join(derived, 'Build', 'Products', 'Release-iphonesimulator', 'TrailNotes.app'), { recursive: true });
    const app = await buildApp({ root, kind: 'expo', platform: 'ios', iosDir: 'ios', configuration: 'Debug', derivedData: derived }, runner);
    expect(app).toBe(join(derived, 'Build', 'Products', 'Release-iphonesimulator', 'TrailNotes.app'));
    expect(lines()[0]).toBe('pod install'); // ios/ exists, so no prebuild
    expect(lines()[1]).toContain(`-workspace ${join(root, 'ios', 'TrailNotes.xcworkspace')} -scheme TrailNotes -configuration Release`);
  });

  it('buildApp surfaces build errors', async () => {
    const { runner } = mockRunner([['xcodebuild', { code: 65, stdout: 'x\n/app/A.swift:1: error: cannot find type\n' }]]);
    await expect(buildApp(base, runner)).rejects.toThrow(/cannot find type/);
  });

  it('picks the bundle id and scheme per platform', () => {
    const p = profileWith(
      { bundleId: 'com.a.app', platforms: ['ios', 'watchos', 'macos'] },
      {
        scheme: 'App',
        targets: [
          { name: 'App', kind: 'app', bundleId: 'com.a.app', devices: ['iphone', 'mac'], platforms: ['ios', 'macos'], macCatalyst: true },
          { name: 'App Watch App', kind: 'watch', bundleId: 'com.a.app.watchkitapp', devices: ['watch'], platforms: ['watchos'], macCatalyst: false },
        ],
      },
    );
    expect(appIdentity(p, 'ios')).toMatchObject({ appId: 'com.a.app', scheme: 'App' });
    expect(appIdentity(p, 'watchos')).toMatchObject({ appId: 'com.a.app.watchkitapp', scheme: 'App Watch App' });
    expect(appIdentity(p, 'macos')).toMatchObject({ appId: 'com.a.app', scheme: 'App', macCatalyst: true });
  });
});

describe('simulators per platform', () => {
  const list: SimList = {
    devices: {},
    devicetypes: [
      { name: 'Apple Watch Ultra 3 (49mm)', identifier: 'watch-ultra-3' },
      { name: 'Apple Vision Pro', identifier: 'vision-pro' },
      { name: 'iPhone 17 Pro', identifier: 'iphone-17-pro' },
    ],
    runtimes: [
      { identifier: 'com.apple.CoreSimulator.SimRuntime.iOS-27-1', name: 'iOS 27.1', version: '27.1', isAvailable: true, platform: 'iOS' },
      { identifier: 'com.apple.CoreSimulator.SimRuntime.watchOS-12-0', name: 'watchOS 12.0', version: '12.0', isAvailable: true, platform: 'watchOS' },
      { identifier: 'com.apple.CoreSimulator.SimRuntime.watchOS-11-0', name: 'watchOS 11.0', version: '11.0', isAvailable: true },
      { identifier: 'com.apple.CoreSimulator.SimRuntime.xrOS-3-0', name: 'visionOS 3.0', version: '3.0', isAvailable: true, platform: 'xrOS' },
      { identifier: 'com.apple.CoreSimulator.SimRuntime.tvOS-27-0', name: 'tvOS 27.0', version: '27.0', isAvailable: false },
    ],
  };

  it('filters runtimes by platform (not /iOS/ for everything)', () => {
    expect(runtimeMatches(list.runtimes[0]!, 'ios')).toBe(true);
    expect(runtimeMatches(list.runtimes[1]!, 'ios')).toBe(false);
    expect(runtimeMatches(list.runtimes[3]!, 'ios')).toBe(false);
    expect(runtimeMatches(list.runtimes[3]!, 'visionos')).toBe(true);
    expect(runtimeMatches(list.runtimes[2]!, 'watchos')).toBe(true); // no platform field: name/identifier
    expect(pickRuntime(list, 'Apple Watch Ultra 3 (49mm)', 'watchos').runtime.name).toBe('watchOS 12.0');
    expect(pickRuntime(list, 'Apple Vision Pro', 'visionos').runtime.name).toBe('visionOS 3.0');
    expect(() => pickRuntime(list, 'Apple Vision Pro', 'tvos')).toThrow(/No suitable tvOS runtime/);
    expect(() => pickRuntime(list, 'Apple TV 4K (3rd generation)', 'tvos')).toThrow(/device type not found/);
  });

  it('creates a dedicated simulator on the right runtime', async () => {
    const { runner, lines } = mockRunner([
      ['xcrun simctl list -j', { stdout: JSON.stringify(list) }],
      ['xcrun simctl create', { stdout: 'UDID-1\n' }],
    ]);
    const sim = await ensureSimulator('Apple Watch Ultra 3 (49mm)', 'watchos', runner);
    expect(sim).toEqual({ udid: 'UDID-1', name: 'Vitrin · Apple Watch Ultra 3 (49mm)', runtime: 'watchOS 12.0' });
    expect(lines()[1]).toBe('xcrun simctl create Vitrin · Apple Watch Ultra 3 (49mm) watch-ultra-3 com.apple.CoreSimulator.SimRuntime.watchOS-12-0');
  });

  it('status bar overrides per platform', () => {
    expect(statusBarArgs('U', 'ios')).toEqual(expect.arrayContaining(['--time', '9:41', '--batteryLevel', '100', '--cellularBars', '4']));
    expect(statusBarArgs('U', 'watchos')).toEqual(['simctl', 'status_bar', 'U', 'override', '--time', '9:41']);
    expect(statusBarArgs('U', 'tvos')).toBeUndefined();
    expect(statusBarArgs('U', 'visionos')).toBeUndefined();
  });
});

describe('Mac capture', () => {
  it('builds launch arguments, window capture and recording commands', () => {
    expect(macLaunchArgs(['-VitrinDemo', '-VitrinScreen', 'home'], 'tr', 'tr', 'dark')).toEqual(['-VitrinDemo', '-VitrinScreen', 'home', '-AppleLanguages', '(tr)', '-AppleLocale', 'tr_TR', '-AppleInterfaceStyle', 'Dark']);
    expect(macLaunchArgs([], 'en-US', 'us', 'light')).toEqual(['-AppleLanguages', '(en-US)', '-AppleLocale', 'en_US']);
    expect(screencaptureArgs(4711, '/o.png')).toEqual(['-l', '4711', '-o', '-x', '-t', 'png', '/o.png']);
    expect(screenRecordArgs({ x: 40, y: 60.4, w: 1440, h: 900 }, 12, '/o.mov')).toEqual(['-v', '-V', '12', '-x', '-R40,60,1440,900', '/o.mov']);
    expect(pickMainWindow([{ id: 1, x: 0, y: 0, w: 300, h: 200, title: 'panel' }, { id: 2, x: 0, y: 0, w: 1440, h: 900, title: 'main' }, { id: 0, x: 0, y: 0, w: 4000, h: 4000, title: '' }])?.id).toBe(2);
  });
});

describe('capture planning', () => {
  const ctxWith = (extra: Record<string, unknown> = {}) => ({ config: configWith(extra) }) as unknown as Ctx;
  const everything = profileWith({ platforms: ['ios', 'macos', 'watchos', 'tvos', 'visionos'], supportsIPhone: true, supportsIPad: true, supportsDuo: true });

  it('captures one family per enabled platform/device', () => {
    const fams = familiesToCapture(ctxWith(), everything);
    expect(fams.map((f) => `${f.family}:${f.platform}:${f.device}`)).toEqual([
      'iphone:ios:iPhone 17 Pro',
      'ipad:ios:iPad Pro 13-inch (M5)',
      'mac:macos:Mac',
      'watch:watchos:Apple Watch Ultra 3 (49mm)',
      'tv:tvos:Apple TV 4K (3rd generation)',
      'vision:visionos:Apple Vision Pro',
    ]);
  });

  it('uses configured simulators; Duo stays opt-in', () => {
    const fams = familiesToCapture(ctxWith({ capture: { simulators: { watch: 'Apple Watch Series 11 (46mm)', duo: 'iPhone Duo' } } }), everything);
    expect(fams.find((f) => f.family === 'watch')!.device).toBe('Apple Watch Series 11 (46mm)');
    expect(fams.find((f) => f.family === 'duo')).toBeDefined();
  });

  it('only captures the selected platforms', () => {
    const fams = familiesToCapture(ctxWith({ selection: { platforms: ['watchos'] } }), everything);
    expect(fams.map((f) => f.family)).toEqual(['watch']);
  });

  it('previews only → recordings only, for families with an App Preview class', () => {
    expect(captureKinds(configWith({ selection: { assets: ['previews'] } }))).toEqual({ screens: false, recordings: true });
    expect(captureKinds(configWith({ selection: { assets: ['screenshots'] } }))).toEqual({ screens: true, recordings: false });
    expect(captureKinds(configWith({ selection: { assets: ['metadata'] } }))).toEqual({ screens: false, recordings: false });
    expect(captureKinds(configWith())).toEqual({ screens: true, recordings: true });
    const fams = familiesToCapture(ctxWith({ selection: { platforms: ['ios', 'watchos', 'macos'], assets: ['previews'] } }), everything);
    expect(fams.map((f) => f.family)).toEqual(['iphone', 'ipad', 'mac']); // no watch preview class
    expect(familiesToCapture(ctxWith({ selection: { assets: ['metadata'] } }), everything)).toEqual([]);
  });

  it('tools per platform', () => {
    expect(requiredTools(['ios'])).toEqual(['xcrun']);
    expect(requiredTools(['macos'])).toEqual(['xcrun', 'screencapture']);
  });
});

describe('vitrin platforms / select', () => {
  const profile = profileWith({
    platforms: ['ios', 'watchos'],
    supportsIPhone: true,
    platformEvidence: { ios: [{ path: 'A.xcodeproj/project.pbxproj', note: 'A: SDKROOT=iphoneos' }], watchos: [{ path: 'A.xcodeproj/project.pbxproj' }] },
  });

  it('reports detected platforms first, with evidence and target counts', () => {
    const r = platformsReport(configWith({ selection: { platforms: ['watchos'] } }), profile);
    expect(r.platforms.map((p) => p.platform)).toEqual(['ios', 'watchos', 'macos', 'tvos', 'visionos']);
    const ios = r.platforms[0]!;
    expect(ios).toMatchObject({ detected: true, selected: false, label: 'iPhone & iPad (App Store)' });
    expect(ios.evidence[0]!.note).toBe('A: SDKROOT=iphoneos');
    expect(ios.targets.screenshots).toEqual(['iphone-6.3', 'iphone-6.9']);
    expect(ios.targets.previews).toEqual(['preview-iphone']);
    expect(r.platforms[1]).toMatchObject({ platform: 'watchos', selected: true, targets: { screenshots: ['watch-ultra'] } });
    expect(r.platforms.find((p) => p.platform === 'tvos')).toMatchObject({ detected: false, selected: false });
    expect(r.assets.every((a) => a.selected)).toBe(true);
  });

  it('validates choices', () => {
    expect(parseChoice('ios, watchos,ios', ['ios', 'watchos'] as const, 'platform')).toEqual(['ios', 'watchos']);
    expect(parseChoice('all', ['ios'] as const, 'platform')).toBeNull();
    expect(parseChoice(undefined, ['ios'] as const, 'platform')).toBeUndefined();
    expect(() => parseChoice('ios,windows', ['ios', 'macos'] as const, 'platform')).toThrow(/Unknown platform: windows/);
  });

  it('writes selection into vitrin.config.yaml, keeping comments and other keys', () => {
    const before = '# Vitrin configuration\napp:\n  bundleId: com.a # the app\nurls: {}\n';
    const after = applySelection(before, { platforms: ['ios', 'watchos'], assets: ['screenshots', 'previews'] });
    expect(after).toContain('# Vitrin configuration');
    expect(after).toContain('bundleId: com.a # the app');
    expect(parseYaml(after).selection).toEqual({ platforms: ['ios', 'watchos'], assets: ['screenshots', 'previews'] });
    const assetsOnly = applySelection(after, { assets: ['metadata'] });
    expect(parseYaml(assetsOnly).selection).toEqual({ platforms: ['ios', 'watchos'], assets: ['metadata'] });
    const cleared = applySelection(applySelection(after, { platforms: null }), { assets: null });
    expect(parseYaml(cleared).selection).toBeUndefined();
    expect(configWith(parseYaml(after)).selection.platforms).toEqual(['ios', 'watchos']);
  });

  it('select command writes the file', async () => {
    const { selectCommand } = await import('../src/commands/select.js');
    const dir = mkdtempSync(join(tmpdir(), 'vitrin-select-'));
    const file = join(dir, 'vitrin.config.yaml');
    writeFileSync(file, '# keep me\napp:\n  bundleId: com.a\nurls: {}\n');
    const ctx = { root: dir, paths: { config: file, profile: join(dir, 'metadata', 'app_profile.json') }, config: configWith() } as unknown as Ctx;
    await selectCommand(ctx, { platforms: 'ios,macos', assets: 'screenshots' });
    const { readFileSync } = await import('node:fs');
    const text = readFileSync(file, 'utf8');
    expect(text).toContain('# keep me');
    expect(parseYaml(text).selection).toEqual({ platforms: ['ios', 'macos'], assets: ['screenshots'] });
    expect(ctx.config.selection.platforms).toEqual(['ios', 'macos']);
    await expect(selectCommand(ctx, {})).rejects.toThrow(/Nothing to select/);
    // The removed uploader choice: `--uploader` alone changes nothing and does not fail (older callers).
    expect(await selectCommand(ctx, { uploader: 'deliver' })).toBe(0);
    expect(parseYaml(readFileSync(file, 'utf8')).upload).toBeUndefined();
  });

  it('stores formats, store locales and the conversation language, and drops a removed uploader', () => {
    const before = '# keep\napp:\n  primaryLocale: tr\n  locales: [tr, en-US, de-DE]\nurls: {}\nupload:\n  platform: ios\n  uploader: deliver\n';
    const after = parseYaml(applySelection(before, { targets: ['iphone-6.9'], locales: ['en-US', 'tr'], language: 'tr' }));
    expect(after.selection).toEqual({ targets: ['iphone-6.9'] });
    expect(after.app).toEqual({ primaryLocale: 'tr', locales: ['en-US', 'tr'] });
    expect(after.ui).toEqual({ language: 'tr' });
    expect(after.upload).toEqual({ platform: 'ios' });
    const reset = parseYaml(applySelection(applySelection(before, { language: 'tr' }), { language: null, targets: null }));
    expect(reset.ui).toBeUndefined();
    expect(reset.selection).toBeUndefined();
  });

  it('samples one locale (English first) and the main iPhone format', () => {
    expect(sampleLocale(configWith({ app: { primaryLocale: 'tr', locales: ['tr', 'de-DE', 'en-GB'] } }))).toBe('en-GB');
    expect(sampleLocale(configWith({ app: { primaryLocale: 'tr', locales: ['tr', 'en-US', 'en-GB'] } }))).toBe('en-US');
    expect(sampleLocale(configWith({ app: { primaryLocale: 'de-DE', locales: ['tr', 'de-DE'] } }))).toBe('de-DE');
    const r = platformsReport(configWith({ app: { primaryLocale: 'tr', locales: ['tr', 'en-US'] }, selection: { targets: ['iphone-6.9'] } }), profile);
    expect(r.samples).toEqual({ locale: 'en-US', target: 'iphone-6.9', family: 'iphone' });
    expect(r.formats.find((f) => f.target === 'iphone-6.9')).toMatchObject({ selected: true, size: '1320×2868' });
    expect(r.formats.find((f) => f.target === 'iphone-6.3')).toMatchObject({ selected: false, required: true });
    expect(r).toMatchObject({ language: null, uploader: 'asc' });
  });

  it('reports the asc CLI, the only uploader, from what is installed', () => {
    const none = { asc: null };
    expect(uploaderReport(configWith(), { asc: '1.4.0' })).toMatchObject({ chosen: 'asc', recommended: 'asc' });
    // An old config that still says deliver reports asc too.
    const old = uploaderReport(configWith({ upload: { uploader: 'deliver' } }), none);
    expect(old).toMatchObject({ chosen: 'asc', recommended: 'asc' });
    expect(old.options.map((o) => [o.uploader, o.installed, o.install])).toEqual([['asc', false, 'brew install asc']]);
    expect(uploaderReport(configWith(), { asc: '1.4.0', ascLogin: true }).options[0]!.note).toMatch(/asc auth login/);
    // A missing asc comes with the warning that it will be installed before the upload (only after a yes).
    expect(uploaderReport(configWith(), { ...none, brew: '4.4.0' }).options[0]!.warning).toMatch(/installed with `brew install asc`/);
    expect(uploaderReport(configWith(), { ...none, brew: null }).options[0]!.warning).toMatch(/Homebrew/);
    expect(uploaderReport(configWith(), { asc: '1.4.0' }).options[0]!.warning).toBeUndefined();
  });
});
