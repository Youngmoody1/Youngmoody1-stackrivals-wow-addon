/**
 * SR1 cross-platform codes — TypeScript reference implementation for stackrivals.io.
 * Written from the spec (docs/CROSS_PLATFORM_MULTIPLAYER.md §6), independently of the Lua addon,
 * and checked against the shared vectors (docs/vectors/sr1.json) by check_vectors.ts.
 *
 * The web project may copy this file as-is. It has no imports: pass the web engine's
 * `hashString` (src/game/engine/prng.ts) and, for importResult, `verifyLog` (src/lib/match/rules.ts).
 */

export const SR1_RULESETS = {
  b120: { timeCapMs: 120_000, countdownMs: 3_000, startLevel: 1 },
  r180: { timeCapMs: 180_000, countdownMs: 4_000, startLevel: 1 },
  daily120: { timeCapMs: 120_000, countdownMs: 3_000, startLevel: 1, seedRe: /^srwow-daily-\d{4}-\d{2}-\d{2}$/ },
} as const;
export type Sr1RulesetId = keyof typeof SR1_RULESETS;
export const SR1_PLATFORMS = ["wow-forever", "wow-retail", "wow-classic"] as const;
export type Sr1Platform = (typeof SR1_PLATFORMS)[number];
export const SR1_MAX_CODE = 32_768;
const ACTION_LETTERS = "ABCDEFG"; // index into INPUT_ACTIONS: left,right,rotateCW,rotateCCW,softDrop,hardDrop,hold

type HashString = (s: string) => number;

const SEED_RE = /^[a-z0-9-]{1,64}$/;
const B36_RE = /^(0|[1-9a-z][0-9a-z]{0,8})$/; // canonical, ≤ 9 chars
const ENGINE_RE = /^e([1-9][0-9]{0,3})$/;
const LINK_RE = /^[A-Z0-9]{6,12}$/;

const hex8 = (n: number) => (n >>> 0).toString(16).padStart(8, "0");
const checkOf = (body: string, h: HashString) => hex8(h(body));
const b36 = (n: number) => {
  if (!Number.isInteger(n) || n < 0) throw new Error("b36: non-negative integer expected");
  return n.toString(36);
};
const unb36 = (s: string): number | null => (B36_RE.test(s) ? parseInt(s, 36) : null);

function realDate(y: number, m: number, d: number): boolean {
  if (m < 1 || m > 12 || d < 1) return false;
  const leap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
  return d <= [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]!;
}

function seedOk(ruleset: string, seed: string): ruleset is Sr1RulesetId {
  const rs = (SR1_RULESETS as Record<string, { seedRe?: RegExp }>)[ruleset];
  if (!rs || !SEED_RE.test(seed)) return false;
  if (!rs.seedRe) return true;
  if (!rs.seedRe.test(seed)) return false;
  const [y, m, d] = seed.slice("srwow-daily-".length).split("-").map(Number);
  return realDate(y!, m!, d!);
}

/** Remove ASCII whitespace only; anything else outside printable ASCII is "chars"; then the size. */
function clean(code: unknown): { code: string } | { error: "size" | "chars" } {
  if (typeof code !== "string") return { error: "size" };
  const c = code.replace(/[ \t\r\n\f\v]+/g, "");
  if (/[^\x21-\x7e]/.test(c)) return { error: "chars" };
  if (c.length > SR1_MAX_CODE) return { error: "size" };
  return { code: c };
}

// Letters of WoW's character-name locales (Latin incl. accents, Greek, Cyrillic, Hangul, CJK).
function isLetter(cp: number): boolean {
  return (cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122)
    || (cp >= 0xc0 && cp <= 0x24f && cp !== 0xd7 && cp !== 0xf7)
    || (cp >= 0x370 && cp <= 0x3ff) || (cp >= 0x400 && cp <= 0x4ff)
    || (cp >= 0xac00 && cp <= 0xd7a3) || (cp >= 0x4e00 && cp <= 0x9fff);
}

/** "Name-Realm": name 2..12 letters; realm 1..40 letters/digits/apostrophes; 1..64 UTF-8 bytes. */
export function nameOk(s: string): boolean {
  const bytes = new TextEncoder().encode(s).length;
  if (bytes < 1 || bytes > 64) return false;
  const cps = [...s].map((ch) => ch.codePointAt(0)!);
  const dashes = cps.filter((cp) => cp === 45).length;
  if (dashes !== 1) return false;
  const dash = cps.indexOf(45);
  const name = cps.slice(0, dash), realm = cps.slice(dash + 1);
  if (name.length < 2 || name.length > 12 || realm.length < 1 || realm.length > 40) return false;
  return name.every(isLetter) && realm.every((cp) => isLetter(cp) || (cp >= 48 && cp <= 57) || cp === 39);
}

function checkOk(fields: string[], h: HashString): boolean {
  const last = fields[fields.length - 1]!;
  return /^[0-9a-fA-F]{8}$/.test(last) && last === checkOf(fields.slice(0, -1).join("."), h);
}

/** UTF-8 bytes -> lowercase hex, and back (strict UTF-8). */
export function toHex(s: string): string {
  return [...new TextEncoder().encode(s)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
export function fromHex(h: string): string | null {
  if (h.length % 2 !== 0 || !/^[0-9a-f]+$/.test(h)) return null;
  const bytes = new Uint8Array(h.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(h.slice(i * 2, i * 2 + 2), 16);
  try {
    // ignoreBOM: keep a leading U+FEFF (then rejected by nameOk) instead of silently dropping it
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
  } catch {
    return null;
  }
}

/** Compact input log: per input, tick delta (canonical base 36) + action letter A..G. */
export function packInputs(inputs: readonly (readonly [number, number])[]): string {
  let prev = 0;
  return inputs
    .map(([t, a]) => {
      const d = t - prev;
      prev = t;
      return b36(d) + ACTION_LETTERS[a]!;
    })
    .join("");
}
export function unpackInputs(s: string): [number, number][] | null {
  if (!/^[0-9a-zA-G]*$/.test(s)) return null;
  const out: [number, number][] = [];
  const re = /([0-9a-z]+)([A-G])/g;
  let t = 0;
  let consumed = 0;
  for (let m = re.exec(s); m; m = re.exec(s)) {
    if (m.index !== consumed) return null;
    const d = unb36(m[1]!);
    if (d === null) return null;
    t += d;
    out.push([t, ACTION_LETTERS.indexOf(m[2]!)]);
    consumed = re.lastIndex;
  }
  return consumed === s.length ? out : null;
}

/* ---------------- challenge codes ---------------- */

export function encodeChallenge(ruleset: Sr1RulesetId, seed: string, engineVersion: number, h: HashString): string {
  if (!seedOk(ruleset, seed)) throw new Error("bad ruleset/seed");
  const body = ["SR1C", ruleset, `e${engineVersion}`, seed].join(".");
  return `${body}.${checkOf(body, h)}`;
}

export type DecodeError = "size" | "chars" | "format" | "fields" | "check" | "engine" | "ruleset_or_seed" | "platform"
  | "numbers" | "hash" | "player" | "link" | "log";

export function decodeChallenge(code: unknown, h: HashString):
  | { ok: true; ruleset: Sr1RulesetId; engine: number; seed: string }
  | { ok: false; error: DecodeError } {
  const cl = clean(code);
  if ("error" in cl) return { ok: false, error: cl.error };
  const f = cl.code.split(".");
  if (f[0] !== "SR1C") return { ok: false, error: "format" };
  if (f.length !== 5) return { ok: false, error: "fields" };
  if (!checkOk(f, h)) return { ok: false, error: "check" };
  const eng = ENGINE_RE.exec(f[2]!);
  if (!eng) return { ok: false, error: "engine" };
  if (!seedOk(f[1]!, f[3]!)) return { ok: false, error: "ruleset_or_seed" };
  return { ok: true, ruleset: f[1] as Sr1RulesetId, engine: Number(eng[1]), seed: f[3]! };
}

/* ---------------- result codes ---------------- */

export interface Sr1Result {
  platform: Sr1Platform;
  ruleset: Sr1RulesetId;
  engine: number;
  seed: string;
  ticks: number;
  score: number;
  lines: number;
  level: number;
  hash: string;
  player: string;
  link: string | null;
  inputs: [number, number][];
}

export function encodeResult(r: Sr1Result, h: HashString): string {
  if (!SR1_PLATFORMS.includes(r.platform)) throw new Error("platform");
  if (!seedOk(r.ruleset, r.seed)) throw new Error("ruleset/seed");
  if (!nameOk(r.player)) throw new Error("player");
  const player = toHex(r.player);
  if (r.link !== null && !LINK_RE.test(r.link)) throw new Error("link");
  const body = [
    "SR1R", r.platform, r.ruleset, `e${r.engine}`, r.seed, b36(r.ticks), b36(r.score), b36(r.lines), b36(r.level),
    r.hash.toLowerCase(), player, r.link ?? "-", packInputs(r.inputs),
  ].join(".");
  return `${body}.${checkOf(body, h)}`;
}

/** Decoding only. Nothing in a result code is trusted until importResult has replayed it. */
export function decodeResult(code: unknown, h: HashString): ({ ok: true } & Sr1Result) | { ok: false; error: DecodeError } {
  const cl = clean(code);
  if ("error" in cl) return { ok: false, error: cl.error };
  const f = cl.code.split(".");
  if (f[0] !== "SR1R") return { ok: false, error: "format" };
  if (f.length !== 14) return { ok: false, error: "fields" };
  if (!checkOk(f, h)) return { ok: false, error: "check" };
  if (!(SR1_PLATFORMS as readonly string[]).includes(f[1]!)) return { ok: false, error: "platform" };
  const eng = ENGINE_RE.exec(f[3]!);
  if (!eng) return { ok: false, error: "engine" };
  if (!seedOk(f[2]!, f[4]!)) return { ok: false, error: "ruleset_or_seed" };
  const [ticks, score, lines, level] = [f[5]!, f[6]!, f[7]!, f[8]!].map(unb36);
  if (ticks == null || score == null || lines == null || level == null) return { ok: false, error: "numbers" };
  if (!/^[0-9a-f]{8}$/.test(f[9]!)) return { ok: false, error: "hash" };
  const player = f[10]!.length >= 2 && f[10]!.length <= 128 ? fromHex(f[10]!) : null;
  if (player === null || !nameOk(player)) return { ok: false, error: "player" };
  const link = f[11]!;
  if (link !== "-" && !LINK_RE.test(link)) return { ok: false, error: "link" };
  const inputs = unpackInputs(f[12]!);
  if (!inputs || inputs.some(([t]) => t > ticks)) return { ok: false, error: "log" };
  return {
    ok: true, platform: f[1] as Sr1Platform, ruleset: f[2] as Sr1RulesetId, engine: Number(eng[1]), seed: f[4]!,
    ticks, score, lines, level, hash: f[9]!, player, link: link === "-" ? null : link, inputs,
  };
}

/* ---------------- server import (spec §6.4) ---------------- */

export interface ImportDeps {
  hashString: HashString;
  /** src/lib/match/rules.ts verifyLog */
  verifyLog: (i: {
    log: { v: number; seed: string; startLevel: number; ticks: number; inputs: [number, number][] };
    seed: string; timeCapMs: number; elapsedMs: number;
  }) => { ok: boolean; reasons: string[]; final: unknown | null; score: number; lines: number; level: number; hash: string | null; toppedOut: boolean };
}

/** The run itself, independent of who claims it. Store SHA-256(runKey) as UNIQUE (spec §6.5). */
export function runKey(r: Pick<Sr1Result, "seed" | "ticks" | "inputs">): string {
  return `${r.seed}.${b36(r.ticks)}.${packInputs(r.inputs)}`;
}

/**
 * challenge: the server's own record of the challenge being answered (never taken from the code):
 * createdAtMs / closesAtMs (a Daily: 00:00 UTC of its date / 24 h later). nowMs: the server clock.
 */
export function importResult(
  code: unknown,
  challenge: { ruleset: Sr1RulesetId; seed: string; createdAtMs: number; closesAtMs: number },
  nowMs: number,
  deps: ImportDeps,
) {
  const r = decodeResult(code, deps.hashString);
  if (!r.ok) return { decode: r.error } as const;
  const out: Record<string, unknown> = {
    decode: "ok", platform: r.platform, ruleset: r.ruleset, engine: r.engine, seed: r.seed, player: r.player,
    link: r.link, ticks: r.ticks, inputs: r.inputs.length,
    claimed: { score: r.score, lines: r.lines, level: r.level, hash: r.hash },
  };
  if (r.ruleset !== challenge.ruleset) {
    out.verify = { ok: false, reasons: ["ruleset_mismatch"] };
    return out;
  }
  if (nowMs > challenge.closesAtMs) {
    out.verify = { ok: false, reasons: ["expired"] };
    return out;
  }
  const elapsedMs = nowMs - challenge.createdAtMs;
  const v = deps.verifyLog({
    log: { v: r.engine, seed: r.seed, startLevel: 1, ticks: r.ticks, inputs: r.inputs },
    seed: challenge.seed, timeCapMs: SR1_RULESETS[challenge.ruleset].timeCapMs, elapsedMs,
  });
  const reasons = [...v.reasons];
  const verify: Record<string, unknown> = { ok: false, reasons };
  if (v.final) {
    if (v.score !== r.score || v.lines !== r.lines || v.level !== r.level) reasons.push("claim_mismatch");
    if (v.hash !== r.hash) reasons.push("hash_mismatch");
    Object.assign(verify, { score: v.score, lines: v.lines, level: v.level, hash: v.hash, toppedOut: v.toppedOut });
  }
  verify.ok = reasons.length === 0;
  out.verify = verify;
  out.verification = verify.ok ? "server_verified" : "rejected";
  return out;
}
