# Changelog

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
