# Challenge Friends (branch `multiplayer`, 0.6.0, NOT tested in a real client)

`/sr` → **Challenge** → pick a mode (Blitz 2:00, 3:00, Spell Battle) → pick a list → **Refresh** →
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
| **Battle.net** | Battle.net friends who are on WoW right now (`BNGetNumFriends`, `C_BattleNet.GetFriendAccountInfo` → `gameAccountInfo`) | Refresh: one `HEL` whisper to their character, **only** if they play the same WoW version (`wowProjectID`) on your realm or a connected one (`GetAutoCompleteRealms`) |
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
| Battle.net friends on another realm (not connected) | needs `C_BattleNet.SendGameData` / `BN_CHAT_MSG_ADDON` — **not built**; listed as "other realm" | listed only | not built |
| Different WoW versions (e.g. Classic Era ↔ Retail) | not possible with whispers; Battle.net game data may or may not cross versions | listed as "other WoW version" | not built, not promised |
| Different factions, same realm | addon whispers across factions are expected to work for addon messages, but this must be tested | no | **unknown** |
| WoW ↔ stackrivals.io | not possible from inside WoW (no internet API) | – | – |

## Next step: a Battle.net transport (planned, not built)

To reach Battle.net friends on other realms: a transport adapter beside the whisper one, sending
the same duel messages with `C_BattleNet.SendGameData(gameAccountID, prefix, text)` and receiving
`BN_CHAT_MSG_ADDON`. The duel would address the rival by a session-only handle (looked up again from
the friends list after a reload; game account IDs change), never by the ID itself. It needs a real
two-client test first: whether the API exists and delivers in Classic Era / Forever, its size and
rate limits, and whether it crosses realms (and versions). Until then, those friends are shown with
the reason they can't be challenged yet.

## Test with two real players

See `docs/SPELL_BATTLE_TEST.md`, procedure C.
