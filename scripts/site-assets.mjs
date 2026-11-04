#!/usr/bin/env node
// Builds the web-sized images and videos for the landing page (site/assets).
//
//   node scripts/site-assets.mjs --samples <dir> [--review <dir>] [--no-video]
//
// --samples   a folder with one sub-folder per style preset, each holding the PNGs `vitrin design` rendered for
//             examples/Ritim (`NN_<slug>_<target>.png`, `header_header.png`),
//             plus `video/` with Remotion stills (`mac-40.png`, `tv-140.png`).
// --review    a folder with screenshots of `vitrin review --serve` (`gallery-desktop.png`, `gallery-reject.png`).
// --no-video  skip the App Preview clips (they come from examples/Ritim: `vitrin -C examples/Ritim video --styles all`).
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(join(root, 'packages/render/package.json'));
const sharp = require('sharp');

const args = process.argv.slice(2);
const opt = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const samples = opt('--samples');
const review = opt('--review');
if (!samples) throw new Error('Pass --samples <dir> (one folder per style preset with the rendered PNGs, plus video/).');

const ex = join(root, 'examples/Ritim');
const out = join(root, 'site/assets');
mkdirSync(out, { recursive: true });

const need = (f) => {
  if (!existsSync(f)) throw new Error(`Missing ${f}`);
  return f;
};

async function webp(src, dest, width, quality = 80, extract) {
  let img = sharp(need(src));
  if (extract) img = img.extract(extract);
  await img.resize({ width, withoutEnlargement: true }).webp({ quality, effort: 6 }).toFile(join(out, dest));
}

// The style switcher: three of the twelve presets, six iPhone shots each, plus iPad.
const styles = { glass: 'liquid-glass-aurora', midnight: 'midnight-glow-pro', candy: 'candy-pop-social' };
const slugs = ['today', 'streaks', 'charts', 'reminders', 'custom', 'more'];
for (const [key, style] of Object.entries(styles)) {
  const dir = join(samples, style);
  for (const [i, slug] of slugs.entries()) {
    const n = String(i + 1).padStart(2, '0');
    await webp(join(dir, `${n}_${slug}_iphone-6.9.png`), `${key}-shot-${n}.webp`, 500, 78);
  }
  await webp(join(dir, '01_today_ipad-13.png'), `${key}-ipad.webp`, 640, 78);
}

// The platforms showcase, all in one preset.
const mid = join(samples, styles.midnight);
await webp(join(mid, '01_today_mac-16x10.png'), 'plat-mac.webp', 960, 78);
await webp(join(mid, '01_today_appletv-4k.png'), 'plat-tv.webp', 960, 78);
await webp(join(mid, '01_today_vision-pro.png'), 'plat-vision.webp', 960, 78);
await webp(join(mid, '01_today_watch-ultra.png'), 'plat-watch.webp', 320, 82);
await webp(join(mid, '01_today_duo-outer.png'), 'plat-duo.webp', 440, 78);
await webp(join(mid, 'header_header.png'), 'header.webp', 1600, 78);

// Landscape App Preview stills (Remotion, 1920×1080).
await webp(join(samples, 'video/mac-40.png'), 'preview-mac.webp', 900, 80);
await webp(join(samples, 'video/tv-140.png'), 'preview-tv.webp', 900, 80);

// The review gallery: the "What will be uploaded" summary with the approve bar, and a screenshot marked for changes.
if (review) {
  await webp(join(review, 'gallery-desktop.png'), 'review-summary.webp', 1100, 82, { left: 0, top: 0, width: 1360, height: 1000 });
  await webp(join(review, 'gallery-reject.png'), 'review-reject.webp', 560, 82, { left: 30, top: 18, width: 562, height: 562 });
}

if (!args.includes('--no-video')) {
  const ffmpeg = (a) => execFileSync('ffmpeg', ['-v', 'error', '-y', ...a], { stdio: 'inherit' });
  const missing = (f) => {
    if (!existsSync(f)) throw new Error(`Missing ${f} — render the example first (vitrin -C examples/Ritim video --styles all --locale en-US), or pass --no-video.`);
    return f;
  };
  // Full App Preview (showcase), web-sized.
  const preview = missing(join(ex, 'metadata/store/app-previews/en-US/01_IPHONE_67.mp4'));
  ffmpeg(['-i', preview, '-vf', 'scale=432:-2', '-c:v', 'libx264', '-preset', 'slow', '-crf', '27', '-pix_fmt', 'yuv420p', '-an', '-movflags', '+faststart', join(out, 'preview.mp4')]);
  ffmpeg(['-ss', '5', '-i', preview, '-frames:v', '1', '-vf', 'scale=432:-2', join(out, 'preview.jpg')]);
  // Short silent loops of each style for the style picker.
  for (const style of ['classic', 'showcase', 'kinetic', 'energetic']) {
    const src = missing(join(ex, `metadata/video-styles/en-US/01_${style}.mp4`));
    ffmpeg(['-ss', '2', '-t', '7', '-i', src, '-vf', 'scale=300:-2', '-c:v', 'libx264', '-preset', 'slow', '-crf', '29', '-pix_fmt', 'yuv420p', '-an', '-movflags', '+faststart', join(out, `style-${style}.mp4`)]);
    ffmpeg(['-ss', '3.5', '-i', src, '-frames:v', '1', '-vf', 'scale=300:-2', join(out, `style-${style}.jpg`)]);
  }
}

console.log(`✓ Site assets written to ${out}`);
