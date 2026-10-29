# StackRivals for World of Warcraft

A fast, competitive falling-block puzzle minigame inside WoW — the same game as
[stackrivals.io](https://stackrivals.io), with the same rules, pieces and scoring.
Built first for **World of Warcraft: Forever** (launch 4 November 2026).

| Client | Status |
|---|---|
| WoW Forever | Release target (interface 16001). Real-client test on launch day (beta is closed). |
| Retail (Midnight) | Listed in the TOC (120105) so it can be tested now; not yet verified in the client. |
| Classic Era / Hardcore, TBC / Anniversary, Wrath, Cata, Mists Classic | Listed in the TOC; planned, verified one by one after Forever. |

Free, no ads, no payments. Pauses itself the moment you enter combat.

## Install

1. Download `StackRivals-<version>.zip`.
2. Find your game folder: Battle.net → select the WoW Forever game → gear icon → **Show in Explorer**.
3. Open `Interface\AddOns` inside that game folder (create `AddOns` if it doesn't exist).
4. Unzip so you get `Interface\AddOns\StackRivals\StackRivals.toc` (not `StackRivals\StackRivals\...`).
5. Start the game (or `/reload`), make sure **StackRivals** is ticked in the AddOns list on the character screen.
6. Type `/sr` or click the minimap button.

During the beta, if the AddOns list shows "Out of date", tick **Load out of date AddOns**.

## Modes

| Mode | What it is |
|---|---|
| Classic | Endless. The speed goes up every 10 lines. |
| Blitz 2:00 | Highest score in two minutes — made for queue timers and waiting for the group. |
| Daily Blitz | Blitz with the **same piece sequence for every player** on the same UTC day. Compare scores with your guild. |

## Controls (rebindable in Settings)

| Action | Default | Also |
|---|---|---|
| Move | ← → | A D |
| Soft drop | ↓ | S |
| Hard drop | Space | |
| Rotate right / left | ↑ / Z | W X / L-Ctrl |
| Hold | C | Shift |
| Pause | P | Esc |

Keys are captured **only while a run is live**. Paused, on the menu, with the window closed or
in combat, every key goes to WoW as normal. Enter pauses the game and opens chat. Print Screen
always works.

## Commands

`/sr` or `/stackrivals` open/close · `/sr blitz | classic | daily` start a mode ·
`/sr pause` · `/sr settings` · `/sr minimap` show/hide the button · `/sr scale 0.8` ·
`/sr reset` window position/size · `/sr sound` · `/sr stats` · `/sr version`

## What makes it StackRivals

- **Exact web rules.** The Lua engine is a 1:1 port of the stackrivals.io engine; automated
  parity tests replay the same inputs in both and require bit-identical results.
- **Combat-safe.** Combat pauses the run, hands every key back to WoW and (optionally) hides the window.
  It comes back paused after the fight.
- **Never lose a run.** `/reload`, logout or a disconnect keeps your unfinished run; *Continue last run*
  restores it exactly.
- **Records** per mode (top 5), today's Daily best, lifetime stats, and a one-click *Share to guild / group*.
  Records live in your SavedVariables on your own computer; they are **not verified** (anyone can edit
  that file), so treat shared scores as friendly bragging, not a ranked ladder.
- **How to play** on first launch, pause/resume with one key, the window always fits the screen.
- Every best run is stored as a compact, replayable input log (the web format), ready for future
  verification on stackrivals.io.

## Development

```
lua5.1 tests/run.lua          # all tests (engine, parity, session/DB, full addon in a WoW API mock)
tools/build_release.sh        # dist/StackRivals-<version>.zip (addon folder only)
bun tools/parity/gen-fixtures.ts ../stackrivals-practice-arena > tests/fixtures/parity.lua
```

- `StackRivals/Engine` — pure Lua 5.1 game engine (no WoW API): PRNG, pieces, rules, input DAS/ARR.
- `StackRivals/Core` — session (modes, pause, countdown), saved data, sound, bootstrap/events.
- `StackRivals/UI` — theme, board renderer, window, minimap button.
- `tests/` — Lua tests + a strict WoW API mock; `tools/` — fixture generator, icon/sound generators, release script.

Everything in `tests/`, `tools/` and `docs/` stays out of the release ZIP.

See [docs/TESTING_IN_WOW.md](docs/TESTING_IN_WOW.md) for the in-client test pass and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design decisions and the multi-client plan.
