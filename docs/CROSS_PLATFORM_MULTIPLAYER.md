# StackRivals cross-platform multiplayer (shared spec, v1)

This file is shared between the WoW addon project and the stackrivals.io project. It says what
is possible, what is built, what is not possible, and which formats both sides use. There is
**one** multiplayer architecture: the same engine (parity-tested), the same seeds, the same input
log, the same verification and the same result vocabulary on every platform.

Status words: **BUILT** (code + automated tests), **SIMULATED** (tested only in a simulated WoW),
**CLIENT TESTED** (ran in real WoW clients), **PLANNED**, **NOT POSSIBLE** (with the reason).

## 1. Conclusions first

| Connection | Real-time 1v1? | Status | Why |
|---|---|---|---|
| WoW Forever ↔ WoW Forever (same/connected realms) | **Yes** | BUILT, SIMULATED (needs a two-client test: docs/MULTIPLAYER_TEST.md) | Blizzard addon messages (whisper/guild/party) |
| WoW Retail ↔ Retail, Classic ↔ Classic | **Yes** | BUILT (same code), SIMULATED | Same API; each client is its own game world |
| WoW Forever ↔ WoW Retail / Classic | **No** | NOT POSSIBLE in real time | Separate game services; addon messages never cross game versions |
| Web ↔ Web | **Yes** | Exists on stackrivals.io (Quick Match, challenges, server-verified) | Supabase Realtime + server replay |
| WoW ↔ Web (or apps) live | **No** | NOT POSSIBLE with allowed methods | §4 |
| WoW ↔ Web/apps **asynchronous** (same seed, copy/paste codes) | Yes, not live | Format + Lua codec + shared vectors + TS reference **BUILT**; addon UI and web import PLANNED | §6 |
| Shared Daily (same pieces for everyone each UTC day) | Yes, not live | WoW Daily Blitz BUILT; web side PLANNED | §6.7 |
| Web ↔ Windows/Chrome/mobile apps | Yes | PLANNED (web stack) | Same web backend and engine |

**Order of work:** (1) native WoW guild duels, (2) asynchronous WoW↔web challenges,
(3) shared Daily + server replay, (4) shared account/statistics where technically possible,
(5) real-time only if a safe, allowed, documented method appears (none exists today).

## 1b. Spell Battle (branch `spellbattle`, v0.5.0 preview)

0.5 also changes the pause rule for duels between two 0.5 clients: a pause pauses both runs, both
resume together, and each player may pause for 60 s in total (`PSE`, `RSM`). Both PCs confirm the
result (`VER`), and a disagreement is "disputed", not counted. Details: `docs/SPELL_BATTLE.md` §4.

Spell Battle from Play 2.0 is BUILT and SIMULATED for **WoW ↔ WoW** duels (ruleset `s180`) and for
vs Bot. Details, the protocol additions (`RDY`/`GO` loadout, `SP`, cast letters `H`–`P`), the result
rule (both logs replayed in lockstep = the web's `verifySpellMatch`) and what needs real clients:
`docs/SPELL_BATTLE.md`. Findings and an SR1 proposal for the web: `docs/WEB_SPELL_REPORT.md`.

## 2. What is built in the addon (branch `multiplayer`, v0.4.0 preview)

A 1v1 **score race on a shared seed**: both players get the same pieces and play for a fixed time;
the higher score wins. Nothing about the board is sent. Each player plays locally, and the addons
exchange a few small messages.

- **Rulesets:** `b120` = 2:00, 3 s countdown. `r180` = 3:00, 4 s countdown = the web 1v1 time cap
  and countdown (fingerprinted against `src/lib/match/rules.ts`).
- **Seed (commit-reveal):** `srduel-<mid>-<nonceA><nonceB>`. The challenger sends only
  `commitA = FNV-1a("srcommit-<mid>-<nonceA>")` in the invite; the accepter picks nonceB without
  knowing nonceA; the challenger reveals nonceA in GO and the accepter checks it against commitA.
  Neither player can choose or grind the pieces; the accepter learns the seed only at GO.
- **Flow:** find players (one guild/group broadcast, answers by whisper) → INV → ACC → both press
  Ready (RDY) → GO → score every 2 s (SC) → END + input log (LOG chunks) → each side replays the
  rival's log → FIN ("I have your result") → result → Rematch.
- **Delivery:** a successful `SendAddonMessage` only means *accepted into the client's queue*,
  never *delivered* (warcraft.wiki.gg). So nothing trusts a send: state messages repeat until the
  rival's next state shows they arrived; results repeat until the rival's FIN; a declined or
  cancelled match keeps answering late messages with DEC (a lost DEC can never re-open a popup);
  log chunks that arrive early are kept; chunks are re-requested (RQ) only when the stream stalls.
  Re-sent messages replace each other in the send queue instead of piling up.
- **Timeouts:** invite 30 s; lobby 60 s host / 75 s guest (the host always decides first);
  silence: warning at 20 s, "gone" at 35 s (cleared as soon as the rival is heard again); rival log
  60 s after both runs ended; hard deadline = limit + 5 min. Simultaneous challenges between the
  same two players become one duel (the lower match id wins).
- **Results:**

  | Outcome | When |
  |---|---|
  | win / loss / draw by score | the rival's log replayed to exactly their claimed score, lines and hash (`peer_checked`) |
  | win | the rival's log fails the replay check, or their result arrived faster than the game can be played (10 s margin) |
  | win | the rival forfeited, disconnected or went offline during play, or didn't finish by the deadline |
  | no result | the rival's log never fully arrived: a claimed score alone never decides a winner |
  | loss | you forfeited during play (both forfeited: draw, web rule) |
  | no result (you) | you left after your own run ended; your result still reaches the rival |
  | no result | the rival left after their run ended, but their result never arrived (60 s) |
  | cancelled | declined, busy, offline, other version, timeout, or a GO nonce that doesn't match the commitment; a guest that cancels before it ever played (lost GO) cancels for both |

  A challenged Trial/Veteran account can't send anything, so the challenger sees "didn't answer".
  The "too fast" check measures from the earliest moment the rival can have started (host: when it
  sent GO; guest: when it sent Ready), so a late GO never makes an honest result look too fast.

- **Safety and UX:** whispers only during a match. Combat pauses your own run (also when GO
  arrives in combat); a duel that starts while you type in chat starts paused. Nothing protected
  is called. "Forfeit duel" needs a second click within 3 s. Unsolicited replies (hello, busy) are
  rate-limited per player and low priority, so spam can't starve a duel. Whispering an offline
  rival stops at once; the server's "No player named ..." line is hidden for the exact player we
  just whispered (bare name only on our own realm), and an offline report only ends a match after
  6 s without any message from the rival.
- **Diagnostics:** the last 5 duels are kept in SavedVariables (`duelDiag`): counters per message
  kind, send result codes, drops, longest silence, queue peak and a compact event log;
  `/sr duel debug` shows the live state. See docs/MULTIPLAYER_TEST.md.

### Wire protocol v1 (addon prefix `StackRivals`)

Plain printable ASCII, `:`-separated, at most 255 bytes, base-36 numbers.

| Message | Fields | Sent |
|---|---|---|
| `1:HEL` | addonVersion, engineVersion | guild/party broadcast on *Find players* (max once per 20 s) |
| `1:HI` | addonVersion, engineVersion, busy(0/1) | whisper reply (max once per 10 s per player) |
| `1:INV` | mid, ruleset, engineVersion, commitA (8 hex) | challenge (re-sent every 4 s while waiting) |
| `1:ACC` | mid, nonceB | accept (re-sent in the lobby) |
| `1:DEC` | mid, reason (`no busy combat version timeout cancel ruleset`) | decline / cancel; repeated for late messages about a closed match |
| `1:RDY` / `1:PNG` | mid | ready / keep-alive |
| `1:GO` | mid, nonceA | start (host); reveals nonceA; re-sent until the guest's first score |
| `1:SC` | mid, tick, score, lines, over | every 2 s while playing |
| `1:END` | mid, ticks, score, lines, level, hash, chunkCount | when your run ends; re-sent until FIN |
| `1:LOG` | mid, i, n, payload | input-log chunk (≤ 200 chars) |
| `1:RQ` | mid, i | ask again for chunk i (only when the stream stalled) |
| `1:FIN` | mid | "I have your END and complete log": stop re-sending |
| `1:BYE` | mid, reason (`forfeit` during play, `left` after your own run ended; also `quit timeout combat`) | leave |

**Version rule:** `<v>:DEC:<mid>:<reason>` keeps this exact shape in every protocol version. A
client that receives an invite with another protocol version answers `<their v>:DEC:<mid>:version`,
so the inviter learns "different version" at once.

**Log payload:** per input, the tick delta from the previous input in base 36 (no leading zeros)
followed by the action letter `A`–`G` (index into `left,right,rotateCW,rotateCCW,softDrop,hardDrop,hold`).
About 3 bytes per input; a 2:00 duel is roughly 1–3 KB in 5–15 chunks. The same codec is used in
the SR1 result code (§6).

### Traffic (simulated, measured by the tests)

A 2:00 duel: about **60 messages per player** (149 for both), peak **6 per second**. Our pacing:
broadcasts burst 4 then 1 per 2 s; whispers burst 8 then 2 per second, 0.8 per second inside
instances (where whispers count against the per-prefix limit). Tests assert ≤ 110 messages per
player per duel and ≤ 8 in any second, and zero throttles inside instances.

### WoW facts this relies on (warcraft.wiki.gg, checked 29 Oct 2026)

- `C_ChatInfo.SendAddonMessage(prefix, msg, chatType, target)`: prefix ≤ 16 characters, message ≤
  255. Returns `Enum.SendAddonMessageResult` (since 10.2.7 Retail / 4.4.0 Classic): 0 Success,
  1 InvalidPrefix, 2 InvalidMessage, 3 AddonMessageThrottle, 4 InvalidChatType, 5 NotInGroup,
  6 TargetRequired, 7 InvalidChannel, 8 ChannelThrottle, 9 GeneralError, 10 NotInGuild (11.1.0),
  11 AddOnMessageLockdown (12.0.0), 12 TargetOffline (12.0.0). **The code is the last return value**
  (a deprecation wrapper put a boolean first on some clients); older clients return a boolean. The
  addon reads the last numeric value and treats booleans and Lua errors safely.
- **Success = queued, not delivered** (see Delivery above).
- Per-prefix throttle: 10 messages, +1 per second; whispers outside instances are exempt. The
  server can change this at any time.
- `RegisterAddonMessagePrefix` returns 0 Success, 1 DuplicatePrefix, 2 InvalidPrefix,
  3 MaxPrefixes. **Registrations are lost on `/reload`**: the addon registers on every
  `PLAYER_LOGIN` (which also fires after a reload).
- Whispers work on the same realm and connected realms. Cross-faction is not documented.
- Offline target: chat whispers print `ERR_CHAT_PLAYER_NOT_FOUND_S` ("No player named '%s' is
  currently playing."); addons hide it with a `CHAT_MSG_SYSTEM` message filter. The wiki's
  SendAddonMessage page says an **addon** whisper prints "Player is offline." instead. Which text
  appears is checked in the two-client test; offline detection also works without it (code 12 on
  12.x, and silence after 35 s everywhere).
- **Trial and Veteran accounts can't send addon messages** (Forever 1.60.1 beta, Retail 12.1.7).
  The addon detects `IsTrialAccount()`/`IsVeteranTrialAccount()` and says so instead of failing silently.
- **To verify in real clients:** sender name format, own guild echo, when code 12 is returned,
  whether the chat-filter API exists under that name in Forever/12.x, cross-faction and
  connected-realm behaviour, lockdown situations. Until then the duel status is SIMULATED.

## 3. Result trust levels (shared vocabulary)

| `verification` | Meaning | Where |
|---|---|---|
| `local` | One client's score, checked by nobody | WoW solo records |
| `peer_checked` | The opponent's addon replayed the log with the shared seed and got the same score and hash, and found no impossible input | WoW duels |
| `server_verified` | stackrivals.io replayed the log on the server (`verifyLog`) and every claim matched | Web matches; WoW results imported via §6 |
| `rejected` | A replay found a problem (reasons attached); stored for audit, never ranked | Any platform |

A peer check catches a tampered score or log. It cannot prove that the opponent's addon wasn't
modified, because both clients are controlled by players. So **ranked rewards and global
leaderboards use only `server_verified` results.**

## 4. Crossplay: what is possible without bending Blizzard's rules

WoW addons run in a sandbox with **no sockets, HTTP, files or processes**. Ways data can move:

| Option | Direction / latency | Allowed? | Verdict |
|---|---|---|---|
| **Copy/paste codes** (SR1, §6): the addon shows a code in a text box, the player copies it to the website (and pastes challenge codes into the addon) | both ways, manual, seconds | Yes: only the player's own keyboard | **Build this (P2).** The only verified-at-server bridge that needs nothing installed |
| **Battle.net OAuth on the website** (`wow.profile` scope, `/profile/user/wow` lists the account's characters) | web ↔ Blizzard, not the game | Yes: official Blizzard API | **Best account linking** (§6.8). Retail confirmed; Classic namespaces exist but have reported 403 issues; Forever's namespace is unknown until launch |
| **Desktop companion reading SavedVariables** after logout or `/reload` (like the WeakAuras Companion or the Raider.IO client) | WoW → web, only at reload/logout | Widely used pattern, read-only | Later (P3) as a convenience: uploads finished results with consent. Same trust as codes; not live |
| Companion writing a data file the addon reads at login | web → WoW, only at login/reload | Same pattern | Could deliver challenges or leaderboards; not live |
| Tailing the chat log file (`/chatlog`) or screen reading | WoW → web, near-live, one way | Grey zone; a program watching the game client | **Not recommended.** Fragile, one-way, and the way back would need simulated input, which is forbidden |
| Reading game memory, injecting input, intercepting traffic, automating play | — | **Forbidden** | Never |

**Result:** a two-way real-time match between WoW and the web cannot be built with allowed,
documented methods. We do not claim or advertise live crossplay. Real time stays inside each WoW
game world (WoW↔WoW duels) and inside the web (web↔web). The platforms meet asynchronously: the
same seeds, the same engine, the server replay, and one shared result record.

## 5. Shared match record (JSON, both platforms) — `stackrivals.match.v1`

What the website stores for every match or challenge result, whatever the platform:

```json
{
  "schema": "stackrivals.match.v1",
  "matchId": "wow:k3x9qa | web:<uuid> | chal:<challenge id>",
  "platform": "wow-forever | wow-retail | wow-classic | web | windows | android | ios | chrome",
  "mode": "duel | challenge | daily | solo",
  "ruleset": "b120 | r180 | daily120",
  "engineVersion": 1,
  "seed": "srduel-k3x9qa-ab12cd34ef56gh78 | srchal-7f3k2p9d01 | srwow-daily-2026-11-05",
  "startedAt": "2026-11-05T00:12:00Z",
  "endedAt": "2026-11-05T00:14:05Z",
  "players": [
    {
      "playerRef": "wow:Alice-Realm | web:<user id>",
      "account": "<web user id> | null",
      "accountLink": "battlenet | code | none",
      "score": 68046, "lines": 140, "level": 15, "ticks": 7200,
      "hash": "8f2a91c0",
      "log": { "v": 1, "seed": "...", "startLevel": 1, "ticks": 7200, "inputs": [[0, 5], [12, 0]] },
      "forfeited": false
    }
  ],
  "outcome": ["win", "loss"],
  "verification": "local | peer_checked | server_verified | rejected",
  "reasons": [],
  "source": "sr1-import | web-match | wow-duel"
}
```

- `log` is exactly the web's `SerializedInputLog`, so `replayLog`/`verifyLog` run it unchanged. The
  WoW compact log converts to it losslessly (`tools/sr1/sr1.ts` `unpackInputs`).
- Rulesets are identified by id **and** `engineVersion`; a record is only comparable with records
  of the same ruleset and engine version. When the engine version changes, old records are kept and
  shown separately (the addon already archives its records this way).
- WoW duels are stored locally in the addon (history of 20 with `rival, me, them, res, how, rs, d`);
  they reach the website only through a future SR1 import or companion, as `peer_checked`
  or after server replay as `server_verified`.

## 6. Asynchronous cross-platform challenges — format SR1

The same seed and rules on both platforms; results move as **copy/paste codes**. No network use
from WoW, fully allowed. The website replays every result itself, so imports are `server_verified`.

**Implementations:** Lua `StackRivals/Net/Codes.lua` (BUILT), TypeScript reference
`tools/sr1/sr1.ts` (BUILT, no imports: the web project may copy it), shared vectors
`docs/vectors/sr1.json` (12 challenge, 32 result vectors, 3 run-key pairs), checker
`tools/sr1/check_vectors.ts` (runs the TS reference with the web's real `verifyLog`; **77/77 pass at
web commit 29afe52**). A differential fuzz of 4,000 mutated codes gave identical Lua and TS verdicts. The addon UI (paste a challenge,
copy a result) is PLANNED for after the real client test.

### 6.1 Rulesets (ruleset id + engine version = the rules)

| id | timeCapMs | capTicks | countdownMs | startLevel | seed rule |
|---|---|---|---|---|---|
| `b120` | 120000 | 7200 | 3000 | 1 | `[a-z0-9-]{1,64}` |
| `r180` | 180000 | 10800 | 4000 | 1 | `[a-z0-9-]{1,64}` (= web 1v1) |
| `daily120` | 120000 | 7200 | 3000 | 1 | exactly `srwow-daily-YYYY-MM-DD`, a real calendar date (UTC) |

`capTicks = ceil(timeCapMs / 1000 × 60)`, exactly as `verifyLog`. Seeds are ASCII by definition:
the web's `hashString` hashes UTF-16 code units and Lua hashes bytes; they agree on ASCII only.
Web-created challenge seeds: `srchal-` + 10 random `[a-z0-9]`.

### 6.2 Challenge code

`SR1C.<ruleset>.e<engine>.<seed>.<check>` — e.g. `SR1C.b120.e1.srchal-7f3k2p9d.xxxxxxxx`

### 6.3 Result code

`SR1R.<platform>.<ruleset>.e<engine>.<seed>.<ticks36>.<score36>.<lines36>.<level36>.<hash>.<playerHex>.<link>.<log>.<check>`

| Field | Rule |
|---|---|
| platform | `wow-forever` \| `wow-retail` \| `wow-classic` |
| engine | `e` + decimal, no leading zeros, 1–4 digits |
| ticks36, score36, lines36, level36 | lowercase base 36, canonical (no leading zeros, `0` for zero), ≤ 9 chars |
| hash | 8 lowercase hex: claimed `hashState` of the final state |
| playerHex | lowercase hex of the UTF-8 bytes of `Name-Realm` as the addon reports it; 1–64 bytes, valid UTF-8 (a BOM is not removed). Name 2–12 letters; realm 1–40 letters, digits or `'` (spaces and hyphens removed, like `GetNormalizedRealmName`); exactly one `-`. Letters = A–Z, a–z, U+00C0–U+024F (not ×÷), Greek, Cyrillic, Hangul, CJK. This blocks control, zero-width, bidi and other invisible characters |
| link | `-` or a one-time link code `[A-Z0-9]{6,12}` (§6.8) |
| log | compact log (§2), canonical (re-encoding gives the same text); every input tick ≤ ticks; may be empty |
| check | 8 lowercase hex = FNV-1a 32 (`hashString`) of everything before `.<check>` |

Decoding: remove ASCII whitespace `[ \t\r\n\f\v]` (pasted codes get wrapped); anything else outside
printable ASCII `0x21–0x7E` → `chars` (e.g. a non-breaking space); then more than 32768 characters →
`size`; split on `.`; exact field count (5 / 14). Decode errors, in this order: `size chars format
fields check` then field errors `engine ruleset_or_seed platform numbers hash player link log`. **The check only catches typos** — anyone can recompute it.
Trust comes from the server replay, never from the code.

A 2:00 result is about 1.5–2.5 KB, a 3:00 result about 2.5–3.5 KB: fine for a paste box.

### 6.4 Server import algorithm (both implementations must give identical output)

Input: the pasted code, the server's own record of the challenge being answered (`ruleset`, `seed`,
`createdAtMs`, `closesAtMs` — **never taken from the code**; a Daily: 00:00 UTC of its date and 24 h
later; a web challenge: creation time and creation + `CHALLENGE_TTL_MS`), and the server clock `nowMs`.

1. Decode (§6.3). On error: reject with the decode error.
2. If the code's ruleset ≠ the challenge's ruleset: reject `ruleset_mismatch`.
3. If `nowMs > closesAtMs`: reject `expired` (boards close; old Daily seeds can't be farmed later).
4. `log = { v: engine, seed: codeSeed, startLevel: 1, ticks, inputs }`.
5. `v = verifyLog({ log, seed: challenge.seed, timeCapMs: RULESETS[ruleset].timeCapMs,
   elapsedMs: nowMs − createdAtMs })`.
   This yields `engine_mismatch`, `seed_mismatch`, `malformed_log`, `over_time_cap`,
   `faster_than_clock` (log longer than elapsed + 3 s), `inhuman_input_rate`, `inputs_after_topout`.
6. If `v.final` exists: append `claim_mismatch` if score, lines or level differ from the claim, then
   `hash_mismatch` if the hash differs.
7. No reasons → continue with §6.5 (run key, link); otherwise store `rejected` with the reasons
   (audit), never ranked.

`importResult` in `tools/sr1/sr1.ts` is this algorithm. The vectors pin its output, including the
order of reasons.

### 6.5 Duplicates and manipulation

- **One run, one owner:** `runKey = <seed>.<ticks36>.<log>` (`runKey()` in both implementations)
  identifies the run itself, whoever claims it. Store `SHA-256(runKey)` as UNIQUE: the first
  successful import owns the run; the same run under another name, platform or link is rejected
  (`duplicate_run`) and flagged for review. Player, platform and link are **not** protected by the
  check, so this is the only thing that stops someone re-wrapping another player's run.
- **One player, one challenge:** unique `(challengeId, playerRef)` for the *ranked* entry. A WoW
  player can retry a seed offline as often as they like, so async challenges are **best-attempt
  boards** for everybody (web players may retry too). Every import is kept for audit; the board
  shows the best `server_verified` score per player.
- **Re-using a code:** the seed binds a result to one challenge (`seed_mismatch` otherwise); the
  same run imported twice is caught by the run key.
- **Forged or edited codes:** replay → `claim_mismatch`, `hash_mismatch`, `over_time_cap`,
  `inhuman_input_rate`, `inputs_after_topout`.
- **Pre-computed or bot runs:** `faster_than_clock` only stops results that appear before the game
  could be played *after the challenge existed*. It does **not** stop runs prepared in advance when
  the seed is predictable: Daily seeds (`srwow-daily-<date>`) are public by design so WoW can play
  them offline, so a tool-assisted Daily run can be prepared days ahead and imported right after
  midnight. Daily boards are therefore fun boards, not ranked rewards. For anything ranked, use web
  challenges with an unpredictable seed (`srchal-` + server randomness, never derived from the
  date), closing times, linked accounts and the web's fraud checks. A bot playing in real time can't
  be told apart by replay alone on any platform.
- **Someone else's code:** without a link, the result is shown as `WoW: Name-Realm (unlinked)`
  and gives the importing web account nothing. A link code is **consumed by its first successful
  import** (it travels in plain text inside a result code, so it must not be reusable).
- **Names are claims:** `Name-Realm` in a code is whatever the code says. Only Battle.net OAuth
  (§6.8) proves character ownership; show unlinked names as unverified.
- Rate-limit imports per account and IP.

### 6.6 Verification status shown to players

`server_verified` = "Verified by StackRivals" · `peer_checked` = "Checked by your opponent's
addon" · `local` = "Not verified" · `rejected` = not shown on boards. Never say "verified" for a
WoW duel.

### 6.7 Shared Daily

Seed `srwow-daily-<UTC date>`, ruleset `daily120`, available 00:00–24:00 UTC. The addon already
plays it as Daily Blitz. The web generates the same seed for the same date (the engine is
parity-tested), so web and WoW players get identical pieces. WoW scores join the web Daily board via
an SR1 result code (`elapsedMs` counted from 00:00 UTC). There is no challenge code for a Daily: the
seed is implied by the date.

### 6.8 Account linking (later)

1. **Preferred: Battle.net OAuth on the website** (scope `wow.profile`, endpoint
   `/profile/user/wow`). Blizzard returns the account's characters, so ownership of `Name-Realm` is
   proven by Blizzard. Free Blizzard developer client needed (owner's decision). Classic/Forever
   availability must be checked at launch.
2. **Fallback: one-time link code.** The website shows `[A-Z0-9]{8}`; the player types
   `/sr link CODE` in WoW; the next result code carries it, and the first successful import consumes
   it. It shows that the person with the web account pasted that result; it proves nothing about who
   owns the character or who played. Label it "linked", never "verified identity".
3. Never passwords, tokens or Battle.net credentials through the addon or in codes.

### 6.9 Changing the format

Additions need a new format id (`SR2C`/`SR2R`). Both sides update the vectors together; the vectors
file is generated by the addon (`lua5.1 tests/sr1_vectors.lua > docs/vectors/sr1.json`) and must
pass `tools/sr1/check_vectors.ts` against the web engine before either side ships.

## 7. Fairness rules (all platforms)

- The same engine (`ENGINE_VERSION` must match; parity tests keep the TS and Lua engines identical).
- The same seed for both players, and the same time cap. Inputs are limited to 4 per tick and 80
  per second, inputs after top-out are rejected, and logs over the time cap are flagged.
- A forfeit always loses; both forfeiting is a draw. Equal scores are a draw (web `decideOutcome`).
- A result needs the full input log. A claimed score without a log never wins.
- A log that fails the replay, or arrives faster than the game can be played, loses / is rejected.
- Free and equal on every platform: no paid advantage, and web premium never gates WoW play
  (Blizzard add-on policy).

## 8. Roadmap

| Phase | Content | Depends on |
|---|---|---|
| P0 | Solo addon 0.3.x released for Forever | Owner's client test |
| P1 | Duels 0.4.0: two-client test (docs/MULTIPLAYER_TEST.md) → fixes → merge → release | Two paid WoW accounts, same realm/guild |
| P2 | Web: SR1 import page + challenge pages + shared Daily board (`server_verified`) | Web work; spec §6, vectors |
| P2 | Addon: paste a challenge code (`/sr code`), play it, copy the result code | After P1; codec already built |
| P2 | Account linking: Battle.net OAuth (preferred) or link codes | Web account system; Blizzard developer client |
| P3 | Guild leaderboard inside WoW (throttled guild broadcast of personal bests) | P1 |
| P3 | Optional desktop companion: upload finished results after `/reload` (consent, read-only) | P2 |
| — | Live WoW↔web, live Forever↔Retail | Not possible (§1, §4) |
