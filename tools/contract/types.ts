/**
 * StackRivals shared data contract, version 1 (DRAFT until agreed with stackrivals.io).
 * One set of names for the website (TypeScript) and the WoW addon (Lua). Field-by-field
 * documentation, the Lua side of each type and the compatibility rules:
 * docs/STACKRIVALS_WEB_INTEGRATION.md. Wire formats (what actually moves between the two):
 * SR1 (docs/CROSS_PLATFORM_MULTIPLAYER.md section 6), SR2 draft (docs/SR2_DRAFT.md),
 * SRL1 / SRP1 (docs/ACCOUNT_SYNC_HANDOFF.md, tools/contract/account.ts).
 * Types only (no runtime code): `tsc --noEmit tools/contract/types.ts` checks it.
 */

export const CONTRACT_VERSION = 1 as const;

// ---- identities --------------------------------------------------------------------------------
/** Where a player or result comes from. WoW values = SR1 platforms. */
export type Platform =
  | "web" | "windows" | "chrome" | "android" | "ios"
  | "wow-forever" | "wow-retail" | "wow-classic";

/** The website's account (the ONLY account). `accountId` = public ref, never an e-mail or secret. */
export interface AccountRef { accountId: string /* [a-z0-9_-]{4,40} */ }

/** A player as one platform knows them. WoW: the character "Name-Realm" (SR1 name rules). */
export type PlayerRef =
  | { platform: "web" | "windows" | "chrome" | "android" | "ios"; accountId: string }
  | { platform: "wow-forever" | "wow-retail" | "wow-classic"; character: string /* "Name-Realm" */; linkId: string | null };

/** WoW character <-> account binding, made by SRL1 + confirmed by SRP1 (website stores it). */
export interface AccountLink {
  accountId: string; platform: "wow-forever" | "wow-retail" | "wow-classic"; character: string;
  linkId: string /* [a-z0-9]{12}, chosen by the addon */; linkedAt: number /* unix s */;
}

// ---- rules -------------------------------------------------------------------------------------
/** Engine version = the rules (ENGINE_VERSION in both engines). Records only compare within one. */
export type EngineVersion = number; // 1..9999, currently 1

/**
 * Ruleset ids. SR1: b120 / r180 / daily120. Duels (WoW native protocol): b120 / r180 / s180.
 * Spell Battle vs Bot: "spellbot" (SR2 draft).
 */
export type Ruleset = "b120" | "r180" | "daily120" | "s180" | "spellbot";
export interface RulesetSpec {
  id: Ruleset; timeCapMs: number; capTicks: number; countdownMs: number; startLevel: 1; spells: boolean;
}
export const RULESETS: Record<Ruleset, RulesetSpec> = {
  b120: { id: "b120", timeCapMs: 120000, capTicks: 7200, countdownMs: 3000, startLevel: 1, spells: false },
  r180: { id: "r180", timeCapMs: 180000, capTicks: 10800, countdownMs: 4000, startLevel: 1, spells: false },
  daily120: { id: "daily120", timeCapMs: 120000, capTicks: 7200, countdownMs: 3000, startLevel: 1, spells: false },
  s180: { id: "s180", timeCapMs: 180000, capTicks: 10800, countdownMs: 4000, startLevel: 1, spells: true },
  spellbot: { id: "spellbot", timeCapMs: 180000, capTicks: 10800, countdownMs: 4000, startLevel: 1, spells: true },
};

/** What the player chose (names as shown in WoW 0.6.1; ids never change). */
export type GameMode =
  | "classic" /* Classic */ | "blitz" /* Time Trial */ | "daily" /* Daily Challenge */ | "spellbot" /* Spell Battle */
  | "duel" /* Duel 2:00 / 3:00 */ | "spellduel" /* Spell Duel */ | "quickduel" /* Quick Duel (Quickplay) */
  | "challenge" /* web challenge code (SR1C) */;

/** Seeds are ASCII [a-z0-9-]{1,64}. Daily: "srwow-daily-YYYY-MM-DD" (UTC). Web challenge: "srchal-" + 10. Duel: "srduel-<mid>-<nonces>". */
export type Seed = string;

/** Match id: "wow:<mid>" (duel, 6-10 [a-z0-9]), "web:<uuid>", "chal:<challenge id>". */
export type MatchId = string;

// ---- logs --------------------------------------------------------------------------------------
/** The web's SerializedInputLog: [tick, action] pairs, action 0-6 = left,right,rotateCW,rotateCCW,softDrop,hardDrop,hold. */
export interface InputLog { v: EngineVersion; seed: Seed; startLevel: 1; ticks: number; inputs: [number, number][] }
/** Spell casts inside a Spell Battle log: action 100-108 = the 9 spells (SR2 letters H-P). */
export interface SpellEvent { tick: number; spell: 100 | 101 | 102 | 103 | 104 | 105 | 106 | 107 | 108; landsAt?: number }
export type SpellEvents = SpellEvent[];

// ---- results -----------------------------------------------------------------------------------
/** How far a result can be trusted. Only "server_verified" may rank or reward. */
export type MatchVerification =
  | "local"           // this PC only (SavedVariables): never trusted
  | "peer_checked"    // WoW duel: the other PC replayed it
  | "server_verified" // the website replayed the log (SR1 / SR2 import, web match)
  | "rejected";       // a replay or check failed (kept for audit, never ranked)

export interface PlayerResult {
  player: PlayerRef; score: number; lines: number; level: number; ticks: number; hash: string /* 8 hex */;
  log: InputLog | null; spells?: SpellEvents; forfeited: boolean;
}
export interface MatchResult {
  schema: "stackrivals.match.v1";
  matchId: MatchId; platform: Platform; mode: GameMode; ruleset: Ruleset; engineVersion: EngineVersion; seed: Seed;
  startedAt: string | null; endedAt: string | null;
  players: PlayerResult[];
  outcome: ("win" | "loss" | "draw" | "void")[];
  /** WoW duels: what a verdict rests on (VER basis); the web: "replay" for a server replay. */
  basis: "replay" | "rejected" | "forfeit" | "timeout" | "void";
  verification: MatchVerification;
  reasons: string[];
  source: "sr1-import" | "sr2-import" | "web-match" | "wow-duel";
}

// ---- profiles ----------------------------------------------------------------------------------
/** The website's profile as shown in WoW (from SRP1). Display only, never authoritative in WoW. No Shards / currencies. */
export interface ProfileSnapshot {
  linkId: string; player: string; accountId: string; name: string; issued: number; expires: number;
  level: number; xp: number; xpNext: number; rank: string | null; season: string | null; seasonPct: number;
  wins: number; losses: number; draws: number;
  history: { mode: string; res: "w" | "l" | "d"; my: number; their: number; at: number }[];
  achUnlocked: number | null; achTotal: number | null; cosOwned: number | null; cosEquipped: string | null; sig: string | null;
}
/** A StackRivals account profile (the website's; `linked` = this WoW character has a confirmed link). */
export interface PlayerProfile {
  v: 1; profileId: string | null; displayName: string | null; rank: string | null; level: number | null; xp: number | null;
  wins: number; losses: number; linked: boolean;
}
/** One WoW character as one addon tells another (PRF). Self-reported except name/realm. */
export interface CharacterProfile {
  v: 1; name: string; realm: string; faction: "Alliance" | "Horde" | "Neutral" | null; race: string | null; class: string | null;
  level: number | null; duelWins: number; duelLosses: number; chat: boolean; source: "wow-api" | "self-reported";
}

// ---- Quickplay, invitations, chat --------------------------------------------------------------
export type QuickplayAdapterStatus = "available" | "unavailable" | "not_connected";
export interface MatchmakingStatus {
  v: 1; state: "idle" | "searching" | "matched" | "none"; mode: "b120" | "s180"; startedAt: number | null;
  reach: { guild: boolean; group: boolean; friends: number };
  adapters: { native: QuickplayAdapterStatus; web: QuickplayAdapterStatus };
  note: "no_opponent" | "fell_through" | "cancelled" | "you_not_ready" | null;
}
/** Quickplay events, in order: searching -> matched -> lobby (ready check) -> countdown -> playing -> result. */
export type MatchmakingEvent =
  | { type: "search_started"; mode: "b120" | "s180" } | { type: "search_cancelled" } | { type: "no_opponent" }
  | { type: "matched"; matchId: MatchId; rival: PlayerRef } | { type: "fell_through"; rival: PlayerRef }
  | { type: "ready"; who: "me" | "rival" } | { type: "countdown" } | { type: "started" }
  | { type: "result"; result: MatchResult } | { type: "rematch_requested"; by: "me" | "rival" };
export interface MatchInvitation {
  v: 1; matchId: MatchId; ruleset: "b120" | "r180" | "s180"; engineVersion: EngineVersion; from: PlayerRef; to: PlayerRef;
  quickplay: boolean; rematch: boolean; commit: string /* seed commitment */;
}
export type ReadyState = "invited" | "lobby" | "ready" | "playing" | "waiting" | "done" | "cancelled";
export interface MatchChatMessage { v: 1; matchId: MatchId; n: number; from: PlayerRef; kind: "text" | "quick"; text: string; quickCode: 1 | 2 | 3 | 4 | null }
export type RematchRequest = MatchInvitation & { rematch: true };
