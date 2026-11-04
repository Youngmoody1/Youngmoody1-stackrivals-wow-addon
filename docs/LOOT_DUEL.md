# Loot Duel (0.7.0, branch `feature/loot-duel`; SIMULATED, not tested in a real raid)

The raid or party can settle who gets an item with a short StackRivals race instead of `/roll`.
**It only decides a winner. It never touches loot.** The loot master (or whoever the group's
rules say) hands out the item in WoW by hand. It is separate from Quickplay and Duels: never
ranked, never on the website, no gold, no bets, no Shards.

## How it works

1. **Open it.** The leader, a raid assistant or the master looter opens **Loot Duel** from the menu.
2. **Pick the item.** Shift-click it while the box has focus, paste its link, or type its item ID.
   The sheet shows the name in its quality colour, the icon and the WoW tooltip on hover.
3. **Pick the time and the players.** Choose **1:00** (default) or **2:00**, and 2–8 group members.
   You can include yourself.
4. **Invite.** Each player gets a popup with the item, the time and the rules, and clicks **Join**
   or **Pass**.
   * Nobody is entered automatically.
   * No answer within 60 s counts as not in.
   * A player whose addon never answers is marked "no StackRivals: /roll instead".
   * Joining sends only a **commitment** to a secret seed share, not the share itself.
5. **Start (n).** The leader starts with everyone who joined (at least 2), within 80 s of the
   offer. After that the invite has expired and a new one is needed.
   * The player list (names + commitments) and the rules are fixed at the start.
   * Every PC checks the list against the answers it saw itself:
     * a changed commitment cancels the race;
     * an uninvited name cancels the race;
     * a player who joined but was left out is told so on screen.
6. **Lock in the pieces.** Every player reveals their seed share. The leader relays them all and
   reveals its own share, which was committed in the offer.
   * Every PC checks each share against its commitment.
   * If anyone's share is missing after 20 s, the **whole race is cancelled**. Nobody can re-roll
     the pieces by leaving someone out.
7. **Race.** Everyone gets the **same pieces** and **no spells**.
   * Live scores show in the side panel.
   * Your run ends at the time limit, or earlier if you top out.
   * The game runs in real time, as in duels: a low frame rate never slows your game down.
   * Pauses (combat, chat) are allowed but limited to **15 s in total**. Past that, your run ends
     where it is, and that score counts.
   * While you're in a Loot Duel (joined, locking in or racing), duel invites are answered "busy".
     Quickplay, duels and solo starts wait.
8. **Results.** Every addon sends its final score and its full input log.
   * **Every PC replays every run.**
   * Ranking:
     1. replay-checked results, highest score first;
     2. on equal score, more lines;
     3. still equal at the top: **TIE** (roll off with `/roll`).
   * A run with no result (disconnect, offline, too late) or a failed replay is **out**. Nobody
     wins because someone else dropped out, and no result is invented.
   * The replay uses the same checks as duels and the website (`Engine/Verify.lua`): time cap,
     input rate (at most 4 inputs per tick), no inputs after a top-out, and the claimed score,
     lines, level and hash.
9. **Announce.** The leader can click **Announce** to post one line in party or raid chat. Nothing
   is posted without that click.

## Fairness

| Rule | How |
|---|---|
| Same pieces | One seed for everyone, made from **every** player's secret share plus the leader's. All are committed (64-bit commitments) before anyone reveals, so nobody, the leader included, knows or can steer the pieces. A missing share cancels the race |
| Same rules | Fixed time (1:00 or 2:00), no spells (random or offensive spells shouldn't decide an epic), the normal engine, `ENGINE_VERSION` checked |
| Can't fake a score | Every PC replays every log. A claimed score that doesn't match its log is "replay failed: out" (tested with a lying client) |
| Can't add game time | The replay refuses a run longer than the time limit. A pause doesn't give extra game time |
| Disconnect | A result must arrive within the time limit + 90 s (1:00) or + 120 s (2:00): logs travel slowly on the group channel. Otherwise "no result: out". There is no automatic win for the others |
| Thinking time | Pauses are limited to 15 s per race. Past that, the run ends where it is |
| Frame rate | The race runs in real time (like duels). Capping your FPS doesn't slow your game down |
| Ties | Score, then lines, then a declared tie (roll off). Settled before the start and shown in the popup |
| No addon | Shown as "no StackRivals: /roll instead". The group decides how to include them (the usual fallback is `/roll`) |
| Changes after the start | Not possible: the list and the rules are checked against the start's hash on every PC |
| Busy players | Someone in a StackRivals duel can't join (answered as a pass) |

**Trust level (shown on screen):** results are **peer-checked**. Every PC replays every run. That
catches typos, broken clients and naive cheats, but it is **not proof against a modified addon**
(for example a bot playing the run). For valuable items, agree on Loot Duel only with people you
trust, as you would with any loot rule.

**Time limit:** 1:00 is the default.

* A 1:00 race with a 3 s countdown and the result exchange takes about 1.5 minutes. That is short
  enough between pulls.
* 2:00 is there for bigger items.
* We haven't measured this in a real raid yet. See the test plan below.

## Loot and WoW's rules

* The addon calls **no** loot API that changes anything. No `GiveMasterLoot`, no
  `SetLootMethod`, no trade, no roll. A test checks this.
* It only **reads** who the master looter is, so the master looter can run a Loot Duel:
  * `C_PartyInfo.GetLootMethod`, with `Enum.LootMethod` 2 = master looter. Classic Era 1.15.8+
    and Retail 11.2+.
  * Otherwise the old `GetLootMethod` (`"master"`), removed in Classic Era 1.15.8.
* Item info comes from `C_Item.GetItemInfo` / `GetItemInfo`, plus `GetItemInfoInstant` for the
  icon. The quality colour comes from `C_Item.GetItemQualityColor` / `ITEM_QUALITY_COLORS`, with
  WoW's own values as the fallback.

| Version | Loot in WoW | What that means for Loot Duel |
|---|---|---|
| Classic Era / Hardcore 1.15.x | Master loot, group loot, need / greed | The master looter hands out the winner's item. Group loot: everyone must agree to pass / roll as agreed |
| WoW Forever 1.60.x | **Not verified.** It is a new client. Check which loot methods it has | Loot Duel only decides. Whatever WoW allows still applies |
| Retail | Personal loot only (no master loot). Items can be traded within 2 h, to people who were eligible | The holder trades the item by hand, if the item is tradeable |
| TBC / Mists Classic | Master loot exists | as Classic Era |

Blizzard doesn't settle loot disputes between players. **Agree on the rules before the raid**
(which items, which time, what happens on a tie or a disconnect), and announce them.

## Messages (group channel, ignored by older clients)

| Message | Meaning |
|---|---|
| `LDO` | offer: item, time, engine, seed commitment, number of invitees |
| `LDI` | invitee list, as chunks |
| `LDA` | join (with a commitment to the player's seed share) or pass |
| `LDP` | the final player list (names + commitments) |
| `LDS` | the list is fixed (list hash): reveal now |
| `LDN` | a player's seed share (checked against their commitment) |
| `LDV` | the leader relays every share |
| `LDG` | go: the leader's share (committed in the offer) |
| `LDC` | live score |
| `LDE` | the player's final result |
| `LDL` | the player's log, as chunks |
| `LDX` | the leader cancelled, left, or not every share arrived (sent 3 times, also at logout) |
| `LDR` | the leader's computed winner (display only: every PC computes its own) |

* Only the leader, an assistant or the master looter can make an offer. Offers from anyone else,
  or from outside the group, are ignored. A test checks this.
* Names travel as hex.
* All messages are ≤ 255 bytes, with the same queue and rate limits as duels.

## Tests (simulated, `tests/test_lootduel.lua`, 24)

An independent review (4 Nov 2026) found 8 problems. All are fixed, and each has its own test
(R1–R9): commit–reveal, the left-out player, a missing share, expiry, the last finisher,
frame rate, busy, inhuman logs, the leader reloading, the pause budget, and a lossy, reordering
network. The original tests cover:

* Protocol round-trip and malformed messages.
* Standings: the score / lines / tie rules; a rejected run comes last.
* Item links and quality colours; class colours from the roster.
* A full race with 3 invitees (2 join, 1 passes): the same seed everywhere, every PC replays every
  run, the same winner everywhere, and no loot API called.
* A forged score is rejected on every PC.
* A disconnect means out after the deadline, and a winner is still decided.
* Fake offers from members are ignored; the master looter can run it.
* No addon → "/roll instead".
* A tampered start is refused.
* A busy player is answered as a pass.
* The whole sheet: pick players, invite, join from the popup, start, the result banner, and
  Announce only on click.

## Test with a real group (needs your approval to install the dev build; back up first)

Use 3–5 players in one party (then a raid), all with build 0.7.0.

| # | Do this | Expected | Result |
|---|---|---|---|
| L1 | Leader: `/sr` → **Loot Duel** → shift-click an item in your bags | The name in its quality colour, the icon, the tooltip on hover | NOT TESTED |
| L2 | Pick 3 players → **Invite** | Each gets the popup (item, 1:00, "same pieces, no spells") | NOT TESTED |
| L3 | Two click **Join**, one **Pass** | The leader's list: accepted / declined | NOT TESTED |
| L4 | Leader: **Start (2)** | Both runs start at the same time with the same pieces (compare the first 3 pieces) | NOT TESTED |
| L5 | Play to the end | The live leaderboard, then the result after a few seconds, the same winner on every PC | NOT TESTED |
| L6 | **Announce** | One line in party / raid chat | NOT TESTED |
| L7 | Next race: one player `/reload`s mid-race | That player is "no result: out"; the others still get a winner after the time limit + 60 s | NOT TESTED |
| L8 | A player without the addon | "no StackRivals: /roll instead" after 60 s | NOT TESTED |
| L9 | In a 20+ player raid: time an invite → result | Note the minutes, and any lag or "slow" messages | NOT TESTED |
| L10 | Master looter (not the leader) opens Loot Duel | Allowed | NOT TESTED |

Write down which loot method the raid used and how long the whole thing took. That decides
whether 1:00 is the right default.
