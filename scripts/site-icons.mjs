#!/usr/bin/env node
// Builds the website's favicon set and its social image from site/assets/favicon.svg, logo.svg and the sample shots.
//
//   node scripts/site-icons.mjs
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(join(root, 'packages/render/package.json'));
const sharp = require('sharp');
const { chromium } = require('playwright');

const site = join(root, 'site');
const assets = join(site, 'assets');
const favicon = readFileSync(join(assets, 'favicon.svg'));
const logo = readFileSync(join(assets, 'logo.svg'));
const png = (svg, size) => sharp(svg, { density: Math.ceil((72 * size) / 16) }).resize(size, size).png().toBuffer();

// favicon.ico: the small sizes, as PNGs in an ICO directory.
const sizes = [16, 32, 48];
const images = await Promise.all(sizes.map((size) => png(favicon, size)));
const header = Buffer.alloc(6 + 16 * sizes.length);
header.writeUInt16LE(1, 2);
header.writeUInt16LE(sizes.length, 4);
let offset = header.length;
sizes.forEach((size, i) => {
  const entry = 6 + 16 * i;
  header.writeUInt8(size, entry);
  header.writeUInt8(size, entry + 1);
  header.writeUInt16LE(1, entry + 4);
  header.writeUInt16LE(32, entry + 6);
  header.writeUInt32LE(images[i].length, entry + 8);
  header.writeUInt32LE(offset, entry + 12);
  offset += images[i].length;
});
writeFileSync(join(site, 'favicon.ico'), Buffer.concat([header, ...images]));

// The large icons use the full logo; iOS rounds the touch icon itself, so it has no transparent corners.
const flat = (size) => sharp(logo, { density: Math.ceil((72 * size) / 64) }).resize(size, size).flatten({ background: '#FA6B61' }).png();
await flat(180).toFile(join(assets, 'apple-touch-icon.png'));
await flat(192).toFile(join(assets, 'icon-192.png'));
await flat(512).toFile(join(assets, 'icon-512.png'));

const url = (file) => pathToFileURL(join(assets, file)).href;
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
const html = `<!doctype html><style>
@font-face { font-family: J; src: url('${url('fonts/plus-jakarta-sans-latin-wght-normal.woff2')}'); font-weight: 200 800; }
* { box-sizing: border-box; margin: 0; }
body { width: 1200px; height: 630px; overflow: hidden; position: relative; background: #140D11; color: #FCF2EC; font-family: J; }
.b { position: absolute; border-radius: 50%; filter: blur(90px); opacity: .55; }
.awn { position: absolute; left: 0; right: 0; top: 0; height: 40px; background: repeating-linear-gradient(90deg, #F2694F 0 60px, #FFF3EA 60px 120px);
  -webkit-mask: radial-gradient(30px 16px at 50% calc(100% - 16px), #000 98%, transparent) 0 0 / 60px 100% repeat-x, linear-gradient(#000, #000) 0 0 / 100% calc(100% - 16px) no-repeat; }
.copy { position: absolute; left: 72px; top: 132px; width: 640px; }
.brand { display: flex; align-items: center; gap: 16px; font-size: 34px; font-weight: 700; letter-spacing: -.02em; }
.brand img { width: 62px; height: 62px; }
h1 { margin-top: 38px; font-size: 74px; line-height: 1.04; letter-spacing: -.035em; font-weight: 800; }
h1 span { background: linear-gradient(100deg, #FFB25C, #FF8172 45%, #F570AC); -webkit-background-clip: text; color: transparent; }
p { margin-top: 26px; font-size: 26px; color: #D8C6C9; line-height: 1.35; }
.shot { position: absolute; width: 268px; border-radius: 26px; box-shadow: 0 30px 70px rgba(0, 0, 0, .6); }
</style>
<i class="b" style="width:560px;height:560px;left:-200px;top:-260px;background:#FF9E33"></i>
<i class="b" style="width:560px;height:560px;right:-120px;top:-120px;background:#FA6B61"></i>
<i class="b" style="width:560px;height:560px;left:400px;bottom:-400px;background:#ED5C9E"></i>
<img class="shot" src="${url('midnight-shot-02.webp')}" style="left:736px;top:118px;transform:rotate(-7deg)">
<img class="shot" src="${url('midnight-shot-01.webp')}" style="left:904px;top:70px;transform:rotate(5deg)">
<div class="awn"></div>
<div class="copy">
  <div class="brand"><img src="${url('logo.svg')}"><span>Vitrin</span></div>
  <h1>Your store listing, <span>built from your code.</span></h1>
  <p>Plus App Store Connect in one Mac app.</p>
</div>`;
// A file, not setContent: an about:blank page can't load file:// fonts and images.
const file = join(mkdtempSync(join(tmpdir(), 'vitrin-og-')), 'og.html');
writeFileSync(file, html);
await page.goto(pathToFileURL(file).href, { waitUntil: 'load' });
await page.evaluate(() => document.fonts.ready);
const social = await page.screenshot();
await browser.close();
await sharp(social).png({ compressionLevel: 9, palette: true, quality: 92 }).toFile(join(assets, 'og.png'));
console.log('ok');
