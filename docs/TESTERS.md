# External client testers: how we cover WoW clients we don't run ourselves

You don't need every WoW client installed. Each client gets verified by **someone who plays it**,
with a 15-minute script and one copyable report line. All results go into the compatibility matrix
(`docs/COMPATIBILITY.md`) with the tester's client and build. A client is never marked verified
on a mock test alone.

## Who we need

| Client | Testers needed | Why |
|---|---|---|
| WoW Forever | you + 4 friends (a dungeon party) | priority 1; dungeon delivery (FOREVER.md F2) needs 2–5 players |
| Classic Era (+ 1 Hardcore, + 1 Season of Discovery character) | you (+ 1 friend for duels) | priority 1 |
| Retail (Midnight) | 1 solo + 1 pair | the strictest addon rules (secrets, lockdown) |
| TBC Anniversary | 1 solo + 1 pair | many players on Anniversary realms |
| Mists Classic | 1 solo | – |
| Titan Reforged (China) | 1, if anyone can be found | no access from the EU |

Where to find them:
* your Discord (a #testers channel with this file pinned);
* guild mates who already play that client;
* the CurseForge Beta's comments, once the Beta is public.

Testers get the **Alpha / Beta ZIP** (or the CurseForge Beta channel) and a short thank-you in the
changelog, if they want one. Nothing is paid and nothing is required.

## The tester's script (15 minutes, any client)

1. Install: unzip into the client's `Interface\AddOns\` (see `docs/TROUBLESHOOTING.md` for the
   folder). Restart the game fully.
2. `/console scriptErrors 1` (show Lua errors), then `/reload`.
3. `/sr version`: write down the line.
4. Play 2 minutes of Classic, one Time Trial, the Daily, and 1 minute of Spell Battle vs Bot.
5. Fight a mob while playing: the game pauses and your keys go back to WoW.
6. `/reload` mid-game → **Continue last run**.
7. In a group (if possible): `/sr commtest`, then a Guild Duel, and a Loot Duel with 2–5 players.
8. `/sr report` → click the box → Ctrl+C → paste it into the report below.

## Report template (CurseForge comment, GitHub issue or Discord)

```
Client + realm type: (e.g. Retail EU, Classic Era Hardcore)
/sr report line: SRDIAG1;...
What worked: (1-8 above)
What didn't: (what you did, what you expected, what happened)
Lua error text (first lines), if any:
Screenshot: (optional; crop names and chat)
```

The `/sr report` line has no character, realm or chat data. `python3 tools/diag_report.py "<line>"`
turns it into a readable table, with the usual causes flagged: an unknown interface number, a
lockdown, a trial account, throttling, a commtest with no answers, errors.

## What we do with a report

| Report shows | We do |
|---|---|
| Interface not in the TOC | add it to `tools/clients.json` and the TOC, then release 0.8.x |
| Lua error | fix it with a regression test (a mock profile of that client) |
| A missing API (`api=` has a 0 the profile didn't expect) | correct the profile in `tests/clients.lua`, add a fallback |
| commtest: nobody answers | check the lockdown state and reason; if nothing explains it, it's a real limit: document it as "Limited" |
| Everything fine | the matrix cell becomes "client-tested", with the build and date |

## Privacy

* We ask for no account, character, realm or chat data. The report line holds none.
* Screenshots: testers crop names and chat.
* Tester names appear in the changelog only if they ask for it.
