# Prompt for the Claude session working on stackrivals.io

**Til ejeren:** Kopiér alt under stregen ind i hjemmeside-Claudes chat. Vedhæft også disse tre filer
fra addon-repoet (branch `multiplayer`), så den har den præcise spec, koden og testvektorerne:
`docs/CROSS_PLATFORM_MULTIPLAYER.md`, `tools/sr1/sr1.ts` og `docs/vectors/sr1.json`.
Kan hjemmeside-Claude selv læse GitHub-repoet `Youngmoody1/Youngmoody1-stackrivals-wow-addon`,
er vedhæftning ikke nødvendig.

---

**StackRivals — shared multiplayer with the WoW addon (read before changing gameplay or match code)**

There is a World of Warcraft version of StackRivals (repo `Youngmoody1/Youngmoody1-stackrivals-wow-addon`,
branch `multiplayer`; **don't modify that repo**, coordinate through the owner). Its Lua engine is a
1:1 port of `src/game/engine` and is parity-tested against this repo: a rules fingerprint (every
gameplay constant, including the 1v1 match constants and `CLOCK_SLACK_MS`), 66 replayed games, PRNG
vectors and Daily sequences. **Current base: web commit `29afe52`, `ENGINE_VERSION = 1`: identical.**

The goal is **one** StackRivals multiplayer architecture for web, WoW and future apps: the same
engine, seeds, input log, verification and result vocabulary. The attached
`CROSS_PLATFORM_MULTIPLAYER.md` is the full spec; the essentials are repeated below.

### 0. Facts you must respect (never promise more)

- WoW addons have **no internet access**. A **live** match between WoW and the website is not
  possible with allowed methods. Never advertise live crossplay.
- WoW↔WoW duels exist in the addon. Their results are `peer_checked`, never `server_verified`, and
  must never feed ranked ratings or global leaderboards.
- The bridge is **asynchronous**: the same seed on both platforms, and results moved by copy/paste
  codes (format SR1) that **this server replays** → `server_verified`.
- The WoW addon must stay free. Web premium (Pro, shop, wallet) must never be required for anything
  a WoW player does.
- Never ask for Battle.net passwords or tokens, and never put them in codes or the addon.

### 1. Keep the engines in sync (always)

`src/game/engine/*`, `src/game/controls.ts` (HANDLING) and the constants in `src/lib/match/rules.ts`
(time cap, countdown, input limits, reconnect grace, clock slack) are a **shared contract**, as are
`hashString`, mulberry32, the bag shuffle, `SerializedInputLog` and `hashState`. If you change any:
bump `ENGINE_VERSION` when outcomes change, and put this **change report** in your final summary:

```
StackRivals web – change report for the WoW addon
Range: <old commit>..<new commit>   ENGINE_VERSION: <old> -> <new>
1. Gameplay rule changes (engine/controls): what, why, commit
2. New or changed modes (rules, time limits, seeds)
3. Match / 1v1 rule changes (rules.ts constants, winner rules, verification)
4. Visual identity changes (colours, logo, skins, fonts) with values
5. Features intentionally web-only
6. Anything that changes how scores compare across versions
7. SR1 / match-record format changes (should be none without a new format id)
```

### 2. Add the shared SR1 code module + vectors (do this first)

1. Copy `tools/sr1/sr1.ts` into this repo (suggested `src/lib/match/sr1.ts`). It has no imports;
   pass `hashString` (`src/game/engine/prng.ts`) and `verifyLog` (`src/lib/match/rules.ts`).
2. Copy `docs/vectors/sr1.json` into the test fixtures and add a test that, for every vector:
   - `decodeChallenge` gives `expect`;
   - `importResult(code, challenge, elapsedMs, { hashString, verifyLog })` deep-equals `expect`;
   - valid codes re-encode to the same text (whitespace removed).

   - `runKey(a) === runKey(b)` matches `same` for every entry in `runKeys`.

   This is exactly what the addon's `tools/sr1/check_vectors.ts` runs against this repo: **77/77
   pass at `29afe52`** (plus a 4,000-code differential fuzz with identical Lua/TS verdicts). Your
   test keeps it green from your side.
3. Rulesets (id + engine version = the rules):

   | id | timeCapMs | countdownMs | startLevel | seed |
   |---|---|---|---|---|
   | `b120` | 120000 | 3000 | 1 | `[a-z0-9-]{1,64}` |
   | `r180` | 180000 | 4000 | 1 | `[a-z0-9-]{1,64}` (= current 1v1) |
   | `daily120` | 120000 | 3000 | 1 | exactly `srwow-daily-YYYY-MM-DD`, a real date (UTC) |

   Seeds must be ASCII (`hashString` hashes UTF-16 units, Lua hashes bytes; equal only for ASCII).
4. Code formats (details and error names in the spec §6.2–6.3):
   - Challenge: `SR1C.<ruleset>.e<engine>.<seed>.<check>`
   - Result: `SR1R.<platform>.<ruleset>.e<engine>.<seed>.<ticks36>.<score36>.<lines36>.<level36>.<hash>.<playerHex>.<link>.<log>.<check>`
   - `check` = 8-hex FNV-1a (`hashString`) of everything before it; **typo detection only**.
   - Only ASCII whitespace is stripped; any other non-printable-ASCII character → `chars`.
   - The player name follows WoW rules (`nameOk`): no control, zero-width or bidi characters.

### 3. Server import (the only place a WoW score becomes `server_verified`)

Implement a server function (edge function / RPC; results are server-written, keep the existing
RLS style) that does exactly `importResult` (spec §6.4):

1. decode (reject on decode error);
2. load the challenge **from the database** (`ruleset`, `seed`, `createdAtMs`, `closesAtMs`; a Daily:
   00:00 UTC of its date and 24 h later); never trust the code's seed; reject `ruleset_mismatch`;
3. reject `expired` if `nowMs > closesAtMs`;
4. `verifyLog({ log: { v: engine, seed, startLevel: 1, ticks, inputs }, seed: challenge.seed,
   timeCapMs, elapsedMs: nowMs − createdAtMs })`;
5. append `claim_mismatch` (score/lines/level differ) then `hash_mismatch`, if `final` exists;
6. reasons → store as `rejected` (audit only). No reasons → check the run key (below), then store
   as `server_verified`.

`importResult(code, challenge, nowMs, deps)` in `sr1.ts` implements steps 1–5.

**Duplicates and abuse (must have):**
- **Run key:** `SHA-256(runKey(decoded))` UNIQUE. The first successful import owns the run; the same
  run under another name/platform/link → reject `duplicate_run` and flag it. Name, platform and link
  are not protected by the check, so without this anyone can re-wrap someone else's run.
- A best entry per `(challenge_id, player_ref)`; rate limits per account and IP.
- Async challenges are **best-attempt boards** for everyone (a WoW player can retry a seed offline).
- Daily seeds are predictable by design, so a run can be prepared in advance: **Daily boards are
  fun boards, never ranked rewards.** Anything ranked uses web challenges with unpredictable
  server-random seeds and closing times.
- A result without an account link shows as "WoW: Name-Realm (unlinked)", is clearly marked as an
  unverified name, and gives the importing account nothing.

### 4. Data: one shared match record

Store web matches, imports and challenges in a shape compatible with `stackrivals.match.v1`
(spec §5). At least: `platform` (`web | wow-forever | wow-retail | wow-classic | ...`), `ruleset`,
`engine_version`, `seed`, per player (`player_ref`, `account`, `account_link`, score, lines,
level, ticks, hash, log), `verification` (`local | peer_checked | server_verified | rejected`),
`reasons`, `source` (`web-match | sr1-import | wow-duel`). Only compare records with the same
ruleset **and** engine version. Rankings use `server_verified` only.

### 5. Pages and features (ask the owner before shipping each)

1. **Challenges:** any signed-in user can create a challenge (ruleset `b120` or `r180`; seed
   `srchal-` + 10 random `[a-z0-9]`). Show the `SR1C` code with a copy button, a "Play on the web"
   button (same seed), a field to paste a WoW `SR1R` result code, and the board with platform
   icons and verification labels.
2. **Shared Daily:** a web "Daily Blitz" (2:00, ruleset `daily120`, seed `srwow-daily-<UTC date>`)
   whose board mixes web runs and imported WoW codes. WoW players already have this mode.
3. **Labels:** `server_verified` = "Verified by StackRivals"; `peer_checked` = "Checked by the
   opponent's addon"; `local` = "Not verified". Never "verified" for a WoW duel.
4. **Copy for players:** "Play the same pieces in World of Warcraft or on the web, then compare."
   Never "play live against WoW players".

### 6. Later (owner decides): account linking

1. Preferred: **Battle.net OAuth** (scope `wow.profile`, `/profile/user/wow` lists the account's
   characters → proven ownership of `Name-Realm`). Needs a free Blizzard developer client; the
   owner must approve creating it. Check Classic/Forever namespace support at launch.
2. Fallback: a one-time link code `[A-Z0-9]{8}` on the profile; the player types `/sr link CODE`
   in WoW, and the next result code carries it. **Consume it on its first successful import** (it
   is visible in the code). It proves only who pasted the result, not who owns the character or
   who played: label "linked", never "verified identity".

### 7. What the WoW side needs back from you

- Confirmation of the SR1 formats (or proposed changes **before** implementing; a change means a
  new format id and regenerated vectors on both sides).
- The change report (§1) whenever gameplay or match rules change.
- Your test results for the vectors, and the URL/route of the import page when it exists, so the
  addon's "copy result code" screen can point players there.

### 8. Acceptance criteria

- All vectors pass in your test suite; existing web tests stay green.
- An imported valid code becomes `server_verified` with the replayed score; every invalid vector
  is rejected with exactly the expected reasons; the re-wrapped vector is rejected as `duplicate_run`
  when the original was imported first; an expired challenge rejects imports.
- No gameplay change without `ENGINE_VERSION` + change report; no live-crossplay claims; nothing
  about WoW requires payment.
