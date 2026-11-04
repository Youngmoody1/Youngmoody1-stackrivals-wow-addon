# Loot Duel (0.7.1, branch `feature/loot-duel-raid`; SIMULATED, not tested in a real group)

A party or raid settles who gets an item with one short StackRivals race instead of `/roll`.
**2–10 players race at the same time** on the same pieces: one race, no 1v1 rounds, no waiting
between matches. **It only decides a winner. It never touches loot.** The loot master (or whoever
the group's rules say) hands out the item in WoW by hand. It is separate from Quickplay and
duels: never ranked, never on the website, no gold, no bets, no Shards.

What changed from 0.7.0 dev: up to 10 players (was 8), a start that fits in 2 messages (was up to
10), Invite Party / Invite Selected / Invite All, level, class, raid group and StackRivals status
in the list, items from the loot window, a live list of all players beside the window, Loot Duel as
a main card in the menu, and a small Loot Duel button near the group frames.

## How it works

**Open → item → invite → Join → Start → race → result.** Typically 5 clicks for the leader.

1. **Open it.** The **LOOT DUEL** card in the main menu, the small gold **Loot Duel** button near
   the group frames (in a party or raid), or `/sr loot`. Opening sends nothing.
   * Anyone can open it. Only the party leader, the raid leader, a raid assistant or the master
     looter can create one.
   * Opening the lobby as the leader asks the group once (one hidden PARTY / RAID message, at most
     every 20 s) which members have StackRivals. That is not an invite.
2. **Pick the item.**
   * **From loot**: when a loot window is open, one click takes an item from it (uncommon or
     better; click again for the next one). It only reads the loot window; nothing is looted.
   * Or shift-click the item while the box has focus, paste its link, or type its item ID.
   * The sheet shows the name in its quality colour, the icon and the WoW tooltip on hover.
     A long name is cut with "…" on one line. An item the client hasn't seen yet shows a
     question-mark icon until WoW has loaded it (`C_Item.RequestLoadItemDataByID`, then
     `GET_ITEM_INFO_RECEIVED` refreshes the sheet).
3. **Pick the time.** **1:00** (default) or **2:00**.
4. **Invite.** The group is listed with name (class colour), level, class, raid group and
   StackRivals status (**StackRivals** / **old StackRivals** / **no answer yet** / **offline**);
   the tooltip adds the faction. Ten names per page; a 40-player raid has 4 pages.
   * **Invite Party (5)**: one click invites everyone online in your party, you included.
   * **Invite All (n)**: in a raid of up to 10 online. It asks you to **confirm with a second
     click**. Hidden when more than 10 are online.
   * **Invite Selected (n)**: tick 2–10 players, then invite. An 11th tick is refused.
   * **Nobody is entered automatically.** An invite is only a question: each player clicks
     **Join** or **Pass** in a popup (item, leader, time, "Join = you accept the result. The loot
     master hands out the item.", a 60 s bar). No answer = not in. The leader's own click on
     Invite counts as the leader's own Join when the leader invited themselves.
   * Being in the group doesn't make anyone eligible: the leader picks who wants the item **and may
     get it under the group's loot rules**. The addon never guesses that from the class.
   * Joining sends only a **commitment** to a secret seed share, not the share itself.
5. **Joined / Invited / Passed / Ready.** The leader's list shows each player as **joined**,
   **invited…**, **passed**, **no answer: normal loot instead**, then **locking in…** and
   **ready**, plus "Joined n of m".
   * With fewer than 2 joined the button reads **Start: needs 2** and can't be pressed (the core
     refuses it too). After 80 s it reads **Invite expired**: nobody waits forever.
   * Clear errors instead of silence: not in a group, not the leader / assistant / master looter,
     no item, fewer than 2 or more than 10, already running, in a duel, in combat.
6. **Start (n).** The leader starts with everyone who joined (2–10).
   * One message (`LDQ`) fixes the player list and everyone's commitment. Every PC checks it
     against the answers it saw itself: a changed commitment or an uninvited player cancels the
     race; a player who joined but was left out is told so on screen.
   * Each player's addon reveals its seed share (`LDN`, automatic: this is the ready check). The
     leader relays all of them and reveals its own share, committed in the offer, in one
     message (`LDW`).
   * If any share is missing after 20 s, the **whole race is cancelled** and the leader starts
     a new one. Nobody can re-roll the pieces by leaving someone out, and nobody waits forever.
7. **Race, all at once.** Everyone gets the **same pieces** and **no spells**, with the same 3 s
   countdown.
   * The game runs in real time, as in duels: a low frame rate never slows a run down.
   * Pauses (combat, chat) are allowed but limited to **15 s in total**. Past that the run ends
     where it is, and that score counts.
   * **Live list beside the window** (never over the board): all players by score, in class
     colours, your own row marked, each with **playing**, **topped out**, **finished**,
     **no signal**, **disconnected**, **checked** or **replay failed / no result: out**. Live
     scores are marked provisional until replayed. The small panel under NEXT shows your place
     ("#3 of 10").
   * While you're in a Loot Duel (joined, locking in or racing), duel invites are answered "busy";
     Quickplay, duels and solo starts wait.
8. **Results.** Every addon sends its final score and its full input log. **Every PC replays every
   run.**
   * Ranking: replay-checked results by score, then lines; still equal at the top = **TIE** (roll
     off with `/roll`). Equal results share a place.
   * Results that don't count (no result, replay failed) are listed apart under **NOT COUNTED** and
     can't win. Nobody wins because someone else dropped out, and no result is invented.
   * The replay uses the same checks as duels and the website (`Engine/Verify.lua`): time cap,
     input rate (at most 4 inputs per tick), no inputs after a top-out, and the claimed score,
     lines, level and hash.
9. **Announce.** The leader can click **Announce** to post one line in party or raid chat. Nothing
   is posted without that click.
10. **Hand out the item.** In WoW, by hand, as the group's loot rules allow. If the normal loot is
    already over (the item was rolled, looted or can't be traded), Loot Duel can't change that,
    and the screen never promises the item.

## Main menu and quick access

| Before (0.7.0) | After (0.7.1) |
|---|---|
| Classic, Time Trial, **Daily Challenge** (big cards) | Classic, Time Trial, **LOOT DUEL** (big gold card: own gem icon, "Compete for raid loot", "Create Loot Duel") |
| QUICKPLAY bar | QUICKPLAY bar (unchanged) |
| Spell Battle, Guild Duels | Spell Battle, Guild Duels (unchanged) |
| Button row: How to play, Records, Account, **Loot Duel** | Button row: How to play, Records, Account, **Daily Challenge** (gold; today's best, tries and the reset time in its tooltip) |

* Daily Challenge is unchanged as a mode: same seed, records and `/sr daily`.
* The Loot Duel card's right side says what a click does: **Create Loot Duel** (you can lead),
  **Open** (a member), **Join now** (an invite for you), **Open lobby** (inviting), **Live now**
  (racing). Hover: a gold wash, no animation.
* **The quick button** ("Loot Duel" with the gem, 96 × 24): StackRivals' own plain button on the
  screen, by default top left between the player frame and the first party frame.
  * It never hooks, parents to or moves Blizzard's party or raid frames (those are protected),
    so it can't taint them or break in combat. That works the same in every client.
  * Shown only in a party or raid, hidden in combat, opens the lobby, sends nothing.
  * **Shift + drag** moves it (the place is saved); **right-click** hides it. Settings → "Loot
    Duel group button", `/sr lootbutton` and `/sr lootbutton reset` bring it back.
  * Saved: `settings.lootButton` and `settings.lootButtonPos` (new optional settings; older
    versions ignore them; a broken value is dropped on load).

## Network: the message budget

WoW gives each addon prefix **10 messages, then 1 per second**, on PARTY and RAID too
([warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage)). StackRivals
stays below that on purpose: **4, then 1 every 2 s** for group messages. The limit is per sender,
so it mostly matters for the leader.

0.7.0 dev named every player in hex in the start messages: 10 players took the leader up to 10
messages, and the start up to **31 s** (measured in the simulation). 0.7.1:

* names players by their place in the invite list: the whole list is **one** message (`LDQ`) and
  the go with every seed share is **one** message (`LDW`);
* puts the start messages ahead of queued repeats, and drops this Loot Duel's queued repeats at the
  start;
* repeats the offer only while someone hasn't answered, and the leader doesn't send its own share
  twice.

Measured in `tests/test_lootraid.lua` (simulated clients with WoW's throttle; not a real raid):

| Players | Group | Start → every run started | Messages, whole race, all PCs | Over WoW's limit |
|---|---|---|---|---|
| 2 | party of 5 | 0.6 s | 26 | 0 |
| 3 | party of 5 | 0.5 s | 36 | 0 |
| 5 | party of 5 | 0.7 s | 57 | 0 |
| 8 | raid of 10 | 0.7 s | 88 | 0 |
| 10 | raid of 10 | 0.7 s | 109 | 0 |
| 10 | raid of 40 | 0.7 s | 109 | 0 |

The simulated network is fast. Real raids add latency and other addons' traffic (other prefixes
don't share our allowance, but the server can still be slow): measure it, see the test plan below.

## Fairness, reviewed for 10 players

| Rule | How |
|---|---|
| Same pieces | One seed for everyone, made from **every** player's secret share plus the leader's. All are committed (64-bit commitments) before anyone reveals, so nobody, the leader included, knows or can steer the pieces. With 10 players there are 11 shares: one honest share is enough to make the seed unpredictable |
| Nobody steers alone | A share that doesn't match its commitment, or no share within 20 s, cancels the **whole** race. Leaving someone out to re-roll is impossible: the list (with commitments) is fixed before any share is revealed, and a left-out player is told |
| Same rules | Fixed time (1:00 or 2:00), no spells, the same countdown, the normal engine, `ENGINE_VERSION` checked |
| Can't fake a score | Every PC replays every log. A claimed score that doesn't match its log is "replay failed: out" (tested with a lying client among 5) |
| Can't add game time | The replay refuses a run longer than the time limit. A pause doesn't give extra game time |
| Disconnect | Shown as **disconnected** live. A result must arrive within the time limit + 90 s (1:00) or + 120 s (2:00). Otherwise "no result: out" (tested with 10). No automatic win for anyone |
| Thinking time | Pauses are limited to 15 s per race |
| Frame rate | Real-time stepping: 5 fps doesn't slow a run down (tested with 10) |
| Ties | Score, then lines, then a declared tie (roll off). 10 identical runs = a 10-way tie on every PC (tested) |
| No addon / old addon | "no answer: normal loot instead" / "old StackRivals". The group uses its normal loot method for them |
| Changes after the start | Not possible: list, rules and item are in the list hash, checked on every PC |
| Busy players | Someone in a StackRivals duel can't join (answered as a pass) |
| Uninvited players / fake offers | Only the leader, an assistant or the master looter can offer; offers from others or from outside the group are ignored. A place nobody was invited to cancels the race on every PC |
| Leavers | The leader's logout sends a cancel; a player's run without a result is "no result: out" |
| Bad network | Latency up to 2.5 s, 20% duplicates and 5% lost messages with 10 players: the same winner everywhere (tested) |

**What peer-checking can't catch (said on screen and here):**

* A modified addon that plays the run with a bot, or plays a perfect game. The log is valid, so
  the replay accepts it.
* A modified leader addon can refuse to start or cancel. It can't change the pieces, the list or
  anyone's score without every other PC noticing.
* Players who agree to cheat together, or let a friend play for them.
* Very slow or lost messages: a run whose log never arrives is "no result: out". Fair to the
  others, harsh for the player with the bad connection.

**Trust level (on screen):** results are **peer-checked**: good against typos, broken clients and
naive cheats, **not proof against a modified addon**. For valuable items, agree on Loot Duel only
with people you trust, as with any loot rule.

## Loot and WoW's rules

* The addon calls **no** loot API that changes anything: no `GiveMasterLoot`, no `SetLootMethod`,
  no `LootSlot`, no trade, no roll. Tests check this.
* It only **reads**:
  * who the master looter is (`C_PartyInfo.GetLootMethod`, `Enum.LootMethod` 2 = master looter,
    Classic Era 1.15.8+ and Retail 11.2+; otherwise the old `GetLootMethod`);
  * the open loot window's items for "From loot" (`GetNumLootItems`, `GetLootSlotLink`,
    `GetLootSlotInfo`);
  * item info (`C_Item.GetItemInfo` / `GetItemInfo`, `GetItemInfoInstant`) and the quality
    colour.
* **Trial and veteran accounts** can't send addon messages in WoW Forever (and modern clients from
  12.1.7) ([warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage)).
  Such a player can't join; they show as "no answer".

| Version | Loot in WoW | What that means for Loot Duel |
|---|---|---|
| Classic Era / Hardcore 1.15.x | Master loot, group loot, need / greed | The master looter hands out the winner's item. Group loot: everyone must agree to pass / roll as agreed |
| WoW Forever 1.60.x | **Not verified.** Blizzard hasn't described Forever's loot methods; a Forever guide lists master, group and personal loot as "to confirm" and says the first raids are 10 and 20 players ([guildorder.com](https://guildorder.com/th/games/wow_forever/wiki/loot-systems-for-a-10-and-a-20)). Check in the client: `/dump C_PartyInfo.GetLootMethod()` | Loot Duel only decides. Whatever WoW allows still applies. A 10-player raid fits one Loot Duel |
| Retail | Personal loot only (no master loot). Items can be traded within 2 h, to people who were eligible | The holder trades the item by hand, if it is tradeable |
| TBC / Mists Classic | Master loot exists | as Classic Era |

Blizzard doesn't settle loot disputes between players. **Agree on the rules before the raid**
(which items, which time, what happens on a tie or a disconnect), and announce them. Players
without StackRivals can always say no; the group then uses its normal loot method.

**More than 10 want the item?** Agree first who plays (for example `/roll` for the 10 places), or
run a second Loot Duel. Heats with a final are possible later as separate Loot Duels; there is no
tournament system, and nobody is entered without a click.

## Messages (group channel; 0.7.0 dev and older never see a 0.7.1 offer)

| Message | Meaning |
|---|---|
| `LDF` | offer: item, time, engine, seed commitment, number of invitees (0.7.0 dev used `LDO`) |
| `LDI` | invitee list (names as hex), as chunks |
| `LDA` | join (with a commitment to the player's seed share) or pass |
| `LDQ` | the fixed list: `<place>-<commitment>` for every player + list hash. One message for 10 |
| `LDN` | a player's seed share (checked against their commitment) |
| `LDW` | go: the leader's share, the reveal hash and every share as `<place>-<share>`. One message |
| `LDC` | live score (every 4 s, low priority) |
| `LDE` | the player's final result |
| `LDL` | the player's log, as chunks |
| `LDX` | the leader cancelled, left, or not every share arrived (sent 3 times, also at logout) |
| `LDR` | the leader's computed winner (display only: every PC computes its own) |

* `<place>` = the player's 1-based place in the invite list, which every PC has from `LDI`.
* Only the leader, an assistant or the master looter can make an offer. Offers from anyone else,
  or from outside the group, are ignored.
* All messages are ≤ 255 bytes, with the same queue and rate limits as duels. 10 players' list
  is about 225 bytes.
* Mixed versions: a 0.7.0 dev client ignores `LDF`, so it never gets stuck half-way; it shows as
  "no answer" (or "old StackRivals" once its addon has answered the presence check).

## Tests (simulated)

`tests/test_lootduel.lua` (26) and `tests/test_lootraid.lua` (21). Simulated WoW clients
(`tests/netsim.lua`) with WoW's per-prefix throttle. **Not real clients.**

* 2, 3, 5 players in a party of 5; 8 and 10 in a raid of 10; 10 in a raid of 40: same pieces,
  every PC replays every run, the same winner everywhere, within WoW's message limit.
* Invite Party (one click, 5 invited, only the leader's own click joins; 3 join, 1 passes, 1 no
  answer → 4 race). Invite All (confirm with a second click; hidden over 10 online).
* Party leader, raid leader and raid assistant may run it; a member may not.
* 10 players, one disconnects: "disconnected" live, "no result: out", one winner everywhere.
* 10 players on a bad network (latency up to 2.5 s, 20% duplicates, 5% loss) and one at 5 fps.
* 10 identical runs: a 10-way tie on every PC.
* A forged result (rejected) and a lost log (missing): never the winner, listed under NOT COUNTED.
* The live board: 10 rows in class colours, your row marked, beside the window.
* From loot: picks from the loot window, leaves grey items out, loots nothing.
* Menu: card order, the card opens the lobby and sends nothing, Daily Challenge still plays; the
  call to action follows the group.
* Quick button: hidden solo, shown in party and raid, hidden after leaving and in combat; a click
  opens the lobby and sends nothing; right-click, Settings and `/sr lootbutton`; Shift-drag saves
  the place across a reload; a broken saved place is dropped.
* Earlier: commit–reveal (R1–R9), start needs 2 (P1), 20-player raid paging (P2), protocol
  round-trips and bad messages, standings, item links, fake offers, the master looter, no addon,
  a tampered start, busy players, the whole sheet with Announce only on click.

## Test with 10 real players (needs your approval to install the dev build; back up first)

Everyone: StackRivals 0.7.1 dev, `/console scriptErrors 1`, and note realm, faction and client
version. Write down the **seconds** for each step.

| # | Do this | Expected | Result |
|---|---|---|---|
| T1 | Party of 5 in a dungeon. Leader: Loot Duel button → From loot or shift-click an item | Item with quality colour, icon, tooltip; the list shows 5 with level, class and "StackRivals" | NOT TESTED |
| T2 | Leader: **Invite Party (5)** | 4 popups. Nobody is entered except the leader | NOT TESTED |
| T3 | 3 Join, 1 Pass | Joined / passed in the leader's list; **Start (4)** | NOT TESTED |
| T4 | Start | Every run starts within a few seconds; compare the first 3 pieces on 2 screens | NOT TESTED |
| T5 | Play to the end | Live list beside the window; the same winner on every PC; Announce posts one line | NOT TESTED |
| T6 | Raid of 10: **Invite All** → confirm | 9 popups; all 10 can race at once | NOT TESTED |
| T7 | 10 race; one player `/reload`s mid-race | "disconnected" or "no signal", then "no result: out"; one winner for the others | NOT TESTED |
| T8 | Raid of 20–40: page through the list, pick 10, **Invite Selected (10)** | An 11th tick is refused; the other members get no popup | NOT TESTED |
| T9 | One player without StackRivals (or with 0.7.0) | "no answer: normal loot instead" after 60 s; the race starts without them | NOT TESTED |
| T10 | Master looter (not the leader) and an assistant each create one | Both allowed; a normal member isn't | NOT TESTED |
| T11 | Quick button: Shift-drag it, `/reload`, right-click it, `/sr lootbutton` | The place is kept; hidden; back | NOT TESTED |
| T12 | Start a race in combat / enter combat on the way | Can't start in combat; pauses count against the 15 s budget | NOT TESTED |
| T13 | Time from Invite to the result, for 2, 5 and 10 players | Note the minutes; 1:00 races should take about 2 minutes in total | NOT TESTED |
| T14 | WoW Forever: `/dump C_PartyInfo.GetLootMethod()` in a raid | Write down which loot methods exist | NOT TESTED |

Write down which loot method the group used, how long it all took, any "no signal", and any Lua
error (screenshot). That decides whether 1:00 and the 20 s reveal limit are right for real raids.
