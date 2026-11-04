# Loot Duel (0.7.2, branch `feature/loot-duel-raid`; SIMULATED, not tested in a real group)

A party or raid settles who gets an item with one short StackRivals race instead of `/roll`.
**2–40 players race at the same time** on the same pieces: one race, no 1v1 rounds, no heats, no
waiting between matches. **It only decides a winner. It never touches loot.** The loot master (or
whoever the group's rules say) hands out the item in WoW by hand. It is separate from Quickplay
and duels: never ranked, never on the website, no gold, no bets, no Shards.

| Group | Loot Duel |
|---|---|
| 2 players | a direct duel for the item |
| 3–5 | dungeon Loot Duel (Invite Party) |
| 6–10 | small raid |
| 11–25 | big shared Loot Duel |
| 26–40 | full raid Loot Duel |

Everyone plays at once in all of them. Nobody is left out because ten have already joined.

**What changed from 0.7.1 dev (2–10):**
* Up to **40 at once**, with a start protocol that stays at 2 messages for the leader at any size.
* Over 10 players, only the runs that can win are replayed (see "Verification at 40").
* Result colours with icons, and a **CONGRATULATIONS!** screen on every participant's PC.
* The live list scrolls through all 40.
* Invite All works for up to 40 (confirmed).
* The Spell Battle "red box" fix (see the test log).

## How it works

**Open → item → invite → Join → Start → race → result.** Typically 5 clicks for the leader.

1. **Open it.** The **LOOT DUEL** card in the main menu, the small gold **Loot Duel** button near
   the group frames (in a party or raid), or `/sr loot`. Opening sends nothing.
   * Anyone can open it. Only the party leader, the raid leader, a raid assistant or the master
     looter can create one.
   * Opening the lobby as the leader asks the group once (one hidden PARTY / RAID message, at most
     every 20 s) which members have StackRivals. That is not an invite.
2. **Pick the item.**
   * **From loot**: one click when a loot window is open (reads it only, loots nothing).
   * Or shift-click the item, paste its link, or type its item ID.
   * The name shows in its quality colour, with the icon and the WoW tooltip.
3. **Pick the time.** **1:00** (default) or **2:00**.
4. **Invite.** The group is listed with name (class colour), level, class, raid group and
   StackRivals status. There are ten names per page, so a 40-player raid has 4 pages (`<` `>`).
   * **Invite Party (5)**: one click invites everyone online in your party, you included.
   * **Invite All (n)**: every online raid member, up to 40. It asks you to **confirm with a
     second click**. With more than 40 online it says so and you pick with the boxes.
   * **All** / **None** tick or clear the whole list; then **Invite Selected (n)** invites 2–40.
   * **Nobody is entered automatically.** An invite is only a question: each player clicks
     **Join** or **Pass** in a popup. The popup shows the item, the leader, the time and the text
     "Join = you accept the result. The loot master hands out the item.", with a 60 s bar. No
     answer = not in.
   * Being in the group doesn't make anyone eligible: the leader invites those who want the item
     **and may get it under the group's loot rules**. The addon never guesses that from the class.
   * Joining sends only a **commitment** to a secret seed share, not the share itself.
5. **Joined / Passed / Ready.**
   * The header counts it: "40 INVITED - 31 JOINED - 4 PASSED".
   * Each row shows **joined** (✓, green), **passed** (⊖, red), **invited…**, then **ready** while
     locking in.
   * Fewer than 2 joined: **Start: needs 2** can't be pressed.
   * After 80 s it reads **Invite expired**: nobody waits forever.
6. **Start (n).** The leader starts with everyone who joined (see "Start protocol").
7. **Race, all at once.** Everyone gets the **same pieces** and **no spells**, with the same 3 s
   countdown.
   * The game runs in real time: a low frame rate never slows a run down.
   * Pauses (combat, chat) are limited to **15 s per race**. Past that the run ends where it is.
   * **Live list beside the window** (never over the board), with 10 rows:
     * place, name in class colour, score;
     * status with an icon: **▶ playing**, **⚑ topped out / finished**,
       **⚠ disconnected / no signal**, **? checking…**, **✓ checked**, **⚠ replay failed / no
       result: out**.
     * The mouse wheel scrolls through all 40. **Your own row is pinned** at the bottom when it's
       out of view.
     * "Live = provisional, until the best runs are replayed."
8. **Results** (every PC computes them itself, from the same checked runs; see below).
   * The header appears **only once every needed replay is checked**:
     * **CONGRATULATIONS! — [Name] wins the Loot Duel!** with a trophy icon, a short glow and
       pop. It also shows the score, "#1 of n" and "highest replay-checked score"; the item, with
       its name and icon, is in the item box right above. The same text is shown on **every**
       participant's PC, not only the winner's.
     * **TIE!** (gold, "=" icon): "Ann, Ben tie at 12,450", or "9 players tie at …". The text says
       "Roll off with /roll (the agreed tiebreak). No winner is invented."
     * **NO WINNER** (amber ⚠): no checked result. "Use your normal loot rules for …".
   * Rows:

     | Row | Colour + icon |
     |---|---|
     | WINNER | green + trophy |
     | LOST | red + ⊗ |
     | TIE | gold + = |
     | PASSED | red + ⊖ |
     | NOT CHECKED (below the best 10) | amber + ? (can't win; not a defeat) |
     | NO RESULT / REPLAY FAILED | amber + ⚠ (not a defeat) |

     The name keeps its class colour. All results can be paged: 9 per page under the header, so
     40 is 5 pages.
   * A local chat line (only on your own screen) says the result. Nothing is posted to the group.
9. **Announce.** Only the leader, only by clicking **Announce**: one line in party / raid chat.
   No automatic chat.
10. **Hand out the item.** In WoW, by hand, as the group's loot rules allow. If the normal loot is
    already over (the item was rolled, looted or can't be traded), Loot Duel can't change that,
    and the screen never promises the item.

## Start protocol (0.7.2): 2 leader messages at any size

WoW gives each addon prefix **10 messages, then 1 per second**, per sender, on PARTY and RAID too
([warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage)). StackRivals
stays below that: **4, then 1 every 2 s** for group messages. The leader is the bottleneck:
with 40 players, 0.7.1's way (the full list of 40 commitments, then all 40 shares) is 4 + 3
messages, about **10 s** at our rate.

0.7.2 uses what every PC already heard:

* Every player's **join** (`LDA`, with their commitment) and **seed share** (`LDN`) go to the
  whole group anyway.
* So over 10 players, the leader sends the fixed list as **one message** (`LDS`): which places
  are in (a 40-bit mask), the list hash, and the leader's own commitment.
  * Every PC rebuilds the list from the commitments it saw itself and accepts it **only if it
    gives exactly the leader's hash**.
* Then the go is **one message** too (`LDG`): the leader's share, its own player share and the
  reveal hash. Every PC uses the shares it saw and checks the hash.
* Whoever missed a join or a share (lost message, late arrival) gets the full list (`LDQ`) and the
  full go (`LDW`) from the leader's repeats. Those were sent every time in 0.7.1.
* Repeats go out only after the previous repeat has left the send queue, so they never pile up
  behind WoW's limit.
* Up to 10 players nothing changed: the full list and go are one message each anyway.

Result for 40 (simulated): **every run started 1.0 s after Start** (0.7.1's way: 10.2 s). Tested:
a player who never heard one join, nor `LDS` / `LDG`, still starts from the full list and go, on
the same pieces.

## Verification at 40: the best 10 are replayed, not 40 × 40

0.7.1 sent every player's input log to everyone and replayed all of them on every PC (10 × 10).
At 40 that is 40 logs on the group channel and 40 replays per PC, which was too much. 0.7.2:

1. Every player sends a **claim** (`LDE`: score, lines, level, state hash, log size; one short
   message, repeated 5 times over 10 players).
2. Once the claims are known, only the **best 10 claims (ties with the 10th included)** send
   their log (`LDL`, 3–6 messages each). "Known" means every claim is in, or the race time + the
   pause budget + 5 s is over. Every PC replays only the logs it sees in its own best 10.
3. A claim that **fails its replay** (forged score) is out, and so is one **whose log never
   arrives**. The next claim moves up into the best 10 and sends its log. This continues until
   the best 10 are all checked, or the deadline (time limit + 90 s; 2:00 races + 120 s) runs out,
   plus 2 × 40 s if someone moved up.
4. Claims below the best 10 are shown as **NOT CHECKED**: listed with their score, never the
   winner. A winner is always a replay-checked run.
5. Replays run **one per frame, never while your own run is live**, so they never cost FPS
   mid-race. Each replay is 1–15 ms on this machine (texlua, simulated). A replayed log is freed
   right after its check.
6. A player who goes offline or leaves the group without a claim is out at once (a WoW
   disconnect reloads the UI and ends the run). Nobody waits the full deadline for them.

**Trust limits of this model (also on screen as "peer-checked"):**

* A run below the best 10 isn't replayed. It can't win, so a fake low score changes nothing that
  matters. Its displayed place is unverified (marked NOT CHECKED).
* A modified addon can still play with a bot, or play perfectly. The log is valid, so the replay
  accepts it. That is the same as 0.7.1.
* A modified client that claims a huge score must send a log that produces it. Every PC replays
  that log and rejects it, and the next claim moves up. Tested with 40.
* A player who withholds a claimed top log is out after the deadline. That only delays the result.
* The seed can't be steered by anyone, the leader included. All commitments are fixed (in the
  list hash) before any share is revealed. The leader's own share is committed in the offer.
  * A share that doesn't match its commitment cancels the whole race. Tested with a modified
    client among 40.
  * A player who doesn't reveal, or goes offline before revealing, also cancels the whole race.
    There is no re-roll without them: a re-roll would let someone pick between two seeds.
    The leader starts a new Loot Duel.
* One leaver can't block the others for long:
  * no answer = not in;
  * offline in the lobby = not in;
  * offline before revealing = cancelled at once, not after the full reveal time;
  * offline mid-race = out, and the others' result comes without waiting for the deadline.

## Measured (simulated clients, `tests/test_loot40.lua`; NOT a real raid)

Every simulated client runs the real addon. WoW's per-prefix throttle (10 messages, +1/s per
sender) is enforced. "Start" = from the leader's Start click until the last run started.

| Case | Group | Start | Result after the last run ended | Messages (all PCs, whole race) | Peak on the channel / one sender in 10 s | Replays per PC (max one) | Refused by WoW's limit |
|---|---|---|---|---|---|---|---|
| 2 players | party of 5 | 0.5 s | 0.2 s | 14 (0.5 KB) | 4 msg/s / 6 | 2 (1.0 ms) | 0 |
| 5 | party of 5 | 0.6 s | 0.2 s | 30 (1.2 KB) | 6 / 7 | 5 (1.6 ms) | 0 |
| 10 | raid of 10 | 0.7 s | 0.2 s | 55 (2.3 KB) | 10 / 7 | 10 (1.9 ms) | 0 |
| 15 | raid of 20 | 0.7 s | 0.6 s | 81 (2.7 KB) | 16 / 7 | 15 = best 10 + 5 tied with the 10th (2.1 ms) | 0 |
| 20 | raid of 20 | 0.7 s | 1.2 s | 106 (3.4 KB) | 22 / 7 | 20 = best 10 + ties (1.9 ms) | 0 |
| 25 | raid of 25 | 0.7 s | 1.2 s | 118 (3.8 KB) | 25 / 7 | 11 (2.1 ms) | 0 |
| **40** | raid of 40 | **1.0 s** | **1.1 s** | 181 (5.7 KB) | 39 / 8 | 14 (3.3 ms) | 0 |
| 40, bad network: latency up to 2.5 s, 20% duplicates, 5% loss; 5 players at 5 fps | raid of 40 | 52.8 s (leader had every share after 28 s) | 18.7 s | 686 (24.5 KB) | 36 / 6 | 10 (15.2 ms) | 0 |
| 40, 3 disconnect mid-race | raid of 40 | 1.0 s | 1.2 s (nobody waits for the 3) | 397 (10.5 KB) | 42 / 8 | 10 (5.8 ms) | 0 |
| 40, a forged top claim | raid of 40 | 1.0 s | 1.3 s (rejected everywhere, next one moved up) | 180 (5.6 KB) | 39 / 8 | 13 (3.3 ms) | 0 |
| 20, one member missed a join and the one-message list / go | raid of 20 | that member: 21.7 s (full list and go from the repeats) | – | – | – | – | 0 |

Simulated races are short: the test bots top out in a few seconds. A real 1:00 race adds the
minute itself. The results are the same on every PC in every case. The local numbers are from
texlua (Lua 5.3 with shims); the same tests pass on Lua 5.1 in GitHub CI (671 tests, run
`41822289833`).

* **Memory:** "+KB" is the Lua heap of *all* simulated clients together in one Lua state, about
  0.6–0.7 MB per client. A real client holds one of those.
* **CPU:** the replay times are texlua on this machine. WoW's Lua is similar in speed, but not
  measured.
* **Throttle:** no message was refused by WoW's limit in any case. The most any single sender
  sent in 10 s was well under WoW's 19 (10 + 1/s).
* **Peak channel load:** this is all senders together, about one message per player per second
  at most. Every PC receives it all. The messages are short (live scores are about 25 bytes).
* **Limits:** the simulated network is idealised (fixed latency ranges, independent loss, no
  server load), and the frame rate of the other 35 clients is ideal.

**Is 40 stable?** In the simulation, yes: every case above ends with **the same result on every
PC** and stays within WoW's message limit. Over 10 players, at most 10 (+ ties) replays happen per
PC. **Not yet shown in WoW:** that 40 real clients receive 40 players' traffic without hitches,
and how long a real raid's start and result take. No concrete technical blocker was found in the
simulation, but this is the decisive real test (test plan below). Until it has been done, 40 is
**implemented and simulated, not verified**.

## Fairness rules

| Rule | How |
|---|---|
| Same pieces | One seed for everyone from every player's committed share + the leader's committed share. One honest share makes it unpredictable |
| Nobody steers alone | Shares are checked against commitments fixed before anyone reveals. A wrong or missing share cancels the whole race (no re-roll) |
| Same rules | Fixed time (1:00 or 2:00), no spells, the same countdown, the same engine (`ENGINE_VERSION` checked) |
| Can't fake a winning score | The best 10 (+ ties) claims are replayed on every PC. A claim that doesn't match its log is out, and the next moves up |
| Can't add game time | The replay refuses a run longer than the time limit. A pause doesn't give extra game time |
| Disconnect | Shown live as **disconnected**. No claim = out (at once when offline). No automatic win for anyone |
| Thinking time | Pauses are limited to 15 s per race |
| Frame rate | Real-time stepping: 5 fps doesn't slow a run down (tested with 5 of 40 at 5 fps) |
| Ties | Score, then lines, then a declared **TIE** (roll off). Never an invented winner |
| No addon / old addon | "no answer" / "old StackRivals". The group uses its normal loot method for them |
| Changes after the start | Not possible: list, rules and item are in the list hash, checked on every PC |
| Fake offers | Only the leader, an assistant or the master looter can offer; offers from others are ignored |

## Loot and WoW's rules

* The addon calls **no** loot API that changes anything: no `GiveMasterLoot`, no `SetLootMethod`,
  no `LootSlot`, no trade, no roll. Tests check this.
* It only **reads**:
  * who the master looter is;
  * the open loot window (for "From loot");
  * item info.
* **Trial and veteran accounts** can't send addon messages in WoW Forever (and modern clients from
  12.1.7) ([warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage)).
  Such a player can't join; they show as "no answer".

| Version | Loot in WoW | What that means for Loot Duel |
|---|---|---|
| Classic Era / Hardcore 1.15.x | Master loot, group loot, need / greed | The master looter hands out the winner's item. Group loot: everyone passes / rolls as agreed |
| WoW Forever 1.60.x | **Not verified.** A Forever guide lists master, group and personal loot as "to confirm", with first raids of 10 and 20 ([guildorder.com](https://guildorder.com/th/games/wow_forever/wiki/loot-systems-for-a-10-and-a-20)). Check: `/dump C_PartyInfo.GetLootMethod()` | Loot Duel only decides. Whatever WoW allows applies |
| Retail | Personal loot only. Items can be traded within 2 h to people who were eligible | The holder trades the item by hand, if it's tradeable |
| TBC / Mists Classic | Master loot exists | As Classic Era |

Agree on the rules **before** the raid: which items, which time, and what happens on a tie or a
disconnect. Players without StackRivals can always say no.

## Messages (group channel)

| Message | Meaning |
|---|---|
| `LDH` | offer: item, time, engine, the leader's seed commitment, number of invitees (0.7.0 dev `LDO`, 0.7.1 dev `LDF`: dev builds never mix) |
| `LDI` | invitee list, chunk k (names as hex; the leader's own realm without "-Realm") |
| `LDA` | join (+ commitment) or pass |
| `LDS` | **(0.7.2, > 10)** the fixed list in one message: place mask + list hash + the leader's commitment |
| `LDQ` | the fixed list in full, `<place>-<commitment>`, chunked (10 per message) |
| `LDN` | a player's seed share |
| `LDG` | **(0.7.2, > 10)** go in one message: the leader's share, its player share, the reveal hash |
| `LDW` | go in full: every share as `<place>-<share>`, chunked |
| `LDC` | live score (every 4 s; 5 s over 10; 6 s over 20; low priority) |
| `LDE` | final claim |
| `LDL` | input log chunks (best 10 + ties only, over 10 players) |
| `LDX` | cancel / leader left / not every share arrived |
| `LDR` | the leader's computed result (display only; every PC computes its own) |

All ≤ 255 bytes, with the same queue and limits as duels.

## Tests (simulated)

These are in `tests/test_lootduel.lua`, `tests/test_lootraid.lua` and `tests/test_loot40.lua`.
**Not real clients.**

* **Load:** 2, 5, 10, 15, 20, 25 and 40 players.
  * Same pieces and one result on every PC, within WoW's limit.
  * Replays per PC = the best 10 + ties exactly; up to 10, every run.
* **Bad network with 40:** latency up to 2.5 s, 20% duplicates, 5% loss, and 5 players at 5 fps.
  One result everywhere.
* **Disconnects:** 3 of 40 disconnect mid-race. They show as disconnected / no signal, end with no
  result, and nobody wins by their absence.
* **Forged top claim among 40:** rejected on every PC; the next best move up and win.
* **Seed manipulation among 40:** a modified client reveals a share that doesn't match its
  commitment. The whole race is cancelled, nobody plays a steerable seed.
* **Leaver in the lobby:** one player who never answers or goes offline can't block the start.
* **Missed messages:** a member who missed a join and the one-message list / go starts from the
  full ones, on the same pieces.
* **Protocol:** `LDS` / `LDG` round-trip, the place mask for 1–40, and bad messages refused.
* **Earlier (still run):**
  * 10 players on 8 random bad networks;
  * Invite Party / All / Selected;
  * roles;
  * the live board;
  * From loot;
  * menu card;
  * quick button;
  * commit–reveal R1–R9;
  * standings and ties;
  * NOT COUNTED rows.

Previews (simulated, `docs/preview/24*`):

| Preview | Shows |
|---|---|
| 24 / 24a | 5-man dungeon |
| 24g | 10-player raid, all joined |
| 24d | 20-player raid, picking |
| 24h | 40-player raid after Invite All |
| 24c / 24c2 | result with WINNER / LOST / PASSED, on the winner's and a loser's PC |
| 24j | 40-player result with a TIE |
| 24i | 40-player live board |
| 24b | invite popup |

## Test with real players (needs your approval to install the dev build; back up first)

Everyone needs StackRivals 0.7.2 dev and `/console scriptErrors 1`. Note the realm, the faction
and the client version. Write down the **seconds** for each step. Steps 1–3 can be done with a
few friends; steps 4–6 need a real raid.

| # | Group | Do this | Expected | Result |
|---|---|---|---|---|
| R1 | 2 | Leader invites 1, both Join, Start, play | Same first 3 pieces on both screens; CONGRATULATIONS on both PCs | NOT TESTED |
| R2 | 5 (dungeon) | Invite Party, 3 Join, 1 Pass | WINNER green, LOST red, PASSED red on every PC; Announce posts one line only when clicked | NOT TESTED |
| R3 | 5 | One player `/reload`s mid-race | "disconnected", then NO RESULT (amber, not LOST); the others get a result without waiting ~2 min | NOT TESTED |
| R4 | 10 | Invite All → confirm, all Join, Start | Every run starts within a few seconds (write down the time); live list readable at your UI scale | NOT TESTED |
| R5 | 20–25 | Invite All, ~20 Join | Start time; result time after the race; the board scrolls; your row pinned | NOT TESTED |
| R6 | **40** | Invite All (confirm), 30–40 Join, Start | **Start time (sim: ~1 s), result time after the race (sim: ~1 s), FPS during the race, any Lua error, the same winner on 3+ screens** | NOT TESTED |
| R7 | 40 | Repeat R6 with 2 players going offline mid-race | Offline players: NO RESULT; the others' result doesn't wait for the deadline | NOT TESTED |
| R8 | any | A player without StackRivals is invited | Shown as no answer; the race starts without them | NOT TESTED |
| R9 | any | Master looter (not the leader) creates one; a normal member tries | Allowed; refused | NOT TESTED |
| R10 | Forever | `/dump C_PartyInfo.GetLootMethod()` in a raid | Write down which loot methods exist | NOT TESTED |

For R6, also write down: how many joined, the start time, the result time, FPS before / during /
after (`/fps` or the client's own counter), any "no signal", and screenshots of the result on 3
PCs. **That run decides whether 40 is called stable.**
