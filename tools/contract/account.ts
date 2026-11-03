/**
 * StackRivals account codes, DRAFT v1: TypeScript reference for stackrivals.io.
 * Same rules as the addon's StackRivals/Net/AccountCodes.lua; both are checked against
 * docs/vectors/account_v1.json (bun tools/contract/check_account_vectors.ts).
 * No imports: the web project may copy this file. `hashString` = FNV-1a 32 over the code's
 * characters (all codes are ASCII), the same function as SR1's check (src/game/engine/prng.ts).
 * Spec: docs/ACCOUNT_SYNC_HANDOFF.md section 3.
 */

export const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
export const PLATFORMS = ["wow-forever", "wow-retail", "wow-classic"] as const;
export type Platform = (typeof PLATFORMS)[number];
export const MAX_CODE = 4096;
export const MAX_HISTORY = 10;

export function hashString(input: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}
const check = (body: string) => hashString(body).toString(16).padStart(8, "0");

// ---- helpers shared with SR1 ------------------------------------------------------------------
const B36 = /^[0-9a-z]{1,9}$/;
/** canonical base 36 (no leading zeros, "0" for zero, at most 9 characters) */
export function unb36(s: string): number | null {
  if (!B36.test(s) || (s !== "0" && s[0] === "0")) return null;
  return parseInt(s, 36);
}
export const b36 = (n: number) => Math.floor(n).toString(36);

const enc = new TextEncoder();
const dec = new TextDecoder("utf-8", { fatal: true });
export const toHex = (s: string) => Array.from(enc.encode(s), (b) => b.toString(16).padStart(2, "0")).join("");
export function fromHex(h: string): string | null {
  if (h.length % 2 !== 0 || !/^[0-9a-f]*$/.test(h)) return null;
  const bytes = new Uint8Array(h.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(h.slice(2 * i, 2 * i + 2), 16);
  try { return dec.decode(bytes); } catch { return null; }
}
const byteLen = (s: string) => enc.encode(s).length;

/** WoW "Name-Realm" rules (= SR1 nameOk in tools/sr1/sr1.ts). */
function isLetter(cp: number): boolean {
  return (cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122) || (cp >= 0xc0 && cp <= 0x24f && cp !== 0xd7 && cp !== 0xf7)
    || (cp >= 0x370 && cp <= 0x3ff) || (cp >= 0x400 && cp <= 0x4ff) || (cp >= 0xac00 && cp <= 0xd7a3) || (cp >= 0x4e00 && cp <= 0x9fff);
}
export function nameOk(s: string): boolean {
  const n = byteLen(s);
  if (n < 1 || n > 64) return false;
  const cps = Array.from(s, (c) => c.codePointAt(0)!);
  const dashes = cps.filter((c) => c === 45).length;
  if (dashes !== 1) return false;
  const d = cps.indexOf(45);
  const nameLen = d, realmLen = cps.length - d - 1;
  if (nameLen < 2 || nameLen > 12 || realmLen < 1 || realmLen > 40) return false;
  return cps.every((cp, i) => i === d || (i < d ? isLetter(cp) : isLetter(cp) || (cp >= 48 && cp <= 57) || cp === 39));
}
/** display text from the web: valid UTF-8 (JS strings are), 1..max bytes, no control characters */
const textOk = (s: string, max: number) => byteLen(s) >= 1 && byteLen(s) <= max && !/[\u0000-\u001f\u007f]/.test(s);
function hexText(h: string, max: number, optional: boolean): { ok: boolean; text: string | null } {
  if (optional && h === "-") return { ok: true, text: null };
  if (h.length < 2 || h.length > 2 * max) return { ok: false, text: null };
  const s = fromHex(h);
  if (s === null || !textOk(s, max)) return { ok: false, text: null };
  return { ok: true, text: s };
}
function clean(code: unknown): { code: string } | { error: string } {
  if (typeof code !== "string") return { error: "empty" };
  const c = code.replace(/[ \t\r\n\f\v]/g, "");
  if (c === "") return { error: "empty" };
  if (/[^\x21-\x7e]/.test(c)) return { error: "chars" };
  if (c.length > MAX_CODE) return { error: "size" };
  return { code: c };
}
const verifyCheck = (f: string[]) => {
  const last = f[f.length - 1];
  return /^[0-9a-f]{8}$/.test(last) && last === check(f.slice(0, -1).join("."));
};
const finish = (fields: string[]) => { const body = fields.join("."); return body + "." + check(body); };

// ---- 3.1 web link code -------------------------------------------------------------------------
function checkSymbol(seven: string): string {
  let sum = 0;
  for (let i = 0; i < 7; i++) sum += CROCKFORD.indexOf(seven[i]) * (2 * (i + 1) - 1);
  return CROCKFORD[sum % 32];
}
/** Make a code from 7 CSPRNG symbols (the website). */
export function makeWebCode(seven: string): string {
  if (seven.length !== 7 || [...seven].some((c) => !CROCKFORD.includes(c))) throw new Error("symbols");
  return seven + checkSymbol(seven);
}
export const prettyWebCode = (code: string) => code.slice(0, 4) + "-" + code.slice(4, 8);
export function parseWebCode(s: string): { ok: true; code: string } | { ok: false; error: "format" | "check" } {
  const n = s.toUpperCase().replace(/[\s-]/g, "").replace(/O/g, "0").replace(/[IL]/g, "1");
  if (n.length !== 8 || [...n].some((c) => !CROCKFORD.includes(c))) return { ok: false, error: "format" };
  if (checkSymbol(n.slice(0, 7)) !== n[7]) return { ok: false, error: "check" };
  return { ok: true, code: n };
}

// ---- 3.2 link request SRL1 ---------------------------------------------------------------------
export interface LinkRequest { code: string; platform: Platform; player: string; linkId: string; addon: string; engine: number; issued: number }
const isLinkId = (s: string) => /^[a-z0-9]{12}$/.test(s);

export function encodeLinkRequest(r: LinkRequest): string {
  return finish(["SRL1", r.code, r.platform, toHex(r.player), r.linkId, r.addon.replace(/\./g, "-"), String(r.engine), b36(r.issued)]);
}
export function parseLinkRequest(input: unknown): ({ ok: true } & LinkRequest) | { ok: false; error: string } {
  const c = clean(input);
  if ("error" in c) return { ok: false, error: c.error };
  const f = c.code.split(".");
  if (f[0] !== "SRL1") return { ok: false, error: /^SRL\d+$/.test(f[0]) ? "version" : "format" };
  if (f.length !== 9) return { ok: false, error: "fields" };
  if (!verifyCheck(f)) return { ok: false, error: "check" };
  const w = parseWebCode(f[1]);
  if (!w.ok || w.code !== f[1]) return { ok: false, error: "code" };
  if (!(PLATFORMS as readonly string[]).includes(f[2])) return { ok: false, error: "platform" };
  const player = f[3].length >= 2 ? fromHex(f[3]) : null;
  if (player === null || !nameOk(player)) return { ok: false, error: "player" };
  if (!isLinkId(f[4])) return { ok: false, error: "linkId" };
  if (!/^[A-Za-z0-9-]{1,20}$/.test(f[5])) return { ok: false, error: "addon" };
  if (!/^[1-9]\d{0,3}$/.test(f[6])) return { ok: false, error: "engine" };
  const issued = unb36(f[7]);
  if (issued === null) return { ok: false, error: "issued" };
  return { ok: true, code: f[1], platform: f[2] as Platform, player, linkId: f[4], addon: f[5].replace(/-/g, "."), engine: Number(f[6]), issued };
}

// ---- 3.3 profile snapshot SRP1 -----------------------------------------------------------------
export interface HistoryEntry { mode: string; res: "w" | "l" | "d"; my: number; their: number; at: number }
export interface ProfileSnapshot {
  linkId: string; player: string; accountId: string; name: string; issued: number; expires: number;
  level: number; xp: number; xpNext: number; rank: string | null; season: string | null; seasonPct: number;
  wins: number; losses: number; draws: number; history: HistoryEntry[];
  achUnlocked: number | null; achTotal: number | null; cosOwned: number | null; cosEquipped: string | null; sig: string | null;
}
const MAX_SPAN = 30 * 86400;

export function encodeProfile(p: ProfileSnapshot): string {
  if (p.history.length > MAX_HISTORY) throw new Error("history");
  const hx = (s: string | null) => (s === null ? "-" : toHex(s));
  const hist = p.history.length === 0 ? "-" : p.history.map((h) => [h.mode, h.res, b36(h.my), b36(h.their), b36(h.at)].join("-")).join("~");
  return finish([
    "SRP1", p.linkId, toHex(p.player), p.accountId, toHex(p.name), b36(p.issued), b36(p.expires),
    b36(p.level), b36(p.xp), b36(p.xpNext), hx(p.rank), hx(p.season), String(p.seasonPct),
    b36(p.wins), b36(p.losses), b36(p.draws), hist,
    p.achUnlocked === null ? "-" : `${b36(p.achUnlocked)}-${b36(p.achTotal ?? 0)}`,
    p.cosOwned === null ? "-" : `${b36(p.cosOwned)}-${hx(p.cosEquipped)}`,
    p.sig ?? "-",
  ]);
}

export function parseProfile(input: unknown): ({ ok: true } & ProfileSnapshot) | { ok: false; error: string } {
  const bad = (error: string) => ({ ok: false as const, error });
  const c = clean(input);
  if ("error" in c) return bad(c.error);
  const f = c.code.split(".");
  if (f[0] !== "SRP1") {
    if (/^SRP\d+$/.test(f[0])) return bad("version");
    if (/^SR[A-Z0-9]+$/.test(f[0])) return bad("wrong_kind");
    return bad("format");
  }
  if (f.length !== 21) return bad("fields");
  if (!verifyCheck(f)) return bad("check");
  if (!isLinkId(f[1])) return bad("linkId");
  const player = f[2].length >= 2 ? fromHex(f[2]) : null;
  if (player === null || !nameOk(player)) return bad("player");
  if (!/^[a-z0-9_-]{4,40}$/.test(f[3])) return bad("accountId");
  const name = hexText(f[4], 32, false);
  if (!name.ok) return bad("name");
  const issued = unb36(f[5]), expires = unb36(f[6]);
  if (issued === null || expires === null || expires <= issued || expires - issued > MAX_SPAN) return bad("time");
  const level = unb36(f[7]), xp = unb36(f[8]), xpNext = unb36(f[9]);
  if (level === null || level > 9999 || xp === null || xp > 1e12 || xpNext === null || xpNext > 1e12) return bad("numbers");
  const rank = hexText(f[10], 24, true), season = hexText(f[11], 24, true);
  if (!rank.ok) return bad("rank");
  if (!season.ok) return bad("season");
  if (!/^\d{1,3}$/.test(f[12]) || Number(f[12]) > 100) return bad("season");
  const wins = unb36(f[13]), losses = unb36(f[14]), draws = unb36(f[15]);
  if (wins === null || losses === null || draws === null || wins > 1e9 || losses > 1e9 || draws > 1e9) return bad("numbers");
  const history: HistoryEntry[] = [];
  if (f[16] !== "-") {
    const entries = f[16].split("~");
    if (entries.length > MAX_HISTORY) return bad("history");
    for (const e of entries) {
      const m = /^([a-z0-9]{1,12})-([wld])-([0-9a-z]+)-([0-9a-z]+)-([0-9a-z]+)$/.exec(e);
      if (!m) return bad("history");
      const my = unb36(m[3]), their = unb36(m[4]), at = unb36(m[5]);
      if (my === null || their === null || at === null) return bad("history");
      history.push({ mode: m[1], res: m[2] as HistoryEntry["res"], my, their, at });
    }
  }
  let achUnlocked: number | null = null, achTotal: number | null = null;
  if (f[17] !== "-") {
    const m = /^([0-9a-z]+)-([0-9a-z]+)$/.exec(f[17]);
    const u = m ? unb36(m[1]) : null, t = m ? unb36(m[2]) : null;
    if (u === null || t === null || u > t || t > 9999) return bad("achievements");
    achUnlocked = u; achTotal = t;
  }
  let cosOwned: number | null = null, cosEquipped: string | null = null;
  if (f[18] !== "-") {
    const m = /^([0-9a-z]+)-(.+)$/.exec(f[18]);
    const o = m ? unb36(m[1]) : null;
    if (o === null || o > 99999) return bad("cosmetics");
    const e = hexText(m![2], 24, true);
    if (!e.ok) return bad("cosmetics");
    cosOwned = o; cosEquipped = e.text;
  }
  if (f[19] !== "-" && !/^[A-Za-z0-9_-]{16,128}$/.test(f[19])) return bad("sig");
  return {
    ok: true, linkId: f[1], player, accountId: f[3], name: name.text!, issued, expires, level, xp, xpNext,
    rank: rank.text, season: season.text, seasonPct: Number(f[12]), wins, losses, draws, history,
    achUnlocked, achTotal, cosOwned, cosEquipped, sig: f[19] === "-" ? null : f[19],
  };
}
