#!/usr/bin/env node
// The website in Vitrin for Mac's ten languages. site-src/index.html is the English page and the only one written by
// hand; site-src/i18n/<lang>.json maps its text to a translation, and this script writes site/index.html and
// site/<lang>/index.html from the two, so every language has a real page that works with no JavaScript.
//
//   node scripts/site-i18n.mjs extract   writes site-src/i18n/en.json, the texts to translate
//   node scripts/site-i18n.mjs build     writes the pages and the sitemap, and fails on a missing text
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const site = join(root, 'site');
const src = join(root, 'site-src');
const origin = 'https://vitrin.ardasnturk.com';
const LANGUAGES = [
  ['en', 'English'],
  ['tr', 'Türkçe'],
  ['de', 'Deutsch'],
  ['es', 'Español'],
  ['fr', 'Français'],
  ['it', 'Italiano'],
  ['ja', '日本語'],
  ['ko', '한국어'],
  ['pt-BR', 'Português (Brasil)'],
  ['zh-Hans', '简体中文'],
];
const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);
const SKIP = new Set(['script', 'style', 'svg', 'head']);
const ATTRIBUTES = /\s(alt|aria-label|title|placeholder|data-copied)="([^"]+)"/g;
/** Words outside the page: what script.js shows, the menu's name, and the 404 page. */
const NOT_FOUND = ['Page not found — Vitrin', 'This page isn’t on the shelf.', 'The link may be outdated. Everything about Vitrin is on the home page.', 'Back to Vitrin'];
const EXTRA = ['Copied', 'Press ⌘C', 'Language', ...NOT_FOUND];

/** [start, end] of each piece of text in the page: the inside of the outermost element that holds words directly. */
function textRanges(html) {
  const found = [];
  const stack = [];
  let skipping = 0;
  let last = 0;
  const tag = /<!--[\s\S]*?-->|<(\/?)([a-zA-Z][a-zA-Z0-9]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>/g;
  const words = (text) => /\p{L}/u.test(text.replace(/&[a-z]+;/g, ''));
  for (let m; (m = tag.exec(html)); ) {
    if (!skipping && stack.length && words(html.slice(last, m.index))) stack.at(-1).text = true;
    last = tag.lastIndex;
    if (m[0].startsWith('<!--') || m[2] === undefined) continue;
    const name = m[2].toLowerCase();
    if (m[1]) {
      const open = stack.pop();
      if (SKIP.has(name) || open?.keep) skipping--;
      if (open?.text && !skipping) found.push([open.start, m.index]);
    } else if (!m[4] && !VOID.has(name)) {
      const keep = /\stranslate="no"/.test(m[3]);
      if (SKIP.has(name) || keep) skipping++;
      stack.push({ name, start: tag.lastIndex, keep, text: false });
    }
  }
  const outer = found.filter(([a, b]) => !found.some(([c, d]) => c <= a && b <= d && (c !== a || d !== b)));
  return outer.sort((x, y) => x[0] - y[0]);
}

/** Every attribute with words in it, outside <head>, <script> and <style>. */
function attributeTexts(body) {
  const out = [];
  for (const m of body.matchAll(ATTRIBUTES)) if (/\p{L}/u.test(m[2])) out.push(m[2]);
  return out;
}

const META = /<meta (?:name="description"|property="og:(?:title|description)") content="([^"]+)"/g;
const TITLE = /<title>([^<]+)<\/title>/;
const SCHEMA = /"description": "([^"]+)"/;

function texts(html) {
  const head = html.slice(0, html.indexOf('<body'));
  const body = html.slice(html.indexOf('<body'));
  const list = [TITLE.exec(head)[1], ...[...head.matchAll(META)].map((m) => m[1]), SCHEMA.exec(head)[1]];
  for (const [a, b] of textRanges(html)) list.push(html.slice(a, b).trim());
  list.push(...attributeTexts(body.replace(/<script[\s\S]*?<\/script>/g, '')));
  return [...new Set([...list, ...EXTRA])];
}

function pageFor(lang, html, table) {
  const say = (text) => {
    const out = table[text];
    if (out === undefined) throw new Error(`${lang}: no translation for: ${text.slice(0, 90)}`);
    return out;
  };
  // Body text, from the end so the offsets stay right.
  let page = html;
  for (const [a, b] of textRanges(html).reverse()) {
    const inner = html.slice(a, b);
    const lead = inner.match(/^\s*/)[0];
    const tail = inner.match(/\s*$/)[0];
    page = page.slice(0, a) + lead + say(inner.trim()) + tail + page.slice(b);
  }
  const start = page.indexOf('<body');
  let head = page.slice(0, start);
  let body = page.slice(start);
  body = body.replace(ATTRIBUTES, (all, name, value) => (/\p{L}/u.test(value) ? ` ${name}="${say(value)}"` : all));
  head = head.replace(TITLE, (_, t) => `<title>${say(t)}</title>`);
  head = head.replace(META, (all, t) => all.replace(t, say(t).replace(/"/g, '&quot;')));
  head = head.replace(SCHEMA, (all, t) => all.replace(t, say(t).replace(/"/g, '\\"')));
  head = head.replace('<html lang="en">', `<html lang="${lang}">`);
  page = (head + body).replace('<html lang="', `<html data-copied="${say('Copied')}" data-copy-fallback="${say('Press ⌘C')}" lang="`);
  // One level down from the English page.
  page = page.replace(/(href|src|poster)="(assets\/|styles\.css|script\.js|favicon\.ico|site\.webmanifest)/g, '$1="../$2');
  page = page.replace(/href="\.\.\/assets\/fonts/g, 'href="../assets/fonts');
  return page;
}

function languageLinks(html, lang) {
  const url = (l) => (l === 'en' ? `${origin}/` : `${origin}/${l}/`);
  const alternates = LANGUAGES.map(([l]) => `  <link rel="alternate" hreflang="${l}" href="${url(l)}">`).join('\n');
  html = html.replace(/<link rel="canonical"[^>]*>/, `<link rel="canonical" href="${url(lang)}">\n${alternates}\n  <link rel="alternate" hreflang="x-default" href="${origin}/">`);
  html = html.replace(/<meta property="og:url"[^>]*>/, `<meta property="og:url" content="${url(lang)}">`);
  return html;
}

/** The menu: plain links, so it works with no JavaScript. */
function menu(html, lang, label) {
  const prefix = lang === 'en' ? '' : '../';
  const href = (l) => (l === 'en' ? (prefix || './') : `${prefix}${l}/`);
  const items = LANGUAGES.map(([l, name]) => `<a href="${href(l)}" hreflang="${l}" lang="${l}" translate="no"${l === lang ? ' aria-current="page"' : ''}>${name}</a>`).join('');
  const current = LANGUAGES.find(([l]) => l === lang)[1];
  const block = `<details class="lang" translate="no"><summary aria-label="${label}"><svg class="ico"><use href="#i-globe"/></svg><span>${current}</span></summary><div class="lang-list">${items}</div></details>`;
  return html.replace('<!--language-menu-->', block);
}

/** Sends a first visit to the visitor's language, once. A choice made in the menu wins. */
const REDIRECT = `<script>(function(){try{if(localStorage.getItem('vitrin-language'))return;var o=${JSON.stringify(LANGUAGES.map(([l]) => l).filter((l) => l !== 'en'))};var w=(navigator.languages||[navigator.language]);for(var i=0;i<w.length;i++){var c=w[i].toLowerCase();if(c.indexOf('en')===0)return;var h=c.indexOf('zh')===0?'zh-Hans':c.indexOf('pt')===0?'pt-BR':c.slice(0,2);if(o.indexOf(h)>=0){location.replace(h+'/');return}}}catch(e){}})()</script>`;

const source = readFileSync(join(src, 'index.html'), 'utf8');
const command = process.argv[2];
if (command === 'extract') {
    const list = texts(source);
  writeFileSync(join(src, 'i18n', 'en.json'), `${JSON.stringify(Object.fromEntries(list.map((t) => [t, t])), null, 2)}\n`);
  console.log(`${list.length} texts, ${list.join(' ').split(/\s+/).length} words`);
} else if (command === 'build') {
  const label = 'Language';
  const english = languageLinks(menu(source, 'en', label), 'en').replace('</title>', `</title>\n  ${REDIRECT}`);
  writeFileSync(join(site, 'index.html'), english);
  for (const [lang] of LANGUAGES.slice(1)) {
    const table = JSON.parse(readFileSync(join(src, 'i18n', `${lang}.json`), 'utf8'));
    const page = languageLinks(menu(pageFor(lang, source, table), lang, table[label] ?? label), lang);
    mkdirSync(join(site, lang), { recursive: true });
    writeFileSync(join(site, lang, 'index.html'), page);
  }
  // One 404 page serves every address, so it picks its words in the browser.
  const words = Object.fromEntries(LANGUAGES.slice(1).map(([l]) => [l, NOT_FOUND.map((t) => JSON.parse(readFileSync(join(src, 'i18n', `${l}.json`), 'utf8'))[t])]));
  const notFound = readFileSync(join(site, '404.html'), 'utf8').replace(/const WORDS = .*;/, `const WORDS = ${JSON.stringify(words)};`);
  writeFileSync(join(site, '404.html'), notFound);
  const today = new Date().toISOString().slice(0, 10);
  const urls = LANGUAGES.map(([l]) => `  <url>\n    <loc>${origin}/${l === 'en' ? '' : `${l}/`}</loc>\n    <lastmod>${today}</lastmod>\n  </url>`).join('\n');
  writeFileSync(join(site, 'sitemap.xml'), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`);
  console.log(`${LANGUAGES.length} pages`);
} else {
  console.error('site-i18n: extract or build');
  process.exit(1);
}
