# Changelog

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
