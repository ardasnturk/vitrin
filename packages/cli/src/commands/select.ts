import { ASSET_OF_KIND, enabledTargets, getTarget, loadConfig, loadTargets, log, selectedPlatforms, writeText } from '@vitrin/core';
import { AscLocale, AssetKindEnum, PlatformEnum, uploaderOf, VitrinConfig, type AppProfile, type AssetKind, type Evidence, type Platform, type RenderTarget, type Uploader } from '@vitrin/schemas';
import { ASC_INSTALL_HINT } from '@vitrin/upload';
import { readFile } from 'node:fs/promises';
import { relative } from 'node:path';
import pc from 'picocolors';
import { isMap, parseDocument } from 'yaml';
import { EXIT, loadProfile, type Ctx } from '../context.js';
import { detectUploaderTools, type UploaderTools } from './doctor.js';

/**
 * `vitrin platforms` lists what the analyzer detected so the skill can offer a multiple-choice list;
 * `vitrin select` stores the user's choices in vitrin.config.yaml: `selection` (platforms, content, formats),
 * `app.locales`, `ui.language` and `capture.mode`. Every later stage (design, video, capture, validate,
 * upload) only produces what is selected.
 */

/**
 * The one locale the design samples are made in, before the user picks the languages: English (en-US first)
 * when the app has it, otherwise the primary locale.
 */
export function sampleLocale(config: VitrinConfig): string {
  const locales = config.app.locales;
  return locales.find((l) => l === 'en-US') ?? locales.find((l) => l === 'en-GB' || l.startsWith('en')) ?? (locales.includes(config.app.primaryLocale) ? config.app.primaryLocale : locales[0]!) ?? 'en-US';
}

/** The one format the design samples are rendered in: the main iPhone size, else the first screenshot format. */
export function sampleTarget(config: VitrinConfig, profile?: AppProfile): RenderTarget {
  const shotTargets = enabledTargets(config, profile, { quiet: true }).filter((t) => t.kind === 'screenshot');
  return shotTargets.find((t) => t.id === 'iphone-6.9') ?? shotTargets.find((t) => t.family === 'iphone') ?? shotTargets[0] ?? getTarget('iphone-6.9');
}

export const PLATFORM_LABEL: Record<Platform, string> = {
  ios: 'iPhone & iPad (App Store)',
  macos: 'Mac (App Store)',
  watchos: 'Apple Watch (App Store)',
  tvos: 'Apple TV (App Store)',
  visionos: 'Apple Vision Pro (App Store)',
};

export const ASSET_LABEL: Record<AssetKind, string> = {
  metadata: 'Store metadata (name, subtitle, keywords, description)',
  screenshots: 'Screenshots',
  previews: 'App Preview videos',
  creatives: 'Creatives (product page header, search result)',
  events: 'In-App Event cards',
};

export interface PlatformChoice {
  platform: Platform;
  label: string;
  detected: boolean;
  selected: boolean;
  evidence: Evidence[];
  /** Targets this platform would produce if selected with every asset kind (honours targets.enable/disable). */
  targets: Record<Exclude<AssetKind, 'metadata'>, string[]>;
}

export interface PlatformsReport {
  app: string;
  kind: AppProfile['project']['kind'];
  platforms: PlatformChoice[];
  assets: Array<{ asset: AssetKind; label: string; selected: boolean }>;
  /** Formats (target ids) of the selected platforms and content; `selected` follows selection.targets. */
  formats: Array<{ target: string; label: string; platform: Platform; kind: RenderTarget['kind']; size: string; required: boolean; selected: boolean }>;
  /** Store locales: the ones in this run (app.locales) and the ones the project has (detected). */
  locales: Array<{ locale: string; selected: boolean; detected: boolean }>;
  /** Locale and format the design samples are made in (before the user picks languages and formats). */
  samples: { locale: string; target: string; family: string };
  /** The language Vitrin talks to the user in (unset = not asked yet; English until then). */
  language: string | null;
  /** The App Store uploader: always `asc` (kept for readers of this report). */
  uploader: Uploader;
  /** How the app's screens are made: html (from the code, no build) or a real capture. */
  capture: VitrinConfig['capture']['mode'];
  selection: VitrinConfig['selection'];
}

/** Pure: the data behind `vitrin platforms --json`. */
export function platformsReport(config: VitrinConfig, profile: AppProfile): PlatformsReport {
  const current = selectedPlatforms(config, profile).platforms;
  const choices = PlatformEnum.options.map((platform): PlatformChoice => {
    const targets: PlatformChoice['targets'] = { screenshots: [], previews: [], creatives: [], events: [] };
    // Listed as if every asset kind were chosen, so opt-in previews and events show up too.
    const probe = { ...config, selection: { platforms: [platform], assets: AssetKindEnum.options } };
    for (const t of enabledTargets(probe, profile, { quiet: true, allFormats: true })) targets[ASSET_OF_KIND[t.kind] as keyof PlatformChoice['targets']].push(t.id);
    const detected = profile.app.platforms.includes(platform);
    return {
      platform,
      label: PLATFORM_LABEL[platform],
      detected,
      selected: current.includes(platform),
      evidence: profile.app.platformEvidence?.[platform] ?? [],
      targets,
    };
  });
  const assets = config.selection?.assets;
  const chosenFormats = config.selection?.targets;
  const formats = enabledTargets(config, profile, { quiet: true, allFormats: true }).map((t) => ({
    target: t.id,
    label: t.label,
    platform: t.platform,
    kind: t.kind,
    size: `${t.width}×${t.height}`,
    required: t.requirement === 'always',
    selected: !chosenFormats?.length || chosenFormats.includes(t.id),
  }));
  const detectedLocales = profile.app.locales.map((l) => l.asc).filter((x): x is string => Boolean(x));
  const locales = [...new Set([...config.app.locales, ...detectedLocales])].map((locale) => ({ locale, selected: config.app.locales.includes(locale), detected: detectedLocales.includes(locale) }));
  const target = sampleTarget(config, profile);
  return {
    app: profile.app.displayName,
    kind: profile.project.kind,
    // Detected platforms first, so the multi-select shows them on top.
    platforms: [...choices.filter((c) => c.detected), ...choices.filter((c) => !c.detected)],
    assets: AssetKindEnum.options.map((asset) => ({ asset, label: ASSET_LABEL[asset], selected: !assets || assets.includes(asset) })),
    formats,
    locales,
    samples: { locale: sampleLocale(config), target: target.id, family: target.family },
    language: config.ui?.language ?? null,
    uploader: uploaderOf(config),
    capture: config.capture.mode,
    selection: config.selection ?? {},
  };
}

export async function platformsCommand(ctx: Ctx, opts: { json?: boolean } = {}): Promise<number> {
  const profile = await loadProfile(ctx);
  const report = platformsReport(ctx.config, profile);
  if (opts.json ?? ctx.json) {
    process.stdout.write(JSON.stringify(report, null, 2) + '\n');
    return EXIT.OK;
  }
  log.step(`${report.app} (${report.kind}) — platforms`);
  for (const p of report.platforms) {
    const mark = p.selected ? pc.green('●') : pc.dim('○');
    const counts = Object.entries(p.targets)
      .filter(([, ids]) => ids.length)
      .map(([k, ids]) => `${ids.length} ${k}`)
      .join(', ');
    log.info(`${mark} ${p.platform.padEnd(9)} ${p.label}${p.detected ? '' : pc.yellow(' (not detected)')}${counts ? pc.dim(` — ${counts}`) : ''}`);
    for (const e of p.evidence.slice(0, 2)) log.dim(`      ${e.path}${e.note ? ` (${e.note})` : ''}`);
  }
  log.info(`Assets: ${report.assets.map((a) => (a.selected ? a.asset : pc.dim(a.asset))).join(', ')}`);
  log.info(`Formats: ${report.formats.map((f) => (f.selected ? f.target : pc.dim(f.target))).join(', ') || 'none'}`);
  log.info(`Locales: ${report.locales.map((l) => (l.selected ? l.locale : pc.dim(l.locale))).join(', ')} · design samples in ${report.samples.locale} (${report.samples.target})`);
  log.info(`Language: ${report.language ?? pc.yellow('not asked yet (English)')} · uploader: ${report.uploader} · screens: ${report.capture}`);
  log.dim('Change with: vitrin select --platforms ios,watchos --assets screenshots,previews --targets iphone-6.9,ipad-13 --locales en-US,tr --language tr');
  return EXIT.OK;
}

/** Parses a comma-separated CLI value; `all` (or an empty value) clears the selection. */
export function parseChoice<T extends string>(raw: string | string[] | undefined, valid: readonly T[], what: string): T[] | null | undefined {
  if (raw === undefined) return undefined;
  const items = (Array.isArray(raw) ? raw : raw.split(','))
    .map((s) => s.trim())
    .filter(Boolean);
  if (!items.length || (items.length === 1 && items[0] === 'all')) return null;
  const bad = items.filter((i) => !(valid as readonly string[]).includes(i));
  if (bad.length) throw new Error(`Unknown ${what}: ${bad.join(', ')}. Valid: ${valid.join(', ')} (or "all").`);
  return [...new Set(items)] as T[];
}

export interface SelectionChange {
  platforms?: Platform[] | null;
  assets?: AssetKind[] | null;
  /** Formats (target ids); null = every format of the selected platforms. */
  targets?: string[] | null;
  /** Store locales of this run (app.locales); never null. */
  locales?: string[];
  /** app.primaryLocale: the listing's main language, which copy and captures fall back to. */
  primaryLocale?: string;
  /** urls.support / privacy / marketing for every locale (a listing can still override one); '' removes it. */
  urls?: Partial<Record<'support' | 'privacy' | 'marketing', string>>;
  /** ui.language; null removes it. */
  language?: string | null;
  /** capture.mode: html (screens recreated from the code, no build) or launch-args (build + simulators). */
  capture?: CaptureMode;
}

export const CAPTURE_MODES = ['html', 'launch-args', 'xcuitest', 'manual'] as const;
export type CaptureMode = (typeof CAPTURE_MODES)[number];

/**
 * Writes the user's choices into the YAML text, keeping comments and every other key.
 * `null` removes the key (= produce everything detected), `undefined` leaves it unchanged. A removed uploader value
 * (`upload.uploader: deliver | asset-library`) is dropped on the way: uploads always use the asc CLI.
 */
export function applySelection(yamlText: string, change: SelectionChange): string {
  const doc = parseDocument(yamlText);
  const set = (path: string[], v: unknown, flow = true) => (v === null ? doc.hasIn(path) && doc.deleteIn(path) : doc.setIn(path, doc.createNode(v, { flow })));
  for (const key of ['platforms', 'assets', 'targets'] as const) if (change[key] !== undefined) set(['selection', key], change[key]);
  const sel = doc.getIn(['selection']);
  if (isMap(sel) && sel.items.length === 0) doc.delete('selection');
  if (change.locales !== undefined) set(['app', 'locales'], change.locales, false);
  if (change.primaryLocale !== undefined) set(['app', 'primaryLocale'], change.primaryLocale);
  for (const [k, v] of Object.entries(change.urls ?? {})) if (v !== undefined) set(['urls', k], v === '' ? null : v);
  if (change.language !== undefined) {
    set(['ui', 'language'], change.language);
    const ui = doc.getIn(['ui']);
    if (isMap(ui) && ui.items.length === 0) doc.delete('ui');
  }
  const legacy = doc.getIn(['upload', 'uploader']);
  if (legacy === 'deliver' || legacy === 'asset-library') {
    doc.deleteIn(['upload', 'uploader']);
    const upload = doc.getIn(['upload']);
    if (isMap(upload) && upload.items.length === 0) doc.delete('upload');
  }
  if (change.capture !== undefined) set(['capture', 'mode'], change.capture);
  return doc.toString({ lineWidth: 120 });
}

export interface SelectOptions {
  platforms?: string | string[];
  assets?: string | string[];
  targets?: string | string[];
  locales?: string | string[];
  primaryLocale?: string;
  supportUrl?: string;
  privacyUrl?: string;
  marketingUrl?: string;
  language?: string;
  /** Removed: uploads always use the asc CLI. `asc` is accepted and changes nothing; other values only warn. */
  uploader?: string;
  capture?: string;
}

export async function selectCommand(ctx: Ctx, opts: SelectOptions): Promise<number> {
  const platforms = parseChoice(opts.platforms, PlatformEnum.options, 'platform');
  const assets = parseChoice(opts.assets, AssetKindEnum.options, 'asset');
  const targets = parseChoice(opts.targets, loadTargets().map((t) => t.id), 'format');
  const locales = opts.locales === undefined ? undefined : [...new Set((Array.isArray(opts.locales) ? opts.locales : opts.locales.split(',')).map((l) => l.trim()).filter(Boolean))];
  if (locales && !locales.length) throw new Error('--locales needs at least one store locale (e.g. en-US,tr).');
  const primaryLocale = opts.primaryLocale?.trim() || undefined;
  const badLocales = [...(locales ?? []), ...(primaryLocale ? [primaryLocale] : [])].filter((l) => !AscLocale.safeParse(l).success);
  if (badLocales.length) throw new Error(`Invalid store locale: ${badLocales.join(', ')} (App Store Connect codes such as en-US, tr, de-DE).`);
  const language = opts.language === undefined ? undefined : opts.language.trim() === '' || opts.language === 'default' ? null : opts.language.trim();
  if (opts.uploader !== undefined && opts.uploader !== 'asc') log.warn(`--uploader ${opts.uploader} was removed: App Store uploads always use the asc CLI (${ASC_INSTALL_HINT}).`);
  if (opts.capture !== undefined && !(CAPTURE_MODES as readonly string[]).includes(opts.capture)) throw new Error(`Unknown capture mode: ${opts.capture}. Valid: ${CAPTURE_MODES.join(', ')}.`);
  const capture = opts.capture as CaptureMode | undefined;
  const urlEntries = Object.entries({ support: opts.supportUrl, privacy: opts.privacyUrl, marketing: opts.marketingUrl }).filter((e): e is [string, string] => e[1] !== undefined);
  for (const [k, v] of urlEntries) if (v.trim() && !/^https?:\/\/[^\s/]+\.[^\s]+$/.test(v.trim())) throw new Error(`Invalid ${k} URL: ${v} (use a full https:// address).`);
  const urls = urlEntries.length ? (Object.fromEntries(urlEntries.map(([k, v]) => [k, v.trim()])) as SelectionChange['urls']) : undefined;
  const change: SelectionChange = { platforms, assets, targets, locales, primaryLocale, urls, language, capture };
  if (Object.values(change).every((v) => v === undefined)) {
    // `--uploader` alone (older skill text, an older Vitrin for Mac): nothing to store any more.
    if (opts.uploader !== undefined) {
      log.ok('uploader: asc (the only App Store uploader)');
      return EXIT.OK;
    }
    throw new Error('Nothing to select: pass --platforms, --assets, --targets, --locales, --primary-locale, --support-url, --privacy-url, --marketing-url, --language and/or --capture.');
  }
  const text = applySelection(await readFile(ctx.paths.config, 'utf8'), change);
  await writeText(ctx.paths.config, text);
  // Re-read through the schema so an invalid file is caught now, not in the next stage.
  const config = loadConfig(ctx.paths.config);
  ctx.config = config;
  const s = config.selection ?? {};
  log.ok(`selection: platforms ${s.platforms?.join(', ') ?? 'all detected'} · assets ${s.assets?.join(', ') ?? 'all'} · formats ${s.targets?.join(', ') ?? 'all'}`);
  log.ok(`locales: ${config.app.locales.join(', ')} (primary ${config.app.primaryLocale}) · language: ${config.ui?.language ?? 'English (default)'} · screens: ${config.capture.mode}`);
  if (!config.app.locales.includes(config.app.primaryLocale)) log.warn(`The primary locale ${config.app.primaryLocale} is not one of the store locales; copy and captures fall back to it. Add it, or set one of them: vitrin select --primary-locale ${config.app.locales[0]}`);
  const profile = await loadProfile(ctx).catch(() => undefined);
  const enabled = enabledTargets(config, profile);
  log.dim(`  ${enabled.length} formats: ${enabled.map((t) => t.id).join(', ') || 'none'}`);
  if (profile && s.platforms) {
    const { undetected } = selectedPlatforms(config, profile);
    if (undetected.length) log.warn(`Not detected in the project: ${undetected.join(', ')}. Capture needs capture.prebuilt.<platform> or capture.mode: manual for them.`);
  }
  if (profile && locales) {
    const known = profile.app.locales.map((l) => l.asc);
    const extra = locales.filter((l) => !known.includes(l));
    if (extra.length) log.warn(`Not localized in the project: ${extra.join(', ')}. The store listing can still be written in them; captured screens show the app's fallback language.`);
  }
  return EXIT.OK;
}

export interface UploaderReport {
  /** Always `asc`: the asc CLI is the only App Store uploader. */
  chosen: Uploader;
  tools: UploaderTools;
  /** One entry (asc); kept as a list so older readers of `vitrin uploader --json` keep working. */
  options: Array<{ uploader: Uploader; label: string; installed: boolean; install: string; note: string; warning?: string }>;
  recommended: Uploader;
}

/** Pure: the data behind `vitrin uploader --json`. */
export function uploaderReport(config: VitrinConfig, tools: UploaderTools): UploaderReport {
  const login = tools.ascLogin ? '; signed in (asc auth login)' : '';
  const options: UploaderReport['options'] = [
    {
      uploader: 'asc',
      label: 'asc CLI (App-Store-Connect-CLI)',
      installed: Boolean(tools.asc),
      install: 'brew install asc',
      note: tools.asc ? `installed (${tools.asc})${login}` : 'not installed; one Homebrew command',
      // Installing is the user's call: they hear it before anything runs, and Claude installs only after a yes.
      warning: tools.asc
        ? undefined
        : tools.brew === null
          ? 'The asc CLI is not installed and Homebrew was not found. Tell the user Homebrew (https://brew.sh) and then `brew install asc` must be installed before the upload, and install nothing without their yes.'
          : 'The asc CLI is not installed on this computer. Tell the user it will be installed with `brew install asc` before the upload, and run it only after their yes.',
    },
  ];
  return { chosen: uploaderOf(config), tools, options, recommended: 'asc' };
}

/** `vitrin uploader`: whether the asc CLI (the App Store uploader) is installed and signed in. */
export async function uploaderCommand(ctx: Ctx, opts: { json?: boolean } = {}): Promise<number> {
  const report = uploaderReport(ctx.config, await detectUploaderTools());
  if (opts.json ?? ctx.json) {
    process.stdout.write(JSON.stringify(report, null, 2) + '\n');
    return EXIT.OK;
  }
  log.step('App Store uploader: asc CLI');
  for (const o of report.options) {
    log.info(`${o.installed ? pc.green('✓') : pc.dim('○')} ${o.uploader.padEnd(8)} ${o.label} — ${o.note}${o.installed ? '' : pc.dim(` → ${o.install}`)}`);
    if (o.warning) log.warn(`  ${o.warning}`);
  }
  return EXIT.OK;
}
