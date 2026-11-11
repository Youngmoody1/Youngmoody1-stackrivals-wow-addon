# Quality audit of the WoW addon, November 2026 (branch `audit/0.9.1-quality`)

A full review of the addon on top of 0.9.1-dev (`d72ee1f`): gameplay, multiplayer, account sync, effects,
sound, UX, performance, security and client compatibility. Nothing here is released, installed or merged.
0.9.0 on CurseForge is untouched.

**What counts as proof here.** Every finding marked *reproduced* was reproduced with a script against the
simulated clients (`tests/netsim.lua`, `tests/wowmock.lua`) and now has a regression test in
`tests/test_audit.lua` or `tests/test_signed_import.lua`. **None of it has been seen in a real WoW client.**
Section 6 lists what only a real client and real players can show.

## 1. Findings and fixes

Severity: P0 critical, P1 serious, P2 medium, P3 minor.

### Multiplayer (commit `12f7c8c`)

| # | Sev | Finding | Fix |
|---|---|---|---|
| N1 | **P0** | **Also in the released 0.9.0.** A comm-test ping (`CTP`) from anyone, also whispered, queued a normal-priority answer each time. A player repeating pings (a chat macro is enough) filled another player's 64-message send queue, so that player's duel or Loot Duel result never left their PC: the Loot Duel winner changed, and a duel win became "rival sent no log". Reproduced | Pings are answered only over the group channel, from a group member, at most once per 5 s, at low priority, under one queue key |
| N2 | P1 | An invite with the Quickplay flag and an already-known match id was accepted from anyone with no popup; the decline that followed left Quickplay "searching" without a start time, which raised a Lua error every frame and stopped all duel / Loot Duel timers until `/reload`. Reproduced | Only that match's own rival; Quickplay never searches without a start time |
| N3 | P1 | The 60 s wait for the rival's input log was wall-clock. A long log sent inside an instance (0.8 whispers per second there) took longer, so the honest winner was declared forfeited. Reproduced | The wait counts from the last chunk that arrived; hard cap 60 s + 1.5 s per chunk |
| N4 | P2 | After the rival forfeited, leaving was recorded as a second forfeit ("draw" against their "loss"): disputed, counted for nobody. Reproduced | Leaving then takes the win |
| N5 | P2 | No rate limit on duel invites: one player could open popups (with the ready-check sound) at another without end. Reproduced: 40 popups in 8 s | Per-sender cooldown after a decline or timeout: 30 s, doubling to 10 min; a quiet "busy" meanwhile |
| N6 | P2 | "Announce" posted this PC's winner to group chat even when this PC knew the result was disputed, and always claimed "Every PC replayed every run" (untrue above 10 players). Reproduced | A disputed result is announced as disputed; the claim is "Checked by replay on my PC" |
| N7 | P3 | With more than 10 players, the once-a-second loop could run several replays in one frame (not reproduced; by reading) | That loop only queues; replays run one per frame. The batch in `LD.finish` is unchanged: see section 5 |

Checked and clean: every message parser (450,000 mutated messages, no error other than N2), result spoofing
(results are bound to the real sender and the roster), chat injection, loot APIs (read-only: no
`GiveMasterLoot`, no loot-method change, no trade), stuck states (every duel and Loot Duel state has a
timeout), memory growth, tie handling.

### Account and security (commit `fc6b46b`)

| # | Sev | Finding | Fix |
|---|---|---|---|
| A1 | P2 | A saved `verified = true` with a shipped key id was trusted after a reload. SavedVariables is a file the player can edit, so a hand-edited file could show VERIFIED with any Shards and cosmetics and pass `Account.canApplyCosmetic`. (Not exploitable in 0.9.0: no key is shipped there.) Reproduced | A VERIFIED profile keeps the signed code. Nothing is loaded as verified; after login the signature is checked again (spread over frames) and the profile is rebuilt from the code. No code, an edited code or another link: UNVERIFIED |
| A2 | – | Already in `d72ee1f`: cosmetics need VERIFIED **and** not OUT OF DATE | – |

### Run lifecycle, keys, feedback (commit `2f4a18a`)

| # | Sev | Finding | Fix |
|---|---|---|---|
| G1 | P2 | `/sr spell` or `/sr quickplay` during a solo run left the run behind the menu with no way back; the next Start discarded it. Reproduced | An unfinished solo run goes to "Continue last run"; a duel / Loot Duel run stays on screen |
| G2 | P2 | For the second after a run ended the keyboard went back to WoW: a key pressed for the game moved the character or fired an action bar button (matters on Hardcore). Reproduced | Game keys are swallowed during that second, in duels too |
| U1 | P1 | A level-up erased the line-clear callout, also QUAD + BACK-TO-BACK (once per level). Reproduced | The clear keeps its callout; the level goes on the top line |
| U2 | P1 | Spell Battle vs Bot played two end sounds in one frame: the defeat jingle under the victory jingle on a win. Reproduced | One end sound, chosen when the result is known. Duels: neutral sound at my run's end, victory / defeat with the result |
| U3 | P1 | The display font (Chakra Petch) has Latin letters only: player and item names in Cyrillic, Greek, Hangul or CJK would be blank. Font coverage measured; rendering not seen in a client | Such text is set in WoW's own font at the same size; names are never cut inside a UTF-8 character |
| U4 | P2 | Every hard drop played two sound files in one frame; a clear with combo and level-up played four. Reproduced | Per frame: at most one impact sound and one melodic sound |
| U5 | P2 | The window-open sound and the ready-check sound ignored the Sound effects setting | They follow it |
| U6 | P3 | Restart and the play-again key did nothing in web challenges; a Loot Duel showed Restart and "or press Space" | Both restart the challenge; a Loot Duel shows neither |
| U7 | P3 | Ghost outline left on the board after Quit; a key held when chat opened stayed "down"; effects of one run played over the next; the spell flash could stick at 40 %; rotate sound on a blocked turn; a Spell Battle restore replayed the last flash; wrong sentence when both top out on the same tick | Fixed, one test each where the mock can show it |
| U8 | P3 | Combat state: `UnitAffectingCombat` can be unreadable on modern clients, leaving "Combat's over" on screen during a fight | The REGEN events themselves set the state |

### Text and layout (commit `bc9b8e8`)

| # | Sev | Finding | Fix |
|---|---|---|---|
| L1 | P2 | The duel result explanation ran behind the Rematch button: up to 135 px, hiding the agreement / DISPUTED line | At most four lines, the agreement line always kept; the rest is a tooltip |
| L2 | P2 | A finished duel's chat panel covered the Loot Duel live standings | Cleared when a Loot Duel run starts |
| L3 | P2 | Live standings and match chat could be off screen (16:10, 4:3, or addon size 140 %): only the main window was clamped | They flip to the left of the window when the right side has no room |
| L4 | P3 | The Loot invite popup rebuilt its texts every frame; the "waiting" duel badge was wider than the board | Once a second; badge is name + score |

## 2. Effects in three tiers (`UI/Fx.lua`, commit `0e69fad`)

| Tier | When | What |
|---|---|---|
| Small | every hard drop | the four landed cells flash for 0.14 s |
| Medium | line clears, combos, spells (existing callouts and flashes); **new:** the last 10 s of a timed run | a red rim that breathes and a tick on 5..1; garbage / bomb impact is heard |
| Big | QUAD, BACK-TO-BACK, a combo of 4+, a new best, a duel / Spell Battle win, a Loot Duel win | a glow burst behind the callout or the result; the Loot Duel result has a sound (it was silent) |

All are client-side AnimationGroups built once with the window: no Lua per frame. `UI:ClearFx` stops
everything when the run changes, ends or the window hides. **Settings > Reduce effects** keeps texts and
sounds and drops flashes, bursts and the pulsing rim.

Not done, on purpose: flashing only the cleared rows and a perfect-clear effect need new data from the
engine (`lastClear.rows`, perfect-clear detection). The engine is shared with the website bit for bit, so
that is a coordinated change, not an addon-only one (see the handoff below).

## 3. Performance (measured on the Lua 5.3 shim with the mock's widgets: not WoW numbers)

| Case | Mean per frame | Worst frame | Garbage |
|---|---|---|---|
| Classic, game logic | 5 µs | 0.1 ms | 9 KB/s |
| Spell Battle vs Bot (hardest bot), game logic | 49 µs | 1.3 ms | 350 KB/s |
| Window open on the menu, idle | 14 µs | – | 2 B/frame |
| Window closed | – | – | 0 |
| Full redraw, unchanged state | 59 µs | – | ~0 |

A 60 FPS frame is 16.7 ms: the worst measured frame is 8 % of one. Rendering touches only changed cells.
No C_Timer is used; the only per-frame handlers sit on frames that are hidden when idle.

**Not optimized, on purpose:** the bot's placement search (`Engine/Bot.lua`) allocates 100–190 KB per bot
piece and is the only visible spike (1.3 ms). Rewriting it risks the bot's bit-exact parity with the
website for a gain no player would notice. `bestLog` in SavedVariables (up to 1.5 MB per mode) is written
and never read: dead weight, left in place because removing it changes saved data (see section 5).

## 4. Tests

| | Before (`d72ee1f`) | After |
|---|---|---|
| Automated tests (Lua 5.1 in CI) | 850 | see the CI run of the branch head |
| New | – | `tests/test_audit.lua` (24), `tests/test_signed_import.lua` (+4) |

## 5. Open, waiting for a decision

1. **0.9.0 on CurseForge has N1** (comm-test queue jamming), N2 and N3. They are fixed only on this branch.
   Shipping the fix means a release, which needs your GO.
2. `LD.finish` still replays its remaining contenders in one frame (up to ~0.2 s with 10 unchecked logs).
   Spreading it means the result arrives a few frames later on every PC: a behaviour change to test with
   real players first.
3. The duel seed commitment is a 32-bit hash: a host with custom tooling could search for a second nonce.
   Both players get the same pieces, so the gain is small; a fix changes the wire protocol.
4. `bestLog` in SavedVariables: remove (smaller file) or keep.
5. Shift-click item insert for Loot Duel hooks `ChatEdit_InsertLink`. If Retail 12 / Forever moved it, the
   hook is silently skipped. Check in the client: `/dump ChatEdit_InsertLink`.

## 6. What only a real client can show

| Area | Status |
|---|---|
| Classic Era | 0.3.1 smoke test (Classic, Daily, Time Trial) on 4 Nov 2026. Nothing newer |
| WoW Forever | not tested |
| Retail | not tested |
| TBC Anniversary | not tested |
| Mists of Pandaria Classic | not tested |
| Titan Reforged (China) | not tested; no access |
| Duels between two real players | not tested |
| Loot Duel, 2–5 players | not tested |
| Loot Duel, 10–40 players | simulated only (`test_loot40.lua`, `test_lootraid.lua`) |
| Signed profile from the real website (VERIFIED / REJECTED / after `/reload`) | waits for the production key |
| Everything in this audit | simulated clients only |

Real-client checks this audit adds to `TEST_PLAN_0.9.1.md` (part E): the keyboard during the second after
a run ends; names in Cyrillic / CJK; the side panels at addon size 140 %; the sounds (one per moment, off
means off); the new effects and Reduce effects; `/sr commtest` with 2–5 players.

## 7. Handoff to the website chat (nothing was changed there)

1. Cleared-row flash and a perfect-clear effect need `rows` in the engine's `lastClear` and a perfect-clear
   flag. Display-only fields, but the engine is shared: add them on both sides in one versioned step, with
   the shared vectors unchanged (the input log and hash must not change).
2. After a reload the addon now re-checks a VERIFIED profile from the signed code it kept. No change to
   SRP1 / SRP2 or the signature formats.
3. The addon's Collection wording for a signed but old code is "VERIFIED but OUT OF DATE": the website's
   Import result page (planned, C2) should use the same two separate ideas: genuine, and current.
