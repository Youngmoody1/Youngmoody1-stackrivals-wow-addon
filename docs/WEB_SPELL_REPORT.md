# Spell Battle in WoW: report for the stackrivals.io project

For the web project's Claude and developers. This is read-only analysis: nothing in the web
repository was changed.

- Web base: `48fdf46` ("Release candidate A: Play 2.0").
- WoW branch: `spellbattle` (addon 0.5.0 preview).

## Open dependencies (status 2026-10-30)

| # | Item | Status | Closed when |
|---|---|---|---|
| 1 | Bug 1: the final tick (live loop vs `SpellSim`) | **OPEN** on the web | the web project names a commit that fixes it **and** adds the regression test below; `check_web.sh` and the repro script pass against that commit |
| 2 | Bug 2: an input logged after an incoming top-out (`inputs_after_topout` for an honest player) | **OPEN** on the web | the same |
| 3 | `decideOutcome`: both forfeited, draw or score? | **OPEN** (question) | the web says which rule is intended; WoW follows it |
| 4 | SR2 for Spell Battle vs Bot results | **PROPOSAL** (`docs/SR2_DRAFT.md`), nothing built | both sides agree on the field list and share `docs/vectors/sr2.json` |

Neither bug affects the WoW addon's own results: WoW already runs the final tick like `SpellSim`
and never logs an input after a top-out. They matter for **parity** (a WoW vs-Bot result must
verify on the web exactly as it played) and for honest web players.

## How the two implementations are kept equal

The WoW addon ports this web code to Lua:

- `spells.ts`, `bot.ts`, `spell-bot.ts`;
- `verifySpellMatch`, `decideOutcome` and `botMatchDecided` from `src/lib/match/rules.ts`;
- the board effects in `engine.ts`.

Fixtures are generated **from your real TypeScript** and are read-only on your repo:

- `tools/parity/gen-spell-fixtures.ts`:
  - the rules fingerprint;
  - 20 classic bot games (v1 and v2 tuning);
  - 24 boards × every effect and every bot candidate score;
  - 8 full bot-vs-bot battles;
  - 10 random "human" logs through `verifySpellMatch`;
  - 16 tampered logs.
- `tools/parity/gen-spell-scenarios.ts`: 15 scripted edge cases. They cover every spell, the cooldown boundary (179 / 180 ticks), garbage that tops out or pushes the piece, two spells crossing on the same tick, Freeze + Speed Up overlap, Blackout, Scramble, and refused casts. Both sides are compared after **every step**.

All values are equal. `tools/parity/check_web.sh <web checkout>` repeats everything against any
newer commit and names what differs. `ENGINE_VERSION` stays 1, and no SR1 format changed.

---

## Bug 1: the last tick of a match is processed differently live and on the server

**Affected code** (line numbers at `48fdf46`):

- `src/components/game/VersusGame.tsx` `advanceOpp`, line 221: `while (!o.game.gameOver && o.game.tick < Math.min(upTo, capTicks) && …)`.
- The frame loop, line 365: `if (s.gameOver || s.tick >= capTicks) break;`.
- The server side, `src/game/engine/spells.ts` `SpellSim.step`, lines 331–350. A side is skipped only when `t > p.untilTick`. At `t === untilTick` the side still receives due spells, runs its codes (`p.actor.act(...)` for the bot, line 345), and only skips `stepSide` (line 350: `if (t < p.untilTick)`).

**Cause.** `verifySpellMatch` gives the bot `untilTick = capTicks`, and the player
`untilTick = log.ticks`. The server therefore processes tick 10800 for the bot (its moves and
casts, without gravity) and the player's last tick (due incoming spells). The live loop stops
before both. So the live game the player watched is not the game the server scores.

**Reproducible example** (web code only):
`QUICK=1 bun tools/parity/web-live-loop-repro.ts <web checkout>` prints:

```
1. final tick: seed "final-tick-1132", bot elite: live bot score 77464, server bot score 77470
```

- The player drops a piece every 20 ticks and tops out early; the Elite bot plays on to 3:00.
- At tick 10800 the bot hard-drops on the server only, for +6 points.
- In a full search, 39 matches had a different bot board and 2 a different bot score.
- In a close match, the verified winner can differ from the one the player saw.

**Expected behaviour.** The live loop and the server process exactly the same ticks. There are two
options:

- **(a)** The live loop also runs the final tick like `SpellSim`: due incoming spells and codes, no gravity. This changes no server result. The WoW addon does this (`Core/SpellBattle.lua` `finalTick`).
- **(b)** `SpellSim` skips codes at `t === untilTick`. This changes server results and would need a version.

**Regression test** (suggested, vitest):

- Run the live-loop steps for seed `"final-tick-1132"`, Elite, v2 tuning, with a player who presses `hardDrop` every 20 ticks.
- Compare the bot's final `hashState` and score with `verifySpellMatch(...).bot`. They must be equal.

**Gameplay impact.** Rare (a decision of the bot or a spell landing exactly at the end), but it
can flip a close vs-Bot result. It does not affect classic play.

---

## Bug 2: an input is logged after incoming garbage tops the player out

**Affected code:** `src/components/game/VersusGame.tsx`, lines 311–330:

```ts
const due = pendingMe.current.filter((x) => x.at <= side.game.tick);      // l.311
... for (const inc of due) side = receive(side, inc);                      // garbage can top you out here
for (const a of input.current.drain()) {                                   // l.325
  side = applyCode(side, INPUT_ACTIONS.indexOf(a), toOpp);                 // logs [tick, code] even when gameOver
  ...
  if (side.game.gameOver) break;                                           // checked only after the first one
}
```

`applyCode` (`spells.ts` line 219) appends to `side.log` before it looks at anything else.

**Cause.** If incoming garbage tops the player out at the start of a tick, and a key was pressed in
that tick, one entry is logged **after** the top-out. `SpellSim` stops reading a log at the top-out,
so `verifySpellMatch` sets `inputs_after_topout` (`rules.ts` line 235) **for an honest player**.

**Reproducible example:** the same script prints:

```
2. input after incoming top-out: seed "topout-6", bot rival: logged after top-out {"tick":630,"code":2}, server reasons [inputs_after_topout]
```

The player is the web's own Rookie spell bot plus one rotate key per tick (mashing), against the
Rival bot. Rival's garbage tops it out at tick 630, a key was pressed in that tick, and the log is
flagged.

**Expected behaviour.** If the player is already topped out after the incoming spells, skip the
input drain and the cast queue for that tick:

```ts
if (!side.game.gameOver) { for (const a of input.current.drain()) { ... } /* casts */ } else input.current.drain();
```

The WoW addon does this (`Core/SpellBattle.lua` `SB.step`).

**Regression test** (suggested): run seed `"topout-6"` as above, then
`verifySpellMatch(...).results[0].reasons` must be `[]`.

**Gameplay impact.** An honest Spell Battle can be reported as fraud. How often depends on the
fraud handling: one key press in the exact tick of a garbage top-out, which happens when players
mash keys with a high stack.

---

## Note 3: `decideOutcome` comment vs code

`rules.ts` line 258 says "A forfeit always loses (unless both forfeit → draw)", but when both
players forfeited, the code compares scores. The WoW port follows the **code** for Spell Battle
(`Spells.decideOutcome`). WoW's score-race duels use "both forfeited = draw", as the comment says.
Please say which one is intended.

## Note 4: WoW duels use the receiver's landings (for information)

Over WoW whispers, a spell can reach the rival after its landing tick (lag, or a paused sender).
WoW duels therefore replay each spell **where it actually landed on the receiver's board**. Each
client sends its landings with its log, and the replay is always the live game.

The WoW addon then checks a number of things against the landings. Some it checks always:

- forged or unpaid casts;
- landings that match no allowed cast;
- landings held back more than 8 s after the receiver could have received the spell;
- spells that were never applied.

Other checks come from the WoW pause rules: a pause pauses both players, with at most 60 s per
player, and a client that pauses silently is caught by a clock check.

Both PCs also exchange verdicts. If they disagree, the duel is "disputed" and not counted.

The web has realtime delivery and a server, so it may not need any of this. It is a working
reference if you ever see `inputs_after_topout` or `impossible_cast` on honest matches after
reconnects.

## SR1 and Spell Battle (decision)

- **Existing SR1 codes are never used for Spell Battle results.** `SR1R` carries a classic log (moves `A`–`G`) and verifies with `verifyLog`. It cannot represent casts, the loadout, the bot level or the bot tuning. In the addon, SR1 codes are only made for classic modes; Spell Battle has no export.
- **A spell result needs a new format version**, not a new ruleset id inside SR1. Proposal, **SR2** (not built; it waits for your agreement; the full draft with limits, versioning and ranking rules is `docs/SR2_DRAFT.md`). In addition to the SR1 fields:
  - `mode` = `spellbot`;
  - `diff` = the bot level;
  - `tuning` = v1 / v2, or `createdAtMs`;
  - `loadout` = 4 digits;
  - the log alphabet extended with cast letters `H`–`P` (codes 100–108).
- **Verification** = `verifySpellMatch({ players: [p], bot: { actor: new SpellBot(seed, diff, createdAtMs), loadout: BOT_LOADOUTS[diff] } })`. That is exactly what WoW runs.
- **WoW guild-duel results** stay WoW-only and peer-checked; they are never imported as verified.
- **Coordination.** Nothing is built on either side until you confirm the SR2 field list. The 77 SR1 vectors are unchanged.

## Short prompt for the web project's Claude

> In StackRivals Play 2.0 (commit 48fdf46), the WoW addon project found two differences between the
> Spell Battle live loop (`src/components/game/VersusGame.tsx`) and the server verification
> (`SpellSim` / `verifySpellMatch`). Both reproduce with only the web's code:
> `QUICK=1 bun tools/parity/web-live-loop-repro.ts <web checkout>` (the script is in the WoW repo,
> `tools/parity/`).
> 1. The final tick: the server lets the bot act at tick 10800 and lands due spells at the player's last
>    tick; the live loop doesn't (`advanceOpp` loops `tick < capTicks`). Seed "final-tick-1132", Elite:
>    live bot 77464, server 77470. Please make the live loop process the final tick like `SpellSim`
>    (no server change), and add a regression test comparing the live bot's hash with
>    `verifySpellMatch(...).bot`.
> 2. Input after an incoming top-out: if garbage tops the player out at the start of a tick, the first
>    key of that tick is still logged (`applyCode` logs before the `gameOver` check) and the server
>    flags `inputs_after_topout` for an honest player. Seed "topout-6": tick 630. Please skip the input
>    drain and the cast queue when the player is already topped out, and add a regression test that
>    expects no reasons.
> 3. `decideOutcome`: the comment says both forfeits are a draw, the code compares scores. Which is
>    intended?
> 4. SR1 can't carry Spell Battle results. If you want WoW vs-Bot Spell Battles importable, please
>    review the SR2 draft in the WoW repo's `docs/SR2_DRAFT.md`; nothing is built until you agree.
>    A valid replay alone must not give ranked rating or rewards (server-issued seeds, one submission each).
> Don't change ENGINE_VERSION for 1 and 2 (no server result changes). Report back which commit fixes them.
