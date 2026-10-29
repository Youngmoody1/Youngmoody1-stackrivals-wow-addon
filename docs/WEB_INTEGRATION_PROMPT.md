# Prompt for the Claude session working on stackrivals.io

Copy everything below the line into the web project's Claude session.

---

**StackRivals — coordination with the WoW addon (read this before changing gameplay)**

There is a World of Warcraft version of StackRivals (repo `Youngmoody1/Youngmoody1-stackrivals-wow-addon`).
Its Lua engine is a 1:1 port of `src/game/engine` and is parity-tested against this repo: a rules
fingerprint (every gameplay constant), 66 replayed games, PRNG vectors and Daily sequences. It
is currently based on web commit **5d2a9fd** (`ENGINE_VERSION = 1`). The full shared spec is in
`docs/CROSS_PLATFORM_MULTIPLAYER.md` in the addon repo; a copy is attached.

### 1. Keep the engines in sync (always)

- `src/game/engine/*`, `src/game/controls.ts` (HANDLING) and the constants in
  `src/lib/match/rules.ts` (time cap, countdown, input limits, reconnect grace) are now a
  **shared contract**. If you change any of them:
  - bump `ENGINE_VERSION` when outcomes change (the project rule already says so), and
  - list the change in a **change report** for the WoW addon (template below).
- Do not change the PRNG (`hashString`, mulberry32, bag shuffle), the input-log format
  (`SerializedInputLog`) or `hashState` without telling the WoW side. They are what make
  cross-platform verification possible.

**Change report template** (put it in your final summary when you finish an optimisation):
```
StackRivals web – change report for the WoW addon
Range: <old commit>..<new commit>   ENGINE_VERSION: <old> -> <new>
1. Gameplay rule changes (engine/controls): what, why, commit
2. New or changed modes (rules, time limits, seeds)
3. Match / 1v1 rule changes (src/lib/match/rules.ts constants, winner rules, verification)
4. Visual identity changes (colours, logo, skins, fonts) with values
5. Features intentionally web-only
6. Anything that changes how scores compare across versions
```

### 2. Facts to respect (do not promise more)

- WoW addons have **no internet access**. A **live** match between WoW and the website is not
  possible. Never advertise it.
- WoW↔WoW duels exist in the addon (score race on a shared seed). Their results are
  `peer_checked`, not `server_verified`, and must never feed ranked ratings or global leaderboards.
- The WoW addon must stay free. Web premium (Pro, shop, wallet) must never be required for
  anything the WoW addon does.

### 3. Build next (when the owner approves; P2 in the spec)

**Asynchronous cross-platform challenges**, verified by this server:

1. **Shared match record** `stackrivals.match.v1` (spec §5). Add `platform` and a `verification`
   column (`local | peer_checked | server_verified`) to whatever stores match/practice results,
   so web and WoW results can live side by side. Keep everything server-written, as in the
   existing RLS rules.
2. **Challenge codes** `SR1C.<ruleset>.<seed>.<check>` (spec §6): a page/route to create one (any
   signed-in user) and to show its results.
3. **Result import**: a form where a player pastes a WoW result code
   `SR1R.<ruleset>.<seed>.<ticks36>.<score36>.<lines36>.<playerHex>.<packedLog>.<check>`. A server
   function decodes it (compact log codec in spec §2 → `SerializedInputLog`), runs the existing
   `verifyLog` with the ruleset's time cap, stores the result as `server_verified` with
   `platform = wow-forever|wow-retail|wow-classic`, and rejects duplicates (`(seed, playerRef)` unique).
   Add tests that a code produced by the WoW addon's fixtures verifies to the same score.
4. **Rulesets**: register `b120` (2:00, 3 s countdown), `r180` (= current 1v1: 180 000 ms cap,
   4 s countdown) and `daily120` (seed `srwow-daily-<UTC date>`, 2:00) as named rulesets, so a
   code always says which rules apply.
5. **Account linking** (later): a one-time link code shown on the profile; the WoW player types
   `/sr link CODE` and the next result code carries it. Label linked characters "linked", never
   "verified". Never ask for Battle.net credentials.

### 4. What the WoW side needs from you

- The change report whenever gameplay or match rules change.
- Confirmation of (or changes to) the formats above before implementing them, so both sides use
  the same version (`SR1C`/`SR1R`, `stackrivals.match.v1`).
- Don't modify the WoW addon repo. Coordinate through the owner.
