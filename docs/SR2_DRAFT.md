# SR2: Spell Battle result codes (DRAFT, not built)

**Status: a proposal for the stackrivals.io project. Nothing is implemented on either side.** It
waits until the web project agrees to a shared contract (field list, limits, test vectors). SR1
is unchanged: its 77 vectors still pass, and an SR1 parser already refuses spell logs.

## Why a new format, not a new SR1 ruleset

An `SR1R` code carries a classic log (moves `A`–`G`) and is checked with `verifyLog`. A Spell
Battle result needs more to be replayed: the bot level, the bot tuning, both loadouts and the cast
letters. Putting that into SR1 would make old parsers accept codes they can't check. A new prefix
makes old parsers refuse them cleanly (`format`).

## Scope of SR2 v1

- **Spell Battle vs Bot only** (`mode = spellbot`). It is a lockstep game against the web's own bot, so the server can replay it exactly: `verifySpellMatch({ players: [p], bot: { actor: new SpellBot(seed, diff, createdAtMs), loadout: BOT_LOADOUTS[diff] } })`. That is exactly what the WoW addon runs.
- **Never WoW guild duels.** They are peer-checked between two PCs, with receiver landings and whisper timing. They stay WoW-only and are never imported as verified.

## Result code (proposal)

```
SR2R.<platform>.spellbot.e<engine>.<seed>.<diff>.<tuning>.<loadout>.<ticks36>.<score36>.<lines36>.<level36>.<hash>.<botScore36>.<outcome>.<playerHex>.<link>.<log>.<check>
```

| Field | Value | Notes |
|---|---|---|
| `platform` | `wow-forever` \| `wow-retail` \| `wow-classic` | as SR1 |
| `spellbot` | the mode | the only mode in SR2 v1 |
| `engine` | `ENGINE_VERSION` (1) | as SR1 |
| `seed` | `[a-z0-9-]{1,64}` | see "Seeds and ranking" |
| `diff` | `rookie` \| `challenger` \| `contender` \| `elite` \| `rival` | the bot level |
| `tuning` | `t1` \| `t2` | the bot tuning, **explicit**. Not the client's clock: the server maps `t2` to a `createdAtMs` after the switch and refuses tunings it no longer accepts |
| `loadout` | 4 digits `0`–`8` | the player's spells, in slot order (`Spells.encodeLoadout`); the bot's loadout follows from `diff` |
| `ticks36`…`level36` | base 36, canonical | claimed; the server recomputes |
| `hash` | 8 hex | `hashState` of the player's final state (claimed) |
| `botScore36` | base 36 | the bot's final score (claimed, for display and typo detection) |
| `outcome` | `w` \| `l` \| `d` | claimed; the server decides with `botMatchDecided` / `decideOutcome` |
| `playerHex`, `link` | as SR1 | |
| `log` | as SR1, plus cast letters | moves `A`–`G` (codes 0–6), casts `H`–`P` (codes 100–108). No landings: vs Bot is lockstep |
| `check` | 8 hex, FNV-1a 32 | typo detection only, as SR1 |

**Challenge code** (if the web wants server-issued Spell Battle challenges):
`SR2C.spellbot.e<engine>.<seed>.<diff>.<tuning>.<check>`.

## Limits (both sides reject anything outside)

- The code is at most 32768 characters (as SR1). At most 4 inputs per tick, and at most one cast per 180 ticks.
- `ticks` ≤ 10800 (3:00). A log entry after the player's top-out is invalid. This is also why web bug 2 matters: an honest WoW log never has one, but the web's own live loop can produce one.
- Unknown fields, a different field count, a non-canonical number or an unknown letter: refused, never "best effort".

## Seeds and ranking: a valid replay is not enough

A valid replay proves that the game is legal for its seed. It does not prove that it is the player's
only attempt: with client-chosen seeds a player could play many seeds and submit the best. So:

- **Ranked rating or rewards only on server-issued seeds** (an `SR2C` challenge or a daily seed), with one counted submission per account and challenge. The server binds the result to an account (`link`) and refuses a second submission of the same seed.
- **Free-play seeds** (made by the addon) may be shown as "verified replay", but never ranked.
- The server keeps its existing protections (rate limits, duplicate codes, plausibility). SR2 adds nothing that bypasses them.

## Versioning

- The field set of `SR2` is frozen once both sides agree. Any change becomes `SR3`; SR2 codes must keep parsing as SR2.
- A shared `docs/vectors/sr2.json` is produced by **both** implementations before either ships: valid codes, each refusal reason, and the server verdict for each. That's how SR1 is kept equal today (77 vectors).
- SR1 parsers keep refusing SR2 (`format`), and the SR2 parser refuses SR1 the same way.

## What the WoW addon will do after agreement (not before)

- A new `Net/Codes2.lua` with the encoder and parser, beside SR1 (`Net/Codes.lua` stays as is).
- An "Export result" button on the Spell Battle result screen, for vs-Bot only.
- `tests/test_codes2.lua` against `docs/vectors/sr2.json`.

## Open questions for the web project

1. `tuning`: an explicit `t1`/`t2`, as above, or `createdAtMs`?
2. `decideOutcome`: when both forfeit, is it a draw (the comment) or a score comparison (the code)? See `docs/WEB_SPELL_REPORT.md`, note 3.
3. Ranking: do Spell Battle vs Bot results count anywhere, and only for server-issued seeds?
4. Is a 32768-character limit fine for pasting on the site?
5. Does the web want `SR2C` challenges for Spell Battle vs Bot?
