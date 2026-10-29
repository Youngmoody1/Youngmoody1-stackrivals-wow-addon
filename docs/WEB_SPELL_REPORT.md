# Spell Battle in WoW: change report for the stackrivals.io project

For the web project's Claude / developers. This is read-only analysis: nothing in the web
repository was changed. Web base is `48fdf46` ("Release candidate A: Play 2.0"). The WoW branch is
`spellbattle` (addon 0.5.0 preview).

## What WoW now implements, and how it stays equal to the web

The following web code is ported to Lua and checked against fixtures generated **from your real
TypeScript**:

- `spells.ts`;
- `bot.ts` and `spell-bot.ts`;
- `verifySpellMatch`, `decideOutcome` and `botMatchDecided` from `src/lib/match/rules.ts`;
- the board effects in `engine.ts`.

The fixtures come from `tools/parity/gen-spell-fixtures.ts` and are read-only on your repo. All
values are equal: the rules fingerprint, 20 bot games per tuning version, 24 boards × every effect
and every bot candidate score, 8 full bot-vs-bot battles, 10 random "human" logs vs bot and vs
each other through `verifySpellMatch`, and 16 tampered logs (every verdict).

`tools/parity/check_web.sh <web checkout>` repeats this against any newer web commit and names
what differs. The bot's private `CAST_STYLE` / `CAST_STYLE_V1` tables are read from the source
text, because they aren't exported. If you rename them, the generator says so.

`ENGINE_VERSION` stays **1** on both sides, and no SR1 format changed.

## Findings in the web code (please review)

### 1. Live loop vs server: the final tick is processed differently

**Where.** `VersusGame.tsx` `advanceOpp` and the frame loop, against `SpellSim.step` in `spells.ts`
(used by `verifySpellMatch`).

**What happens.** `SpellSim` processes a side at `t == untilTick`: due incoming spells land, and
that side's codes run (but not gravity). The live loop never processes that tick:

- **The bot at the time cap.** `advanceOpp` loops `while (o.game.tick < Math.min(upTo, capTicks))`, so the bot never acts at tick 10800 live. The server's `SpellSim` (bot `untilTick = capTicks`) does let `actor.act()` run at t = 10800. A bot hard drop at that tick adds hard-drop points, and possibly a line clear, **on the server only**. In a close game the verified result can differ from what the player saw.
- **The player's last tick.** The server lands incoming spells due at the player's final tick (`untilTick = log.ticks`); the live loop stopped before that. This doesn't change the score, but it does change the board hash.

**WoW's choice.** WoW follows the server, because the server is the result (`SpellBattle.finalTick`).
The test `test_spellbattle.lua` "you top out: the bot plays on…" compares the live bot board with
`verifyMatch`, hash for hash.

**Suggested web fix.** Either let the live loop process the final tick the way `SpellSim` does, or
make `SpellSim` skip codes at `t == untilTick` for actors. The second changes server results, so it
would need versioning.

### 2. Live loop can log an input after a top-out caused by incoming garbage

**Where.** `VersusGame.tsx`, in the per-tick block:

```ts
const due = pendingMe.current.filter((x) => x.at <= side.game.tick);
... for (const inc of due) side = receive(side, inc);   // garbage can top you out here
for (const a of input.current.drain()) {
  side = applyCode(side, INPUT_ACTIONS.indexOf(a), toOpp); // logged even though gameOver
  ...
  if (side.game.gameOver) break;                          // checked only after the first one
}
```

**What happens.** `applyCode` appends to `side.log` before anything else. If incoming garbage tops
the player out at the start of a tick, and a key was pressed in that same tick, one entry is logged
after the top-out. `SpellSim` stops reading at the top-out, so `verifySpellMatch` reports
`inputs_after_topout` for an **honest player**. That is rare (a key press in the exact 1/60 s), but
it happens when players mash keys with a high stack.

**WoW's choice.** WoW drops that tick's keys and casts after an incoming top-out
(`SpellBattle.step`). Suggested web fix: `if (side.game.gameOver)` → skip the drain and the cast
queue for that tick.

### 3. Duels over slow transports: the receiver's landings

A spell aimed at the rival lands `DELIVERY_TICKS` (90) after the cast. If its message arrives later
than that (slow transport, or the sender paused), the receiver's live board and a replay that lands
it at cast + 90 diverge. That divergence can:

- top the receiver out earlier in the replay (`inputs_after_topout`);
- give different mana (`impossible_cast`);
- simply replay the receiver's inputs on a board they never saw.

An independent review of the WoW code showed this can be **used on purpose**: withhold your
sends, or pause, and the rival's replay score collapses.

**WoW's solution.** Each client records where every incoming spell actually landed (tick and cast
tick) and sends that list with its log. The replay lands spells only there (`Sim` players get an
optional `landings` list). The receiver's replay is therefore always its live game. Fraud checks
then cover what a cheater could still do: forged or unpaid casts that were sent live, landings that
don't match the sender's allowed casts, and ignored spells.

With realtime delivery the web may not need this. If you ever see `inputs_after_topout` or
`impossible_cast` on honest Spell Battle matches after reconnects or long frames, this is the
mechanism, and the WoW port (`Engine/Spells.lua` `Sim.step`, `Core/Duel.lua` `decideSpell`) is a
working reference.

### 4. Spell results and SR1 (proposal, not built)

SR1 codes (`SR1C` / `SR1R`) stay classic-only. Two parts are needed to import a WoW Spell Battle vs
Bot result into the web. Both stay additive, so SR1 isn't broken:

**(a) A ruleset id**, e.g. `spell3-<difficulty>`. The challenge seed is as today, and the bot
tuning is fixed by `createdAtMs`. The code would carry the loadout (4 digits) and the log with cast
codes. SR1's log alphabet would need the cast letters (`H`–`P`, as in the WoW duel protocol).

**(b) Server verification** = `verifySpellMatch({ players: [player], bot: { actor: new SpellBot(seed, diff, createdAtMs), loadout: BOT_LOADOUTS[diff] } })`.
That is exactly what WoW runs locally.

Guild-duel results stay WoW-only: both players are WoW clients, and their result is peer-checked.

## Numbers you can check

| | Web (TS) | WoW (Lua) |
|---|---|---|
| Spells / costs / targets / durations | `SPELL_INFO` | equal (fingerprint test) |
| `MANA_MAX`, `CAST_COOLDOWN_TICKS`, `DELIVERY_TICKS`, `CAST_BASE` | 20, 180, 90, 100 | equal |
| Mana per clear | `[0,1,3,5,8]` + combo | equal |
| `DEFAULT_LOADOUT` | lineBlast, bomb, garbage, blackout | equal |
| Bot tuning v2 switch | `2026-10-28T19:44:00Z` | equal (`1793216640000`) |
| `BOT_LOADOUTS`, `CAST_STYLE(_V1)` | spell-bot.ts | equal |
| Time cap / countdown | 180 000 ms / 4 000 ms | 10 800 ticks / 240 ticks |
