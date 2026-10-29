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
