# Spell Battle in the WoW addon (branch `spellbattle`, v0.5.0 preview)

The web game's **Play 2.0 Spell Battle** ported to the addon: the same 9 spells, mana, cooldown,
delivery delay, bot and result rules as stackrivals.io (web commit `48fdf46`, "Release candidate A:
Play 2.0"). These are **StackRivals spells on StackRivals boards**. The addon never casts, targets
or binds a World of Warcraft ability, and nothing here automates WoW gameplay.

Status words as in `CROSS_PLATFORM_MULTIPLAYER.md`: **BUILT** = code + automated tests,
**SIMULATED** = tested only in a simulated WoW, **CLIENT TESTED** = ran in real WoW clients.
Nothing in this document is CLIENT TESTED yet.

## 1. What the web has, and what the addon has

| Spell | Cost | Target | Effect (web `SPELL_INFO`) | Addon |
|---|---|---|---|---|
| Bomb | 4 | you | clears 3×3 around where your piece lands | BUILT, parity-tested |
| Line Blast | 5 | you | removes your bottom 2 rows | BUILT, parity-tested |
| Freeze | 6 | you | no gravity for 5 s | BUILT, parity-tested |
| Swap | 3 | you | swaps your piece with hold (or next) | BUILT, parity-tested |
| Clear Board | 16 | you | clears your whole board | BUILT, parity-tested |
| Garbage | 4 | rival | 2 garbage rows; the gap = hash(seed, cast tick) | BUILT, parity-tested |
| Speed Up | 6 | rival | double gravity for 8 s | BUILT, parity-tested |
| Blackout | 5 | rival | hides their NEXT for 10 s | BUILT, parity-tested |
| Scramble | 7 | rival | their next piece becomes the worst fit | BUILT, parity-tested |

The shared rules, all equal to the web:

- **Mana:** 0 to 20. A clear gives 1, 3, 5 or 8 mana for 1 to 4 lines, plus the combo count.
- **Cooldown:** 3 s between casts.
- **Loadout:** 4 different spells, exactly 2 for your board and 2 for your rival.
- **Default loadout:** Line Blast, Bomb, Garbage, Blackout.
- **Delivery:** a spell aimed at the rival lands 90 ticks (1.5 s) after the cast, on the rival's clock.
- **Logging:** a cast is an entry in the input log, code 100 + spell index. A refused cast has no effect and is recorded as invalid.
- **Result:** the higher score wins.

**Web spell unlocks.** On the web, Freeze, Clear Board and Scramble are unlocked through the
account's skill tree. The web says they have the "same cost and effect as for everyone". WoW has
no StackRivals accounts, so all 9 spells are available. The verification (`verifySpellMatch`)
only checks that a loadout is valid, so this changes no rule.

## 2. Code

| File | What |
|---|---|
| `Engine/Engine.lua` | Gravity modes in `E.tick(s, gravity)` (normal / frozen / double) and the board effects `clearCells`, `removeBottomRows`, `clearBoard`, `addGarbage`, `swapActive`, `replaceNext`. Classic play never calls any of them. |
| `Engine/Spells.lua` | A port of `spells.ts`: spell info, codes, mana, loadouts, `canCast`, `applyCode`, `receive`, `stepSide`, `bombCells`, `garbageGap`, `worstFitPiece`, the lockstep `Sim`, plus `verifyMatch`, `decideOutcome` and `botMatchDecided` (ported from `rules.ts`). |
| `Engine/Bot.lua` | A port of `bot.ts` and `spell-bot.ts`: placement evaluation, `choose` / `nextAction`, tuning v1 and v2 (switch at `2026-10-28T19:44:00Z`), `generateGame`, the spell bot (casting rules, cast styles v1 and v2, loadouts per level). |
| `Core/SpellBattle.lua` | The live match: vs Bot, and the duel ("remote") variant. |
| `UI/SpellUI.lua` | The Pick Spells sheet, spell tiles, mana, rival panel, effects and Victory / Defeat. |
| `Media/Spells/*.tga` | The web's own icons, drawn from `SpellIcon.tsx` (`tools/make_spell_icons.mjs`, then `tools/png_to_tga.py`). |

## 3. Spell Battle vs Bot (BUILT, SIMULATED)

**Flow.** Menu → **Spell Battle** card → **Pick Spells** (2 + 2 spells, bot level Rookie to Rival)
→ Start → 4 s countdown → 3:00 match → Victory / Defeat / Draw → **Play again** or **Change spells**.

**Same as the web.** The live loop runs per tick, exactly like the web's `VersusGame`:

1. Incoming spells land on your board.
2. Your keys are applied, then your casts. Only castable spells are logged.
3. Your gravity step runs.
4. The bot plays the same tick.

So a live match **is** the lockstep replay of your log against the bot. The tests check this hash
for hash, at three bot levels.

**The match ends correctly** (the web's `botMatchDecided` fix):

- **The bot tops out while you lead:** the match ends at once. You get VICTORY, the timer stops, and no more input or casts are taken. Tested: nothing is logged after the end.
- **The bot tops out while you're behind or level:** you play on. The rival panel says "beat N to win", and passing that score wins.
- **You top out:** the bot plays on to 3:00, as on the web. It does so over a few frames (600 ticks per frame, no hitch) while "The bot is finishing its run…" shows. Then the result appears.
- **3:00:** the match ends for both.

**The last tick follows the server, not the web's live loop.** The web server's verification
processes each side's final tick:

- incoming spells land at that tick;
- the bot's moves at tick 10800 are applied, without a gravity step.

The web's live loop skips that tick. The addon follows the server, because the server decides the
result. See the web report, item 1.

**/reload** rebuilds an unfinished match exactly: both boards, mana, effects and pending spells. It
replays your saved log against a fresh bot from the same seed, which is the verification path.

**Keys.** Spells use **Q, E, R, F** by default, like the web. **1–4** work too, out of action-bar
habit. You can rebind them in Settings under "Spells 1-4". Like every StackRivals key, they are only
captured while a run is live. Outside a run they are WoW's own keys, and in a classic run they do
nothing.

**Records.** Wins, losses, draws and best score are kept per bot level, on this PC only. They are
never ranked.

## 4. Spell Battle between guild members (BUILT, SIMULATED)

The existing duel system is reused, not a second one:

> Challenge → **Spell Battle** (ruleset `s180`) → Pick Spells in the lobby → Ready (your spells lock) → countdown → battle → winner → Rematch.

**Protocol changes** (protocol v1, additive). Only 0.5+ clients know them:

| | Message | Notes |
|---|---|---|
| new ruleset | `s180` | Spell Duel 3:00, 4 s countdown (the web's cap and countdown) |
| extended | `1:RDY:<mid>[:<loadout>]` | the loadout is 4 spell digits, e.g. `1057`; it locks at Ready |
| extended | `1:GO:<mid>:<nonceA>[:<loadout>]` | the host's spells again (its RDY may arrive after GO) |
| new | `1:SP:<mid>:<seq>:<tick36>:<spell>` | a spell aimed at the rival, sent at once and repeated after 1 s and 3 s; the receiver drops repeats by `seq` |
| log codec | `H`–`P` | cast codes 100–108; moves stay `A`–`G` |

Classic duels (`b120`, `r180`) send exactly what 0.4 sends: `RDY` without a loadout, and the same
log letters. So 0.4 and 0.5 clients still play score races together. A 0.4 player is shown as
"needs 0.5.0" for Spell Battle, and the challenge is refused before it is sent. A 0.4 client could
not decode an `s180` invite anyway.

**Message load.** On top of the classic duel, a Spell Battle adds 3 whispers per spell cast on the
rival. The 3 s cooldown keeps this at one cast per 3 s at most.

**Live play.**

- A rival spell lands on your board at its cast tick + 90 on **your** clock. If your clock is already past that point (lag, or the rival started earlier), it lands at once and is counted as "late".
- Spells are checked against what can be known live: the spell must be in the rival's announced loadout and aimed at you, at most one may arrive per cooldown, and none after 3:00. Anything else is refused and counted.
- Mana can't be checked live, because it depends on the rival's board. The replay checks it.

**Result.** It is the web's server verification, run on both PCs: `Spells.verifyMatch` replays
**both** logs in lockstep, with the host as side 1. Both PCs replay the same two logs, so they get
the same boards and the same scores even when a spell arrived late in someone's live view. That
replay is the result, labelled **peer-checked**, never "verified".

**What rejects the rival's result** (they lose, reason `check_failed`):

- a broken or foreign log (engine, seed, malformed);
- a loadout other than the one announced at Ready;
- over the time cap, or inhuman input;
- a result faster than the clock;
- a cast the replay can never allow: cooldown, not in the loadout, or an unknown code;
- **more than 2** casts without enough mana;
- **a spell sent live that isn't a cast in their log** (a forgery).

**Not counted against anyone:**

- "inputs after top-out";
- up to 2 casts without mana.

A spell that reached a board late in the live view can change that board in the replay. The replay
then ignores those inputs, which can't help anyone. This is a WoW-specific choice: the web has
realtime channels and a 1.5 s delivery margin, and it counts every reason as fraud. See the web
report, item 3.

**Known limits**, all documented and shown to the player:

- **Combat pause.** A combat pause stops only your own clock. Your later casts then reach the rival after their landing tick, so their live view differs from the replay. The replay decides, and the result screen says "A spell reached a board late…".
- **Counter-picking.** The rival's loadout is sent at Ready. An honest client doesn't show it before GO; a modified client could read it and pick spells against it. The effect is small, because spells are generic.

## 5. Tests and parity

| Suite | What | Count |
|---|---|---|
| `tests/test_spells.lua` | The Lua port **against fixtures from the web's real code** (`tools/parity/gen-spell-fixtures.ts` at `48fdf46`), plus rule tests. Covers the rules fingerprint (spells, mana, cooldown, delivery, loadouts, bot profiles v1/v2, cast styles) and 20 classic bot games (5 levels × 2 seeds × v1/v2), input for input. It also checks the 24 mid-game boards: bomb cells, worst fit, garbage gap, stack height, every bot candidate with its score, and every effect's resulting hash. Then come 8 full 3:00 bot-vs-bot Spell Battles (hashes, mana, casts, invalid casts at 3 checkpoints, both logs, and a replay from the logs), and 10 "human" logs with random and invalid casts run through `verifySpellMatch` vs bot and vs each other. Last, 16 tampered logs, one for each verdict the web gives. | 66 |
| `tests/test_spellbattle.lua` | vs Bot in the WoW API mock. The live game equals the verification at 3 levels; the match ends when decided (win at once / "beat N to win" / bot plays on / 3:00), with no input or casts after the end. Also: the keys, refused casts, combat pause, an exact /reload, garbled saved data, Pick Spells. | 13 |
| `tests/test_spellduel.lua` | Two simulated clients. Protocol round-trips and forged packets; the log codec with casts; full duels with spells crossing and the same result on both PCs; 2–2.5 s lag (late spells, the live view differs, the result still agrees); 15% loss + 30% duplicates; a forged spell (caught); live rule refusals; an old 0.4 peer; both top out; rematch. | 12 |
| Existing suites | Classic, Blitz, Daily, duels, SR1, design: unchanged and passing. The 77 SR1 vectors are unchanged (Spell Battle doesn't touch SR1). | |

`tools/parity/check_web.sh <web checkout>` now also regenerates the spell fixtures and runs
`test_spells.lua`. That way any later web change to spells or the bot is caught and named.

**ENGINE_VERSION stays 1.** The web did not bump it for Play 2.0: the core engine rules are
unchanged, and the spell effects are separate functions that classic play never calls. A Spell
Battle is identified by its ruleset (`spell` on the web, `s180` in WoW duels), not by an engine
version. SR1 codes are unchanged. Spell results are not exported as SR1 yet: see the web report,
item 4.

## 6. What still needs a real WoW client

- **Look and feel** in a real client: spell icons (TGA), the mana bar, tiles and cooldown curtain at different UI scales, effect flashes, tooltips, the Pick Spells sheet, Victory / Defeat. The previews in `docs/preview` are simulated.
- **Q / E / R / F / 1–4** during a run, and that they are WoW's own keys again after the run. The keyboard-propagation rules are the same as for every StackRivals key, but they need a real check.
- **Performance** in a real client. Measured outside WoW: a bot decision about 1.4 ms per new piece; both bots at full speed 0.05 ms per tick; about 5 KB garbage per bot decision. The fast-forward after your top-out runs at 600 ticks per frame.
- **Spell duels between two real clients:** SP delivery time over whispers (it should stay under 1.5 s), a combat pause mid-match, `/reload` in a spell duel (handled like in a score-race duel), and an old 0.4 client in the guild. See `docs/MULTIPLAYER_TEST.md`.
- Nothing is Forever-verified. 0.3.1 remains the release candidate for the first client test.
