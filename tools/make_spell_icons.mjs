/**
 * Spell icons for the addon, drawn from the web's own icon geometry (src/components/game/SpellIcon.tsx:
 * 48x48 grid, gradients, glow disc red for self spells / steel for rival spells). The JSX of each
 * icon is converted to plain SVG and rasterised with Chromium (Playwright) at 128 px; then
 * tools/make_icon.py-style post-processing (resize to 64, RGB bleed) writes WoW TGAs.
 *
 *   node tools/make_spell_icons.mjs <web repo> <png out dir>
 *   python3 tools/png_to_tga.py <png out dir> StackRivals/Media/Spells
 */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const [web, out] = process.argv.slice(2);
if (!web || !out) throw new Error("usage: node make_spell_icons.mjs <web repo> <out dir>");
mkdirSync(out, { recursive: true });
const src = readFileSync(`${web}/src/components/game/SpellIcon.tsx`, "utf8");
const block = src.slice(src.indexOf("const ICONS"), src.indexOf("export function SpellIcon"));
const self = { bomb: 1, lineBlast: 1, freeze: 1, swap: 1, clearBoard: 1 };
const re = /(\w+): \(u\) => \(<>([\s\S]*?)<\/>\),/g;
const kebab = (s) => s.replace(/[A-Z]/g, (m) => "-" + m.toLowerCase());
let m, n = 0;
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 128, height: 128 } });
while ((m = re.exec(block))) {
  const [, id, jsx] = m;
  let body = jsx
    .replace(/\{u\.(\w)\}/g, 'url(#$1)')
    .replace(/=url\(#(\w)\)/g, '="url(#$1)"')
    .replace(/\s([a-z]+[A-Z][A-Za-z]*)=/g, (_, a) => " " + kebab(a) + "=");
  const glow = self[id] ? ["#E0242F", 0.55] : ["#4FA8FF", 0.5];
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="128" height="128">
<defs>
<linearGradient id="r" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FF6B74"/><stop offset="1" stop-color="#B8151F"/></linearGradient>
<linearGradient id="s" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#9BD0FF"/><stop offset="1" stop-color="#4F8DB3"/></linearGradient>
<linearGradient id="y" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFE98A"/><stop offset="1" stop-color="#F0A020"/></linearGradient>
<linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#6B7384"/><stop offset="1" stop-color="#3A404D"/></linearGradient>
<radialGradient id="w" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="${glow[0]}" stop-opacity="${glow[1]}"/><stop offset="1" stop-color="${glow[0]}" stop-opacity="0"/></radialGradient>
</defs><circle cx="24" cy="24" r="22" fill="url(#w)"/>${body}</svg>`;
  writeFileSync(`${out}/${id}.svg`, svg);
  await page.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
  await page.locator("svg").screenshot({ path: `${out}/${id}.png`, omitBackground: true });
  n++;
}
await browser.close();
console.log(`${n} icons`);
