# WoW Forever: what StackRivals knows, what it doesn't, and how to test it

Status on 4 Nov 2026: **nothing has been tested in the Forever client yet.**

* Forever launches tonight, 4 Nov 2026 at 23:00 UTC (00:00 Danish time).
* Your PC already has the client: `_forever_`, product `wowf`, build **1.60.1.70755**. That comes
  from the launcher's `.build.info`, read without changing anything.
* StackRivals 0.8.0 is built for Forever as its own client type. All of that is mock-tested, not
  client-tested.

## What the documentation says (sources at the bottom)

| Fact | Status |
|---|---|
| Forever is its own client type: `WOW_PROJECT_ID` = **18**, `WOW_PROJECT_CAMELOT`. It is **not** Classic Era (2) | documented (1.60.1 API changes) |
| It shares **Mainline (Retail) UI code and APIs**, "the vast majority of APIs available in 12.1.5". Midnight's addon restrictions, including secret values, are active in Forever too | Blizzard, 15 Sep 2026 |
| TOC files it looks for: `_Forever` / `_Camelot`, then `_Mainline`, then the plain `.toc` | documented (TOC format page) |
| Interface number: 16001 for Forever Beta / Test; the live row is blank on the wiki. Your build 1.60.1 matches 16001 by the usual numbering, but that is **not confirmed** | check in the client |
| Trial and Veteran accounts can't send addon messages | documented (1.60.1 build 70291) |
| First raids: 10 (Barrow Deeps), 20 (Hyjal Summit), 40 (Onyxia's Lair); raids open 9 Dec 2026 | documented (warcraft.wiki.gg "Forever") |
| Loot methods (master loot? group loot?) | **unknown**: not documented by Blizzard |

## Addon messages in instances: the important unknown

Loot Duel and every duel mode need addon messages (PARTY, RAID, WHISPER, Battle.net).

**What Blizzard said for Retail (Midnight), quoted on warcraft.wiki.gg:** sending addon messages
is restricted only while:
1. a Mythic keystone run has started and not ended;
2. a PvP match has started and not ended;
3. an **instance encounter (a boss fight) is in progress**.

An earlier alpha rule blocked addon chat in the whole instance; that was replaced. Ordinary
combat is not a trigger. Since Forever shares Midnight's restrictions, the same rules are expected
there.

**But it isn't settled.** The wiki's "Secret Values" page also lists "a communication-restricted map
such as a dungeon or raid" for the same lockdown state, and 12.0.5 added `SecretOnRestrictedMaps`.
If Forever locks addon messages for **the whole dungeon map**, a Loot Duel can't run inside a
dungeon at all, only outside or between instances. **Only the real client can answer this** (F1–F5
below).

### What StackRivals 0.8.0 does about it (no workaround, ever)

* It asks the client: `C_ChatInfo.InChatMessagingLockdown()` (locked?) and
  `C_RestrictedActions.IsAddOnRestrictionActive(...)` (why: Encounter, ChallengeMode, PvPMatch,
  **Map**, Chat). It also honours send result 11 (`AddOnMessageLockdown`).
* **While locked, every message is held, not lost.** It goes out when WoW allows it again, and it
  doesn't count as a failed try.
* **Loot Duel can't be created or started while locked.** It says why:
  * "WoW blocks addon messages right now (a boss fight, a Mythic+ run or a PvP match). Start the
    Loot Duel after it."
  * If the client reports a whole-**map** lock: "WoW blocks addon messages in this zone. A Loot
    Duel can't run here: start it outside, or use your normal loot rules."
* **A lockdown mid-race** (someone pulls a boss):
  * your run goes on (the game is local);
  * live scores and results wait;
  * every timer and deadline waits too, so nobody is "out" because WoW paused the channel;
  * the live list says "held by WoW".
  * Combat still pauses your run, as always, and pauses count against the 15 s budget. Agree
    not to pull during a Loot Duel.
* Duels and Quickplay get the same hold (no message lost during a lockdown).
* Simulated and tested (Forever profile, 10 players, a 25 s lockdown mid-race): one result
  everywhere, nobody out. This is a simulation, not the client.

## Real-client test plan: Forever (needs your approval to install 0.8.0 there, with a backup)

**Before anything:** Forever has no StackRivals folder yet (`_forever_\Interface\AddOns` doesn't
exist). An install there is new, so nothing can be overwritten. Still, I ask first.

**Solo (1 player, about 15 min):**

| # | Do this | Expected | Result |
|---|---|---|---|
| S1 | `/dump WOW_PROJECT_ID, select(4, GetBuildInfo())` | `18`, and the live interface number (write it down: if not 16001, the TOC must change) | NOT TESTED |
| S2 | AddOns list on the character screen | StackRivals ticked, not "out of date" | NOT TESTED |
| S3 | `/sr version` | "… WoW Forever 1.60.1 (…)" | NOT TESTED |
| S4 | Classic 2 min, Time Trial, Daily | as in Classic Era (keys, score, records) | NOT TESTED |
| S5 | Spell Battle vs Bot 1 min | spells work; **no red box / bar over the bot's board**; nothing blocks your board | NOT TESTED |
| S6 | Enter combat with a mob mid-game | pauses, keys go back to WoW, no Lua error | NOT TESTED |
| S7 | `/console scriptErrors 1`, `/reload` mid-run → Continue | same run, paused | NOT TESTED |

**Instances and addon messages (2+ players, the decisive part):**

**How to check delivery (0.8.1):** StackRivals' own `/sr commtest`.

* The raw API one-liner in the 0.8.0 version of this plan was not good enough, for two reasons:
  * it used a prefix that was never registered, so a receiving client would ignore it anyway;
  * a send result of 0 only means "queued", not "arrived".
* `/sr commtest` sends one ping with StackRivals' registered prefix on the group channel (PARTY /
  RAID / INSTANCE_CHAT). Every other StackRivals in the group answers on the same channel. The
  chat line then says, for example, "send result 0, 4 of 4 group members' StackRivals answered:
  Ann 0.8.1, …".
* **Only answers count as proof**: they show the message went out and came back. It also says when
  WoW reported a lockdown.
* Everyone in the group needs StackRivals 0.8.1+, and they don't have to do anything: their addon
  answers by itself.
* After each test, `/sr report` → copy the line → paste it in the test log. It holds the commtest
  result, the lockdown state and reason, the instance type and the send result codes.

| # | Where | Write down | Then (with StackRivals) | Result |
|---|---|---|---|---|
| F1 | Open world, in a party of 2–5 | `/sr commtest` → "n of n answered"; `/sr report` line | Loot Duel: Invite Party, Join, Start, race: one result on every PC | NOT TESTED |
| F2 | **Inside a dungeon, no fight going on** | `/sr commtest` (all answered = messages arrive in the dungeon); `/sr report` (`locked=0`) | the same Loot Duel inside the dungeon | NOT TESTED |
| F3 | Dungeon, **during a boss fight** | `/sr commtest` (expected: result 11 or no answers, "lockdown"); `/sr report` (`locked=1;why=encounter`) | Loot Duel Start → refused with the boss-fight reason | NOT TESTED |
| F4 | Dungeon: start a Loot Duel, then someone pulls a boss | – | "held by WoW" on the live list, runs go on, one result after the fight | NOT TESTED |
| F5 | Dungeon, ordinary trash combat | `/sr commtest` during the fight (the game pauses; the test still runs) | does trash combat lock messages? (Retail: no) | NOT TESTED |
| F6 | Raid (from 9 Dec), 10–20 players | `/sr commtest` between bosses: n of n | Loot Duel with everyone; start time, result time, FPS | NOT TESTED |
| F7 | Loot method in the group or raid | `/dump C_PartyInfo.GetLootMethod()` | which methods exist; can the leader hand out an item by hand? | NOT TESTED |
| F8 | Two Battle.net friends on different realms | – | Guild Duels → Battle.net tab → a duel (`C_BattleNet.SendGameData`) | NOT TESTED |
| F9 | A trial account in the group (if anyone has one) | – | they can't join; the reason is shown | NOT TESTED |

To check the lockdown handling without a boss, the testing switch
`/run SetCVar("addonChatRestrictionsForced","1")` forces the lockdown state (Blizzard,
1 Dec 2025). It resets when the client restarts.

**Result: F2 decides the dungeon story.**
* If F2 shows messages allowed, a 5-player Loot Duel works in Forever dungeons between pulls.
* If F2 shows `true` (whole-map lock), Loot Duel in Forever dungeons is **unsupported**. It must be
  run outside the instance, and the docs and the screen say so (it already refuses with the "this
  zone" text).

## Sources

All on warcraft.wiki.gg, checked 4 Nov 2026:
* "Forever"
* "WOW_PROJECT_ID"
* "TOC format"
* "Patch 1.60.1/API changes", which quotes Blizzard's 15 Sep 2026 post "An Update On Secrets In
  WoW: Forever"
* "Patch 12.0.0/API changes/notes", which quotes Blizzard's 11 Oct 2025 post on chat restrictions
* "Patch 12.0.5/API changes/notes"
* "Secret Values"
* "API C_ChatInfo.SendAddonMessage"
* "API C_ChatInfo.InChatMessagingLockdown"
* "API C_RestrictedActions.IsAddOnRestrictionActive"

Your client's build was read from `World of Warcraft\.build.info`. Nothing on your PC was changed.
