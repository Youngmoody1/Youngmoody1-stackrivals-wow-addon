# StackRivals cross-platform multiplayer (shared spec, v1)

This file is shared between the WoW addon project and the stackrivals.io project. It says what
is possible, what is built, what is not possible, and which formats both sides use.

Status words used here: **BUILT** (code exists and has automated tests), **SIMULATED** (tested
only in a simulated WoW), **PLANNED**, **NOT POSSIBLE** (with the reason).

## 1. Conclusions first

| Connection | Real-time 1v1? | Status | Why |
|---|---|---|---|
| WoW Forever ↔ WoW Forever (same/connected realms) | **Yes** | BUILT, SIMULATED (needs a two-client test) | Blizzard addon messages (whisper/guild/party) |
| WoW Retail ↔ Retail, Classic ↔ Classic (same client) | **Yes** | BUILT (same code), SIMULATED | Same API; each client is its own game world |
| WoW Forever ↔ WoW Retail / Classic | **No** | NOT POSSIBLE in real time | Separate game services; addon messages never cross game versions |
| Web ↔ Web | **Yes** | Exists on stackrivals.io (Quick Match, challenges, server-verified) | Supabase Realtime + server replay |
| WoW ↔ Web (or apps) live | **No** | NOT POSSIBLE with allowed methods | See §4 |
| WoW ↔ Web/apps **asynchronous** (same seed, result codes) | Yes, not live | PLANNED, spec in §6 | Copy/paste codes; server replays the log |
| Web ↔ Windows/Chrome/mobile apps | Yes | PLANNED (web stack) | Same web backend and engine |

**Recommendation:** ship WoW↔WoW duels (A) first. Make **asynchronous cross-platform
challenges (C)** the bridge to the web, because the web server can verify them by replay. Do not
build or promise a live WoW↔web bridge (B).

## 2. What is built in the addon (branch `multiplayer`, v0.4.0 preview)

A 1v1 **score race on a shared seed**: both players get the same pieces and play for a fixed time,
and the higher score wins. Nothing is sent about the board. Each player plays locally, and the
addons exchange a few small messages.

- **Rulesets:** `b120` is Blitz 2:00 (3 s countdown). `r180` is 3:00 with a 4 s countdown, which
  is the web 1v1 time cap and countdown (fingerprinted against `src/lib/match/rules.ts`).
- **Seed (commit-reveal):** `srduel-<matchId>-<nonceA><nonceB>`. The challenger sends only a hash
  of nonceA in the invite; the accepter picks nonceB without knowing nonceA; the challenger reveals
  nonceA at GO, and the accepter checks it against the hash. Neither player can choose or grind the
  pieces, and the accepter only learns the seed when the countdown starts.
- **Flow:** find players (one broadcast to guild/group, answers by whisper) → INV → ACC → both
  press Ready (RDY) → GO → score heartbeat every 2 s (SC) → END + input log (LOG chunks) → each side
  replays the rival's log → result → Rematch.
- **Robustness:** every state re-sends what the rival needs; re-sent messages replace each other in
  the send queue instead of piling up. Handlers are idempotent, log chunks that arrive before their
  END are kept, stalled chunks are re-requested (RQ, also while still playing), and after the result
  each side keeps serving its END and log for 60 s, even after going back to the menu. Timeouts: no
  answer (30 s), lobby (60 s host, 75 s guest, so the host always decides first), silence (warn at
  20 s, gone at 35 s, cleared as soon as the rival is heard again), the log (60 s after both runs
  ended) and the hard deadline (limit + 5 min). Players who challenge each other at the same moment
  get one duel (the lower match id wins).
- **Results:**
  | Outcome | When |
  |---|---|
  | win / loss / draw by score | the rival's log replayed to exactly their claimed score and hash (`peer_checked`) |
  | win | the rival's log fails the replay check (their result is rejected), or it arrived faster than the game can be played (web `faster_than_clock`, 10 s margin) |
  | win | the rival forfeited, disconnected or went offline during play, or didn't finish by the deadline |
  | no result | the rival's log never fully arrived: a claimed score alone never decides a winner |
  | loss | you forfeited during play (both forfeited: draw) |
  | no result (you) | you left after your own run ended; your result still reaches the rival |
  | cancelled | declined, busy, offline, version mismatch, timeout, or a seed that doesn't match the invite's commitment |
- **Safety:** messages are whisper-only during a match. Combat pauses only your own run (also when
  GO arrives during combat). Nothing protected is called, so nothing is blocked in combat. Quitting
  a running duel is always a labelled forfeit. Unsolicited replies (hellos, "busy") are rate-limited
  per player and low-priority, so spam can't starve a running duel. Whispering an offline rival
  stops at once; the server's "No player named ..." line is hidden for players we just whispered
  (chat-filter API from memory, guarded, not yet client-verified).

### Wire protocol v1 (addon prefix `StackRivals`)

Plain printable ASCII, `:`-separated, at most 255 bytes, base-36 numbers.

| Message | Fields | Sent |
|---|---|---|
| `1:HEL` | addonVersion, engineVersion | guild/party broadcast when you press *Find players* (max once per 20 s) |
| `1:HI` | addonVersion, engineVersion, busy(0/1) | whisper reply |
| `1:INV` | mid, ruleset, engineVersion, commitA (8 hex, FNV-1a of `srcommit-<mid>-<nonceA>`) | challenge (re-sent every 4 s while waiting) |
| `1:ACC` | mid, nonceB | accept (re-sent in the lobby) |
| `1:DEC` | mid, reason (`no busy combat version timeout cancel ruleset`) | decline/cancel (also right after GO, if the guest never started) |
| `1:RDY` / `1:PNG` | mid | ready / keep-alive |
| `1:GO` | mid, nonceA | start (host); reveals nonceA; re-sent until the guest's first score arrives |
| `1:SC` | mid, tick, score, lines, over | every 2 s while playing |
| `1:END` | mid, ticks, score, lines, level, hash, chunkCount | when your run ends (re-sent) |
| `1:LOG` | mid, i, n, payload | input-log chunk (≤ 200 chars) |
| `1:RQ` | mid, i | ask again for chunk i |
| `1:BYE` | mid, reason (`forfeit` during play, `left` after your own run ended; also `quit timeout combat`) | leave |

**Log payload:** for each input, the tick delta in base 36 (`0-9a-z`) followed by the action letter
`A`–`G` (index into `left,right,rotateCW,rotateCCW,softDrop,hardDrop,hold`). That is about 3 bytes
per input, so a full 2:00 duel is roughly 1–3 KB in 5–15 chunks.

### Traffic

A measured simulated 2:00 duel used **147 messages in total** (both players). That is about
0.7 messages per second per player, under Blizzard's per-prefix limit of 10 messages plus
1 per second. Our own pacing: broadcasts get a burst of 4 and then 1 every 2 s. Whispers get a
burst of 8 and then 2 per second, or 0.8 per second inside instances, where whispers count against
the limit. `SendAddonMessageResult` codes are handled: throttle, lockdown and general error are
retried with back-off. Offline, not-in-guild and not-in-group make the duel give up.

### WoW facts this relies on (warcraft.wiki.gg)

- `C_ChatInfo.SendAddonMessage(prefix, msg, chatType, target)`: prefix ≤ 16 characters, message ≤ 255
  characters. Chat types are `PARTY RAID INSTANCE_CHAT GUILD OFFICER WHISPER`, plus `CHANNEL`
  on Retail and `SAY`/`YELL` on Classic.
- Receivers must call `C_ChatInfo.RegisterAddonMessagePrefix`. Messages arrive in `CHAT_MSG_ADDON`
  as prefix, text, channel, sender, and so on.
- The throttle is per prefix: 10 messages, then +1 per second. Whispers are exempt outside
  instances. The server can change these limits at any time.
- Whispers only work between characters on the same or connected realms.
- Since 12.0.0 the result can be `AddOnMessageLockdown` (11) or `TargetOffline` (12).
- **Trial and Veteran accounts cannot send addon messages on Forever** (and on Retail from 12.1.7).
  Those players can't duel. The addon shows "Addon messages are not available".
- **Still to verify in real clients:** the sender name format, whether your own guild/party
  messages echo back to you (we filter them either way), the exact lockdown situations, and
  behaviour across connected realms. This needs **two real WoW clients**. Until then, the duel status is SIMULATED.

## 3. Result trust levels (shared vocabulary)

| Level | Meaning | Where |
|---|---|---|
| `local` | Score from one client, not checked by anyone | WoW solo records |
| `peer_checked` | The opponent's addon replayed the log with the shared seed and got the same score/hash, and found no impossible input | WoW duels |
| `server_verified` | stackrivals.io replayed the log on the server (`verifyLog`/`replayLog`) | Web matches; WoW results imported as in §6 |

A peer check catches a tampered score or log. It cannot prove that the opponent's addon wasn't
modified, because both clients are under their players' control. So **ranked rewards and global
leaderboards use only `server_verified` results.**

## 4. Why there is no live WoW ↔ web bridge (option B evaluated)

WoW addons run in a sandboxed Lua environment with **no sockets, HTTP, files or processes**. The
only ways data leaves or enters the game:

1. **SavedVariables** (a Lua file written when you log out or `/reload`). A desktop companion can
   read it afterwards and send results to the server. That is useful for import, but it only
   happens at logout or reload, so it is **not real-time**.
2. **Files from a desktop app read at load.** WeakAuras Companion and the Raider.IO client work
   this way. They can bring data *in*, but only at login or `/reload`.
3. **Screen reading** (a companion OCRs a code drawn by the addon). This is technically one-way and
   near-real-time, but it is a program watching the game client. Blizzard's rules on third-party
   tools are strict, and the way back into the game would need simulated input, which is
   **forbidden**. We do not do this.
4. Reading game memory, injecting input or intercepting network traffic: **forbidden**, never.

**Result:** a two-way real-time WoW↔web match cannot be built with allowed methods. A companion
app (option B-lite) is only worth it later as a convenience that uploads finished results from
SavedVariables after `/reload`, with the player's consent. That is the same trust level as §6.

## 5. Shared match record (JSON, both platforms) — `stackrivals.match.v1`

```json
{
  "schema": "stackrivals.match.v1",
  "matchId": "wow:k3x9qa or web:<uuid>",
  "platform": "wow-forever | wow-retail | wow-classic | web | windows | android | ios | chrome",
  "mode": "duel | challenge | daily | solo",
  "ruleset": "b120 | r180 | daily120 | classic",
  "engineVersion": 1,
  "seed": "srduel-k3x9qa-ab12cd34ef56gh78",
  "startedAt": "2026-11-05T00:12:00Z",
  "endedAt": "2026-11-05T00:14:05Z",
  "players": [
    {
      "playerRef": "wow:Alice-Realm | web:<user id>",
      "score": 68046, "lines": 140, "level": 15, "ticks": 7200,
      "hash": "8f2a91c0",
      "log": { "v": 1, "seed": "...", "startLevel": 1, "ticks": 7200, "inputs": [[0, 5], [12, 0]] },
      "forfeited": false
    }
  ],
  "outcome": ["win", "loss"],
  "verification": "local | peer_checked | server_verified",
  "reasons": []
}
```

`log` is exactly the web's `SerializedInputLog`, so `replayLog` can run it unchanged. The WoW
compact log (§2) converts to it losslessly.

## 6. Asynchronous cross-platform challenges (option C, PLANNED)

The same seed and rules on both platforms, with results moved by **copy/paste codes**. That uses
no network from WoW and is fully allowed. The web server replays the result, so it is
`server_verified`.

**Challenge code** (made on the web, or by the addon):
`SR1C.<ruleset>.<seed>.<check>`. Example: `SR1C.b120.srchal-7f3k2p9d.1a2b3c4d`, where
`check` = FNV-1a of the preceding text, in hex.

**Result code** (made by the addon after playing the challenge; the player copies it with Ctrl+C
from a text box):
`SR1R.<ruleset>.<seed>.<ticks36>.<score36>.<lines36>.<playerHex>.<packedLog>.<check>`.
`playerHex` is the hex-encoded UTF-8 of `Name-Realm`. `packedLog` uses the codec from §2. A 2:00
result is roughly 2–4 KB, which is fine to paste into a web form.

**Web side:** decode → `replayLog` → `verifyLog` (same limits) → store as
`platform: wow-*`, `verification: server_verified` → show on the challenge page and leaderboard.

**Identity:** a WoW character is linked to a stackrivals.io account by a one-time **link code**.
The website shows a code, the player types `/sr link CODE` in game, and the addon includes it in
the next result code. This shows that the person who has the account also controls a WoW client
that produced that result. It is **not** proof of who owns the character. Call it "linked", never
"verified identity". No passwords, tokens or account data ever go through the addon.

**Daily:** a cross-platform Daily uses seed `srwow-daily-<UTC date>` (the WoW Daily Blitz) on both
platforms, so web and WoW players get the same pieces each day.

## 7. Fairness rules (both platforms)

- The same engine (`ENGINE_VERSION` must match; parity tests keep the TS and Lua engines identical).
- The same seed for both players, and the same time cap. Inputs are limited to 4 per tick and 80
  per second, inputs after top-out are rejected, and logs over the time cap are flagged.
- A forfeit always loses; both forfeiting is a draw. Equal scores are a draw (web `decideOutcome`).
- A result needs the full input log. A claimed score without a log never wins (WoW: "no result").
- A log that fails the replay, or arrives faster than the game can be played, loses.
- A replayed match result can't be replayed twice: the web stores `(matchId, playerRef)` as unique.
- Free and equal on every platform: no paid advantage, and web premium never gates WoW play
  (Blizzard add-on policy).

## 8. Roadmap

| Phase | Content | Depends on |
|---|---|---|
| P0 | Solo addon 0.3.x released for Forever | Owner's client test |
| P1 | Duels 0.4.0: two-client real test → merge to main → release | Two WoW accounts in the same guild/realm |
| P2 | Async challenges: `/sr code` (import a challenge), result code export, web import page + server replay | Web work (§6), EditBox UI in the addon |
| P2 | WoW character ↔ web account linking (link codes) | Web account system |
| P3 | Guild leaderboard inside WoW (guild broadcast of personal bests, throttled) | P1 |
| P3 | Optional desktop companion: upload results after `/reload` (consent, read-only) | P2 |
| — | Live WoW↔web, live Forever↔Retail | Not possible (§1, §4) |
