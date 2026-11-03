# Guild Duels (was Challenge Friends; 0.6.0 on `multiplayer`, 0.6.1 on `feature/connected`; NOT tested in a real client)

`/sr` → **Guild Duel** → pick a mode (Duel 2:00, Duel 3:00, Spell Duel) → pick a list → **Refresh** →
**Challenge** → the rival gets the usual popup (Accept / Decline) → lobby (Spell Battle: Pick
Spells) → Ready → shared countdown → duel → result → Rematch.

It reuses the duel protocol from 0.5 unchanged (invite / accept / ready, seed commit-reveal, live
score, replay check, shared combat pause, timeouts, verdict exchange, disputes, forfeit, rematch).
Only the way you *find* someone is new.

## Lists

| Tab | Where the names come from | How "has StackRivals" is found out |
|---|---|---|
| **Guild** | the guild roster (`GetGuildRosterInfo`, online members only; the roster is refreshed with `C_GuildInfo.GuildRoster` when the sheet opens) | Refresh: **one** `HEL` to the GUILD channel, every StackRivals answers `HI` by whisper |
| **Friends** | your WoW friends list (`C_FriendList.GetFriendInfoByIndex`) | Refresh: one hidden addon whisper (`HEL`) to each **online** friend |
| **Battle.net** | Battle.net friends who are on WoW right now (`BNGetNumFriends`, `C_BattleNet.GetFriendAccountInfo` → `gameAccountInfo`) | Refresh: one `HEL` to each friend on the same WoW version (`wowProjectID`): by addon whisper on your realm or a connected one (`GetAutoCompleteRealms`), **over Battle.net game data on any other realm** (0.6.1) |
| **Group** | your party / raid (`GetNumGroupMembers`, `UnitName`) | Refresh: one `HEL` to PARTY / RAID |
| **Recent** | the rivals in your duel history | Refresh: one `HEL` whisper each (a whisper to someone offline is hidden) |
| **By name** | type `Name` or `Name-Realm` | the challenge itself (as `/sr duel Name`) |

**Rules that keep it quiet and fair**

- **Nothing is sent until you click.** Opening the sheet or switching lists sends nothing (a test checks it). Refresh asks each player at most once a minute and at most 20 per click; the guild / group question is a single broadcast with a 20 s cooldown.
- **"Ready" only after their addon answered.** Being online or in your guild never makes someone challengeable; only their StackRivals' own `HI` does (with its version: Spell Battle needs 0.5+).
- **Invites only by your click.** No automatic or repeated invites; a declined invite is remembered and answered with "declined".
- **Your ignore list is respected:** ignored players are not listed, never asked, never answered (they can't see you have StackRivals) and their invites never pop up.
- **Battle.net:** only the character name is used to whisper. The temporary game account ID is never stored or used as an identity. No Battle.net tag is shown.

## Communication channels: what works, what is tested

| Connection | Transport | Simulated (tests) | Real WoW client |
|---|---|---|---|
| Two guild members, same realm | addon whisper + GUILD broadcast | yes | **not yet tested** |
| Two WoW friends, same realm | addon whisper | yes | **not yet tested** |
| Party / raid | addon whisper + PARTY broadcast | yes | **not yet tested** |
| Battle.net friends, same WoW version, same or connected realm | addon whisper to the character | yes | **not yet tested** |
| Battle.net friends on another realm (not connected) | **0.6.1:** `C_BattleNet.SendGameData` (or `BNSendGameData` on older clients) / `BN_CHAT_MSG_ADDON`; without the API: listed as "other realm" | yes (full duel, presence, Quickplay, chat) | **not yet tested** |
| Different WoW versions (e.g. Classic Era ↔ Retail) | not possible with whispers; Battle.net game data may or may not cross versions | listed as "other WoW version" | not built, not promised |
| Different factions, same realm | addon whispers across factions are expected to work for addon messages, but this must be tested | no | **unknown** |
| WoW ↔ stackrivals.io | not possible from inside WoW (no internet API) | – | – |

## Battle.net transport (0.6.1, `StackRivals/Net/BNet.lua`, BUILT, SIMULATED)

* **APIs**, documented only (warcraft.wiki.gg, checked November 2026):
  * `C_BattleNet.SendGameData(gameAccountID, prefix, data)` → `Enum.SendAddonMessageResult`.
    Present in Retail 12.0.0+, **Forever 1.60.1**, **Classic Era 1.15.9**, TBC 2.5.6 and Mists 5.5.4.
  * `BNSendGameData(gameAccountID, prefix, text)` on older clients (max 4078 bytes, deprecated in 12.0.0).
  * Receiving: `BN_CHAT_MSG_ADDON(prefix, text, "WHISPER", senderID)`.

  The wiki notes that delivery order is not guaranteed when many messages go to one player. The
  duel protocol already copes with that: chunk numbers, repeats, acknowledgements.
* **When it is used.** Only for a whisper to a Battle.net friend whose realm a normal addon whisper
  can't reach. Same-realm and connected-realm friends keep the whisper. It uses the same message
  queue and rate limits, so it covers everything:
  * presence (`HEL` / `HI`);
  * invites, live score, logs and verdicts;
  * Quickplay `QS`;
  * cards (`PRF`) and match chat.
* **Identity.** Everyone is "Name-Realm" as the friend list reports it.
  * The temporary `gameAccountID` lives in memory only, is re-read from the friend list (every
    10 s and on `BN_FRIEND_INFO_CHANGED`), and is never saved, shown or used as an identity.
    A test scans SavedVariables for this.
  * A message from an ID that isn't a current Battle.net friend on WoW is dropped.
* **Chat across factions.** Battle.net friends may already write to each other across factions
  with Battle.net whispers, so a match that runs over Battle.net allows text chat. Over a normal
  whisper, quick messages only.
* **Not used for** different WoW versions (`wowProjectID`): still listed as "other WoW version",
  and not promised.
* **Needs a real test:**
  * that it delivers in Classic Era and in Forever;
  * the real rate limit;
  * order under load;
  * behaviour after `/reload` (the IDs change).

## Test with two real players

See `docs/SPELL_BATTLE_TEST.md`, procedure C.
