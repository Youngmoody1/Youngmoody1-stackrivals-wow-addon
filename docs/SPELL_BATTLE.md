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
| log codec | `H`–`P`, `Z` + landings | cast codes 100–108 (moves stay `A`–`G`); after `Z`: where each rival spell landed, `<tick36>.<castTick36><Q..Y>` |

Classic duels (`b120`, `r180`) send exactly what 0.4 sends: `RDY` without a loadout, and the same
log letters. So 0.4 and 0.5 clients still play score races together. A 0.4 player is shown as
"needs 0.5.0" for Spell Battle, and the challenge is refused before it is sent. A 0.4 client could
not decode an `s180` invite anyway.

**Message load.** On top of the classic duel, a Spell Battle adds 3 whispers per spell cast on the
rival. The 3 s cooldown keeps this at one cast per 3 s at most.

**Live play.**

- A rival spell lands on your board at its cast tick + 90 on **your** clock. If your clock is already past that point (lag, or the rival paused or started earlier), it lands as soon as it arrives.
- Spells are checked against what can be known live: the spell must be in the rival's announced loadout and aimed at you, at most one may arrive per cooldown, and none after 3:00. Anything else is refused and counted.
- Your client records **where every rival spell actually landed** on your board (tick, the cast it came from).

**Result: the receiver's board is the authority.** At the end each player sends their log
**plus their landings** (the log codec appends them after a `Z`). Both PCs then replay **both**
logs in lockstep with `Spells.verifyMatch` (host = side 1). In that replay a rival spell lands
exactly where it landed live, never at a theoretical tick. So:

- **Your replay is always exactly your live game**, whatever the lag, pauses or lost messages. The tests check this hash for hash, including 2–2.5 s lag and a mid-duel pause.
- Both PCs replay the same two logs and the same two landing lists, so they get the same scores.

On the web, a spell always lands at cast tick + 90, because the server has both logs and realtime
delivery. Landings are the WoW-duel extension that makes slow whispers safe. The result is
labelled **peer-checked**, never "verified".

**What rejects the rival's result** (they lose, reason `check_failed`):

- any verdict of the web's verification: a broken or foreign log, over the cap, inhuman input, faster than the clock, a cast the replay refuses, inputs after their top-out. With landings, an honest client never gets any of these;
- a loadout other than the one announced at Ready;
- **a spell they sent you live that their replay doesn't allow:** forged, unpaid (no mana), or not in their log;
- **a landing they report that doesn't match one of your allowed casts**, lands before cast tick + 90, or lands twice;
- **more than one of your casts never landed on their board** although you sent it at least 5 s before their run ended (a client that ignores incoming spells). One is allowed, because all three copies of a message can be lost.

**What a cheater can't do any more** (each is a test):

- **Withhold** their spells, or send them late on purpose: the spell lands where it landed on your board, and your replay is your live game.
- **Cast for free** (log and send a spell without the mana): caught.
- **Ignore your spells:** caught.

**Known limits:**

- **Delayed landing.** A modified client could still hold an incoming spell for a while before applying it, because it reports its own landings. Holding it for good is caught, and so is landing it early; a short delay is not.
- **Counter-picking.** The rival's loadout is sent at Ready. An honest client doesn't show it before GO; a modified client could read it and pick spells against it. The effect is small, because spells are generic.
- **Version check.** A Spell Battle challenge is refused before it is sent only when the rival's version is known from Find players (kept for 2 minutes). Otherwise a 0.4 client simply never answers.

## 5. Tests and parity

| Suite | What | Count |
|---|---|---|
| `tests/test_spells.lua` | The Lua port **against fixtures from the web's real code** (`tools/parity/gen-spell-fixtures.ts` at `48fdf46`), plus rule tests. Covers the rules fingerprint (spells, mana, cooldown, delivery, loadouts, bot profiles v1/v2, cast styles) and 20 classic bot games (5 levels × 2 seeds × v1/v2), input for input. It also checks the 24 mid-game boards: bomb cells, worst fit, garbage gap, stack height, every bot candidate with its score, and every effect's resulting hash. Then come 8 full 3:00 bot-vs-bot Spell Battles (hashes, mana, casts, invalid casts at 3 checkpoints, both logs, and a replay from the logs), and 10 "human" logs with random and invalid casts run through `verifySpellMatch` vs bot and vs each other. Last, 16 tampered logs, one for each verdict the web gives. | 66 |
| `tests/test_spellbattle.lua` | vs Bot in the WoW API mock. The live game equals the verification at 3 levels; the match ends when decided (win at once / "beat N to win" / bot plays on / 3:00), with no input or casts after the end. Also: the keys, refused casts, combat pause, an exact /reload, garbled saved data, Pick Spells, at most 4 codes per tick after a frame hitch, and a result that is kept when the window closes while the bot finishes. | 15 |
| `tests/test_spellduel.lua` | Two simulated clients. Protocol round-trips and forged packets; the log codec with casts and landings; full duels with spells crossing and the same result on both PCs; 2–2.5 s lag and a mid-duel pause (spells land late, both replays still equal the live games); 15% loss + 30% duplicates; disconnect while a spell is on its way. Attacks: a forged spell, withheld casts, unpaid casts, a client that ignores incoming spells. Also live rule refusals, an old 0.4 peer, both top out, rematch. | 18 |
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
