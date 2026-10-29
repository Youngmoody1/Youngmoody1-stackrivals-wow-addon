# Changelog

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
- Tests: 215 Lua tests (55 duel/codes) + 57 cross-implementation vector checks.

## Unreleased (main)

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
