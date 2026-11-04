# Changelog

## 0.7.0 — WoW colours, Loot Duel, 0.6.1 review (branch `feature/loot-duel`, development, not released)

- **WoW's own class colours** everywhere a class is known: lobby cards, Quick Duel "your card", Guild Duels lists (class from the guild roster, friends and Battle.net lists), match chat (the rival's name), the live rival panel and the result. Taken from the client (`C_ClassColor.GetClassColor`, else `RAID_CLASS_COLORS`), with warcraft.wiki.gg's values as fallback (the 9 Classic classes plus Death Knight, Monk, Demon Hunter and Evoker, used only when a client reports them). Item quality colours the same way.
- **Faction themes**: Alliance cards blue, Horde cards red (fill, border, edge, label), dark enough that every class colour reads at 3:1 or better (tested). Your own card shows your real character portrait (`SetPortraitTexture`); the rival's shows the class icon. No invented race colours.
- Profile tab without a profile is compact, with a "Link account" button.
- **Loot Duel** (menu → Loot Duel): the leader, an assistant or the master looter picks an item (shift-click, link or ID; shown in its quality colour), 1:00 or 2:00, and 2–8 group members. Everyone must click **Join** (Pass = /roll instead; no answer = not in). The same pieces for everyone (a seed from every player's nonce), no spells, a live leaderboard. **Every PC replays every run**; replay-checked standings by score, then lines; a tie at the top stays a tie (roll off); a missing or failed run is out, and nobody wins by default. **Announce** posts one line only when clicked. Never ranked, never on the website, no gold or bets, and **no loot API is called** (the loot master hands out the item). Peer-checked, which is said on screen. See `docs/LOOT_DUEL.md`.
- **Review of 0.6.1** (independent): 6 confirmed problems fixed (chat colour-code injection through line wrapping, a web challenge after /reload, Quickplay searching during a normal duel, Forever reported as Classic, "Share my card" leaking the record, Sync paging) plus 6 plausible ones; each has a regression test (`tests/test_review.lua`). See `docs/STATUS.md`.
- Docs: `docs/STATUS.md` (every feature's real status), `docs/WEB_HANDOFF.md` (the one handoff file for the website, with the prompt for web Claude), `docs/INSTALL_AND_TEST.md` (one install and real-client test guide for 0.3.1, 0.5.1 and 0.7.0, Classic Era and Forever).

## 0.6.1 — Connected multiplayer (branch `feature/connected`, development, not released)

- **QUICKPLAY** (Quick Duel): a big button on the menu. Pick Duel 2:00 or Spell Duel 3:00 → Search → match found → ready check (the duel lobby) → countdown → match → result → rematch. It finds only players who are searching too and that WoW lets the addon reach (guild, party / raid, friends and Battle.net friends whose StackRivals answered, recent rivals). There is no global or fake queue. Cancel, 5-minute timeout, fall-through (back to searching, the no-show rival is skipped for 2 min), lobby cancel. The stackrivals.io adapter exists and honestly reports "not connected".
- **Character cards** in the lobby: name, realm, faction (colour + emblem), race, class, level, duel record. Yours comes from WoW's API; the rival's is self-reported by their addon and marked "unverified". "Share my card" can switch it off. StackRivals rank / level shows Unknown until an account can be linked.
- **Match chat** beside the window during a duel: text + Send, quick messages GL / GG / WP / Rematch?, Mute (remembered), Chat on/off, fold-away tab. Both must have chat on. Free text only within one faction (quick messages across factions). Rate-limited, escaped, never posted to any WoW channel.
- **WoW-style mode names** (display only): Time Trial (was Blitz 2:00), Daily Challenge (was Daily Blitz), Duel 2:00 / Duel 3:00, Spell Duel, Quick Duel, Guild Duels (was Challenge Friends). Classic and Spell Battle (vs Bot) keep their names. Mode ids, rulesets, protocol, SR1 / SR2 and saved data are unchanged; `/sr trial` and `/sr quickplay` added.
- **Account** (menu → Account): link this character to an existing stackrivals.io account with a one-time code. Type the web code → PENDING (a typed code proves nothing) → copy the link request (SRL1) to the website → paste the website's snapshot (SRP1) → LINKED. States NOT LINKED / PENDING / LINKED / NOT SYNCED (older than 7 days), last synced, Unlink (two clicks). **Profile** tab: name, rank, level + XP, season, W/L/D, achievements, cosmetics, last 5 matches, all display only from the website's snapshot. Newer snapshots replace older ones (no rollback, no duplicates); wrong character / link / expired / future / manipulated codes are refused with clear errors. No password, e-mail or token is ever asked for or stored. Formats DRAFT v1 (`docs/ACCOUNT_SYNC_HANDOFF.md` with vectors, the website's to-do list and a prompt for web Claude). Manual copy / paste sync, not live sync. Companion app: research only.
- **Sync** (Account → Sync): paste an SR1 challenge code from stackrivals.io and play exactly that challenge (never a local record; Play again repeats it); copy SR1 result codes for the last 10 challenges and today's best Daily Challenge run, for the website to replay. The SR1 `link` field carries the character's linkId when linked. Manual copy / paste, said on screen.
- **Shared data contract v1 (DRAFT)**: `tools/contract/types.ts` (PlayerRef, AccountRef, Platform, MatchId, Ruleset, GameMode, EngineVersion, Seed, InputLog, SpellEvents, MatchResult, MatchVerification, ProfileSnapshot and the Quickplay / chat types), the TypeScript reference for the account codes (`tools/contract/account.ts`), shared vectors `docs/vectors/account_v1.json` (Lua-made, 84/84 with the TypeScript reference), `docs/STACKRIVALS_WEB_INTEGRATION.md` and `docs/WEB_ADDON_INTEGRATION_HANDOFF.md` with the prompt for web Claude.
- **Battle.net transport**: Battle.net friends on realms a whisper can't reach can be found, challenged, matched by Quickplay and chatted with, over `C_BattleNet.SendGameData` (or `BNSendGameData`) / `BN_CHAT_MSG_ADDON`, documented APIs only. Same message queue, limits and duel rules. Temporary game account IDs are kept in memory only (never saved, shown or used as identity); messages from anyone who isn't a current Battle.net friend on WoW are dropped. Text chat across factions only over Battle.net (as Battle.net whispers allow). Older clients without the API still show "other realm". Simulated only.
- Protocol additions `QS`, `PRF`, `CH`, `QM` and the `INV` flag `q`: ignored by 0.6.0 and older, which still duel normally.
- Handoff for the web project: `docs/WOW_QUICKPLAY_HANDOFF.md`. Includes everything from 0.6.0 and 0.5.1.
- All SIMULATED: nothing of 0.6.1 has run in a real WoW client yet.

## 0.6.0 — Challenge Friends (branch `multiplayer`, development, not released)

- **Challenge** card on the menu opens **Challenge Friends**: pick Blitz 2:00, 3:00 or Spell Battle, then a list — Guild, WoW Friends, Battle.net friends on WoW, Group, Recent rivals — or type a name. Uses the 0.5 duel protocol unchanged.
- A player is "ready" only after their own StackRivals answered; nothing is sent until you press Refresh (each player asked at most once a minute, max 20 per click; guild / group: one broadcast). Invites only by your click. Ignored players are never listed, asked, answered or allowed to pop up an invite.
- Battle.net friends are challengeable when they play the same WoW version on your realm or a connected one; others are listed with the reason ("other realm", "other WoW version"). A Battle.net transport for other realms is planned, not built (`docs/CHALLENGE_FRIENDS.md`). Game account IDs are never stored.
- Includes everything from 0.5.1.

## 0.5.1 — vs Bot survival rule (branch `spellbattle`, not released)

- **Spell Battle vs Bot follows the web's new rule** (stackrivals.io `ef71158`, checked at `8ddaad7`): whoever tops out first loses, whatever the score. The bot topping out while you play is a VICTORY at once; your top-out is a DEFEAT at once and the bot stops there (shown as the server shows it); the same tick or 3:00 → higher score. Ported line by line, with fixtures from the web's real code (every rule case + 40 full matches at all 5 levels) and live matches checked against the server's result at all 5 levels.
- Guild duels unchanged (the web keeps "higher score wins" for 1v1).
- Saved W/L/D now count under the new rule; 0.5.0 results kept apart (`statsV1`), best scores kept.
- Pick Spells and the result screen say the rule ("First to top out loses. At 3:00 the higher score wins."); "beat N to win" and "the bot is finishing its run" are gone.

## 0.5.0 — Spell Battle preview (branch `spellbattle`, not released)

- **Spell Battle** from stackrivals.io Play 2.0 (web `48fdf46`): the same 9 spells (Bomb, Line
  Blast, Freeze, Swap, Clear Board on your board; Garbage, Speed Up, Blackout, Scramble on your
  rival's), mana from line clears, 3 s cooldown, spells land 1.5 s after the cast, 2 + 2 loadout.
  StackRivals spells on StackRivals boards only: nothing touches WoW abilities or gameplay.
- **Spell Battle vs Bot**: the web's bot at 5 levels (same placement AI, same casting rules, same
  tuning versions), 3:00. The match ends the moment it's decided (bot topped out while you lead:
  Victory at once, no more input or casts); behind, you play on ("beat N to win"); after your
  top-out the bot plays on to 3:00 like on the web (spread over a few frames). Local W/L/D per
  level. /reload restores a match exactly.
- **Pick Spells** sheet (the web's icons), spell tiles with keys, mana progress and cooldown,
  bomb target on your board, FROZEN / SPEED UP / BLACKOUT chips, hit flashes, the rival's live
  mini board and mana, Victory / Defeat. Spell keys Q / E / R / F (web) and 1-4, rebindable
  ("Spells 1-4"), only read during a live Spell Battle.
- **Spell Battle duels** with guild / group members (ruleset `s180`, 0.5+ on both sides): spells
  chosen in the lobby and locked at Ready, casts sent at once (SP, repeated), the result = both
  logs replayed together on both PCs (the web's `verifySpellMatch`), peer-checked. Forged spells,
  impossible casts, a changed loadout are caught; lag-only differences are not held against anyone.
  Score-race duels are unchanged and still work with 0.4 clients.
- Menu: a VERSUS row with Spell Battle and Duel; Settings: spell keys.
- Parity: `tools/parity/gen-spell-fixtures.ts` generates fixtures from the web's real code;
  `check_web.sh` runs them. Two web findings reported in `docs/WEB_SPELL_REPORT.md` (final tick,
  input after an incoming top-out); the addon follows the web server's verification.
- Independent review applied: in Spell Battle duels each player's client records where the
  rival's spells actually landed and sends it with the log; the replay lands spells exactly there,
  so a replay is always the player's live game (lag, pauses, withheld sends can't change it).
  Forged, unpaid and ignored spells are caught (tests for each). At most 4 inputs per tick (also
  classic), so a frame hitch never looks "inhuman". A vs Bot result is never lost when the window
  closes during the bot's finish. Fewer allocations per frame in the spell HUD.
- Quality pass:
  - **Duel fairness (0.5 on both sides).** A pause (combat, chat, Esc, loading) pauses both runs, and both resume together. Each player has a 60 s pause budget per duel; past it the duel is forfeited, never voided. A clock check catches a client that pauses silently. A rival who never sends their log, while their own claim is lower, loses (`rival_no_log`).
  - **Results.** Both PCs confirm the result (`VER`); a disagreement is "disputed" and not counted. A spell held back more than 8 s is caught (`late_landing`).
  - **Spell edge cases.** 15 scripted scenarios, compared with the web step by step.
  - **Web bugs.** The two web live-loop findings are reproducible with only the web's code (`tools/parity/web-live-loop-repro.ts`).
  - **SR1** never carries a Spell Battle log.
  - **Spell HUD.** Bigger mana value and taller bar; cost on a plate; cooldown seconds on the tiles; castable spells get a 2-unit edge; an incoming-spell chip and a bar beside the board; your spells flash red, the rival's steel.
  - **Docs.** What peer-checking proves and doesn't; test procedures A and B (`docs/SPELL_BATTLE_TEST.md`).
- Hardening (no new features):
  - **Result classes.** Every duel result has a basis: replay, rejected, forfeit, lost contact, or no result. Only a played-out, replay-checked duel is a VICTORY / DEFEAT and counts as won / lost; the rest are WALKOVER / FORFEIT and counted apart ("Forfeits: N won, M lost"). The verdict exchange carries the basis and compares scores only when both PCs replayed.
  - **Withheld log.** A rival who keeps talking but never sends the log forfeits (a WALKOVER, not a verified win); a rival who goes silent after a high claim gives no result for both.
  - **Pauses.** Every pause costs at least 3 s of the budget; a rival that stays paused past it is no longer waited for (forfeit); a lost resume message no longer stalls the waiting player (the score heartbeat shows the clock moving); the rival's pause is measured after your own run too.
  - **Clock check** on the pauses both PCs actually saw (no blanket 60 s): catches hidden pauses and a slowed-down game. Duels now step the game in real time at very low FPS, so a slow PC is never slowed down or rejected.
  - **Verdicts** are awaited while the rival still plays (e.g. after your forfeit), so both PCs end up agreed or disputed.
  - **Spell HUD.** One message lane under the board for spell toasts and the status line (INCOMING, FROZEN, SPEED UP, BLACKOUT): nothing spell-related covers the falling piece. Spell tiles are taller, with key and cost under the icon.
  - **Test builds.** `FLAVOR=vsbot` builds Spell Battle vs Bot with guild duels switched off; CI builds and keeps both builds.
  - **SR2 draft** (`docs/SR2_DRAFT.md`), nothing built; the two web bugs are listed as open dependencies.
  - **Independent review, fixed:** fake micro-pauses no longer buy clock allowance (the rival's PC charges the 3 s minimum too, budget enforced at all times); loading screens are measured from their start; a hang during play is announced as a pause; your pauses cost nothing after the rival left; "Leave duel" after your run keeps deciding (leaving never voids a loss), and /reload sends no verdict (no dispute); 0.5 clients announce themselves so score races get the clock check; verdicts carry an ack; "ready" repeats while waiting.
- Tests: 121 new (82 parity + rules + scenarios, 15 vs Bot in the WoW mock, 24 two-client duels, plus
  updated duel tests for the new pause and confirmation rules). All earlier tests and the 77 SR1 vectors pass.

## 0.4.0 — multiplayer preview (branch `multiplayer`, not released)

- **Duels**: challenge a guild or group member to a 1v1 score race on a shared seed — Blitz 2:00,
  or 3:00 with the web's 1v1 rules. Find players (one guild/group broadcast, answers by whisper),
  invite popup (works with the window closed), Accept / Decline, lobby with Ready, synced
  countdown, live rival score and lead, result with Rematch, `/sr duel Name [3]`, `/sr leave`.
- Seed made from both players' random nonces, so neither picks the pieces alone.
- Peer check: at the end each addon replays the rival's input log with the engine (port of the
  web's `verifyLog`): inflated scores, wrong seeds, over-time logs and inhuman input are caught.
  Results are labelled "peer-checked", never "verified".
- Compact protocol (≤ 255 bytes, ~3 bytes per input in the log), whispers only during a match,
  paced below Blizzard's limits (also inside instances), result codes handled (throttle,
  lockdown → retry; offline, not in guild → give up). Lost/duplicated/late messages recover.
- Disconnect, forfeit, timeouts, busy/version/combat declines. Combat pauses only your own run.
- Duel history and W/L/D in saved data (separate from solo records).
- Tests: two complete simulated clients over a fake network (loss, duplicates, reordering,
  instance throttling, lockdown, offline, tampering, spoofing).
- Fixes from an independent review of the duel code (15 findings, each with a regression test):
  - the player who finishes second now sends their log at once, and keeps serving it for 60 s
    even after going back to the menu (before, the rival had to ask chunk by chunk);
  - log chunks arriving before their END are kept; missing chunks are asked for only when the
    stream stalls, also while still playing; the log wait counts from when both runs ended;
  - challenging an offline player cancels the challenge (it recorded a win);
  - a "rival gone" mark clears when the rival is heard again, and a complete log always decides;
  - challenging each other at the same moment gives one duel instead of two "busy" refusals;
  - lobby race: the guest waits 15 s longer than the host, and a cancel crossing GO cancels cleanly;
  - leaving after your own run ended is "no result" for you, not a forfeit loss; both forfeiting is
    a draw;
  - security: a withheld log is "no result" (it decided by the claimed score); a failed replay
    check rejects the cheater's result (a loser could escape by sending a bad log); seed
    commit-reveal so nobody can pick or grind the seed; results faster than the clock are rejected;
  - spam: unsolicited replies are rate-limited per player and low priority; re-sent messages
    replace each other in the queue; realm names with hyphens/spaces now match;
  - UI: declining an invite no longer hides a running solo run; "Quit to menu" in a duel is a
    labelled "Forfeit duel" (it left the duel stuck); a duel that starts in combat starts paused;
    the window no longer pops up in combat with "hide in combat" on.
  - Comm: prefix registration result checked; the server's "No player named ..." line is hidden
    for players we just whispered and treats them as offline (API from memory, guarded).

### 0.4.0 round 2 (multiplayer hardening + web integration)

- WoW API: result codes read from the last return value (warcraft.wiki.gg); prefix registration
  result checked and repeated on every login/reload; Trial/Veteran accounts detected.
- Delivery: an accepted send is never treated as delivered. FIN acknowledges results; closed
  matches keep answering with DEC (a lost DEC re-opened the invite popup); other protocol versions
  get a decline in their own version.
- UX: duel starts paused while typing in chat; "Forfeit duel" asks for a second click.
- Diagnostics: last 5 duels in SavedVariables (`duelDiag`), `/sr duel debug`.
- SR1 cross-platform codes (challenge/result), shared test vectors, TypeScript reference checked
  against the web's real `verifyLog` (57/57). Verify.lua: engine_mismatch, faster_than_clock, level claim.
- Fixtures re-based on web commit 29afe52 (no gameplay change); match rules in the fingerprint.
- Docs: MULTIPLAYER_TEST.md (Danish two-client test guide), rewritten CROSS_PLATFORM_MULTIPLAYER.md
  and WEB_INTEGRATION_PROMPT.md.
- Second independent review (14 findings, all fixed, regression tests added): late GO no longer
  makes an honest host look too fast (both sides could record a win); a BYE "left" that overtakes
  a lost END gives no result instead of a win; ignored DECs no longer keep a dead duel alive; offline
  lines match only the rival's exact name and need 6 s of silence; FIN kept on purge and re-acked;
  closed-match memory expires; Trial accounts stay silent; strangers can't flood the diagnostics.
  SR1: printable-ASCII rule (`chars`), real Daily dates, WoW name rules (no invisible/bidi
  characters, BOM kept and rejected), `expired` imports, run key against re-wrapped runs, link codes
  consumed on first use, honest wording on Daily pre-computation.
- Tests: 220 Lua tests + 77 cross-implementation vector checks + a 4,000-code Lua/TS differential fuzz.

## Unreleased (main)
## 0.3.2 — design pass (branch `design`, not released)

- Brand matched to stackrivals.io: the exact "Versus" mark (blades, cuts, steel diamond) from the
  site's SVG, the STACKRIVALS wordmark and display type in Chakra Petch (bundled, SIL OFL), the
  site's colour tokens (navy, card surfaces, brand red/steel/gold, muted text #A3ABBA).
- Readable at any resolution: the window is fitted to ~58% of the screen height at every
  resolution and UI scale, never below 1:1 (Settings: 70-140% of that); larger type, nothing
  under 11 units. Board cells snap to whole physical pixels; the simplified mark is used when the
  header mark would be under 32 px. The window opens right of centre (your character stays
  visible) and its centre is remembered, so resizing never moves it (0.3.1 positions still load).
- Mode menu uses the whole window: three big cards with the best score, one click to play. How
  to play is offered ("New? How to play"), no longer forced on first open; the first runs show the
  controls on the board during the countdown.
- How to play: goal, points table and keycaps for your own key bindings, "Play Blitz 2:00" button.
  Records: a card per mode with the best score, top 5 and stats. Settings: grouped sections.
- Game feel: callouts pop in (Chakra Petch italic), the points you scored float up, the score
  pulses, countdown numbers pulse, "GO!", hard drops flash the board rim, pause/game over fade in,
  a new best pops. All AnimationGroups (run by the client, no Lua per frame).
- Independent design review applied: callouts in tiers (single small and quiet, double/triple
  big, quad biggest in gold with the rim, BACK-TO-BACK above, COMBO ×n counted like the site),
  hard drop gives a 2 px board thump, the last 5 seconds of Blitz pulse, Classic's elapsed time is
  quieter than Blitz's countdown, the ghost piece is an outline with a faint fill, a soft red halo
  behind the window, the controls strip leaves the board at GO, "Start here" on Blitz for a new
  player, "Continue your <mode> run", in-combat notes in the menu and on the pause screen, share
  buttons centred, zero quads not mentioned, Settings hides its own button. After game over Space
  plays again only for 6 s and only with the cursor on the window; then it's WoW's again.
- Chat prefix and AddOn list title now read Stack (white) Rivals (red), like the wordmark.
- Gameplay rules unchanged (engine untouched; parity tests identical).
- Tests: fuzz RNG uses high bits (ported from the multiplayer branch: full state coverage again).

## Unreleased

- Web sync: fixtures now record the web commit they came from (5d2a9fd) and a full rules
  fingerprint; `tools/parity/check_web.sh` compares any newer web version and names each differing
  rule. Records are tagged with the ruleset and archived (never deleted) if the rules change.

## 0.3.1 — prelaunch candidate (not released yet)

Fixes from an independent code review of 0.3.0:
- Game over: Space restarts only for 15 s after the result, never after closing/reopening the window
  and never while Settings is open (so Space is a jump again when you walk away).
- The BEST value no longer keeps an old score after "Quit to menu".
- The "or press <key>" hint follows a rebound hard-drop key.
- Daily countdown on the menu updates while the menu stays open.
- Rescale after UI-scale/resolution change waits one frame for the new screen size.
- Backdrop strips are whole pixels (no seams).

## 0.3.0 — prelaunch candidate (not released yet)

Gameplay & feel
- Game over: press the hard-drop key (Space) to play again, after a 1 s grace period.
- Daily Blitz card shows when the pieces change (00:00 UTC) and your score today.
- Smoother red/steel window backdrop; clearer mode cards; settings show the version.

Stability & performance
- No per-tick table garbage in the game loop, input or rendering; HUD text only updates on change.
- Window re-fits after UI-scale or resolution changes.
- Very long Classic runs (hours) still restore after /reload.
- Saved data records which client build/interface loaded the addon (helps bug reports).

Quality
- Automated layout checks and developer previews of every screen; fixed several overlaps.
- Fuzzing (random keys, clicks, combat, reloads, frame times) on simulated Forever, Retail and
  Classic APIs; 60-minute memory test; 300 corrupted saved files; Daily golden sequences from the
  web engine.
- Reproducible build with validation, checksum and release metadata.

## 0.2.1 — compatibility pass (not released yet)

- Combat check ignores "secret" values on modern clients (Midnight/Forever) instead of risking an error.
- Tested fallbacks for older-client APIs (global `SendChatMessage` / `GetAddOnMetadata`).
- Verified frame-rate independence (same game speed at 30–240 FPS).
- Docs: client compatibility matrix, release plan with fallbacks, support/bug reporting.

## 0.2.0 — quality pass (not released yet)

- How to play screen on first open (and from the menu).
- Records screen: top 5 per mode with dates, lifetime runs/lines/quads/time; labelled local & unverified.
- Game over shows your rank in the top 5.
- Pause key also resumes; while paused every other key (incl. Esc) goes to WoW. Resume countdown 2 s.
- Window always fits the screen at any resolution / UI scale (saved size is kept).
- A Daily Blitz that ends after midnight UTC counts for the day its pieces belong to.
- Fixes from code review: key auto-repeat ignored, key releases we never took go to WoW (no stuck
  running), Enter opens chat on the first press, no chat share during chat lockdown, settings layout.
- TOC lists Retail and the Classic flavors so they can be tested (Forever stays the release target).

## 0.1.0 — WoW Forever launch candidate (not released yet)

- Falling-block puzzle game with the exact stackrivals.io rules (engine v1): 7-bag, hold, 5 next
  pieces, ghost piece, wall kicks, lock delay, combos, back-to-back quads, levels.
- Modes: Classic, Blitz 2:00, Daily Blitz (same pieces for every player each UTC day).
- Combat-safe: auto-pause, keys released, window hidden in combat and restored afterwards.
- Unfinished runs survive `/reload` and logout ("Continue last run").
- Records and lifetime stats per mode, today's Daily best, Share to guild/group.
- Rebindable keys, window size, sound, ghost and minimap options. Minimap button and
  addon-compartment entry. `/sr` and `/stackrivals`.
- Interface 16001 (WoW Forever beta).
