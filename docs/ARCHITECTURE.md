# Architecture and decisions

## Layers

```
Engine/   pure Lua 5.1, no WoW API   ← shared by every WoW client; parity-tested against the web engine
Core/     Session (modes, countdown, pause, events) and DB (pure) + Sound/Main (WoW glue)
UI/       textures and font strings only (no XML, no templates, no libraries)
```

## Decisions

- **1:1 engine port, mutating in place.** The web engine is immutable (a copy per tick). In WoW that
  would create garbage 60×/s, so the Lua port mutates state, with identical outcomes. `hashState`
  builds the same string as the web engine; tests/fixtures are produced by the TypeScript engine.
- **No bit library.** 32-bit hashing/PRNG are done with exact double arithmetic, so behaviour is the
  same in every WoW client and in plain Lua 5.1.
- **Gravity table precomputed** from the web formula, so no `pow` rounding difference can exist.
- **Keyboard only while live.** `EnableKeyboard` is on only during countdown/playing (or while
  rebinding). Combat: `PLAYER_REGEN_DISABLED` fires before lockdown, so the run pauses and the
  keyboard is released before any restriction applies; during lockdown the addon calls no
  keyboard API at all.
- **No HTTP.** WoW addons can't reach a web server. Nothing online is claimed. Best runs are kept as
  web-format input logs (`v;seed;startLevel;ticks;t,a …`) so a future import/verification on
  stackrivals.io can replay them server-side.
- **Daily Blitz** gets fairness without networking: the seed is `srwow-daily-<UTC date>`.
- **Own assets only.** Icon (tools/make_icon.py) and sounds (tools/make_sounds.py, same recipes as the
  web game's synthesized Web Audio) are generated from code.
- **Naming.** Pieces keep StackRivals' own names (bar, cube, tee, hook, jack, zig, zag). The listing
  avoids third-party trademarks.

## Multi-client plan (after the Forever launch)

The engine, session and DB have no client dependencies. The UI uses only long-standing API
(`CreateFrame`, `SetColorTexture`, `SetFont`, `EnableKeyboard`, `SetPropagateKeyboardInput`,
`PlaySoundFile`) with fallbacks where APIs moved (`C_AddOns.GetAddOnMetadata`,
`C_ChatInfo.SendChatMessage`). To ship to more clients:

1. Add their interface numbers to `## Interface:` (comma list), e.g. Retail, Classic Era / Hardcore /
   Anniversary, progression Classic.
2. Run the in-client test pass (docs/TESTING_IN_WOW.md) on each client.
3. Fix only what that pass finds; keep one code base.

## Possible next steps (not in 0.1)

Guild leaderboard and duels over the addon message channel (`C_ChatInfo.SendAddonMessage`, throttled),
more modes (40-line sprint), Spell mode from the web game, cosmetic skins.
