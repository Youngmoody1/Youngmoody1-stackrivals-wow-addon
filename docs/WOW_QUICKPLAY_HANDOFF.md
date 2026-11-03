# WoW Quickplay, character cards and match chat: handoff (0.6.1, branch `feature/connected`)

**Status: SIMULATED.** Everything below runs between simulated WoW clients in the test suite
(`tests/test_quickplay.lua`). Nothing has been tested in a real WoW client yet. Previews in
`docs/preview` are drawn from the addon's layout code in a WoW API mock. They are not screenshots.

This file is for the stackrivals.io project (web Claude). It describes what the WoW addon does
and the shared data shapes. **The addon does not talk to the website.** Nothing here asks the
web to change anything yet. The web stays authoritative for accounts, progression and results.

## 1. Game mode names (0.6.1, display only)

| Internal id (unchanged) | WoW addon name | Notes |
|---|---|---|
| `classic` | Classic | solo, endless |
| `blitz` | Time Trial | solo, 2:00 (`/sr trial`; `/sr blitz` still works) |
| `daily` | Daily Challenge | solo, same pieces for everyone per UTC day |
| `spellbot` | Spell Battle | Spell Battle vs Bot, 3:00 |
| ruleset `b120` | Duel 2:00 | 1v1 score race |
| ruleset `r180` | Duel 3:00 | 1v1 score race, the web's 3:00 |
| ruleset `s180` | Spell Duel 3:00 | 1v1 with spells and mana |
| Quickplay (`INV` flag `q`) | Quick Duel (button: QUICKPLAY) | a random rival who is searching too |
| Challenge sheet | Guild Duels (card: Guild Duel) | guild, friends, Battle.net, group, recent, by name |

These are StackRivals puzzle duels, not WoW's own `/duel`. Mode ids, ruleset ids, the protocol,
SR1 and the SR2 draft, and saved data are unchanged. If the web wants the same names, it can use
this table. Nothing in the addon depends on it.

## 2. Quickplay flow

Quickplay → Searching → Opponent found → Ready check (the duel lobby) → Countdown → Match →
Result → Rematch.

* **Who can be found.** Only players who are searching right now, for the same mode, and that WoW
  lets the addon reach:
  * guild (one `GUILD` broadcast every 20 s while searching);
  * party / raid (one `PARTY` / `RAID` broadcast);
  * WoW friends, Battle.net friends on a reachable realm, and recent rivals whose StackRivals
    answered a presence ping (whispered `QS`, at most 20).

  Classic gives addons no global channel, so there is **no global queue and no fake queue**.
* **Matching.** When two searchers hear each other (`QS`), the lower `name-realm` sends a duel
  invite with the Quickplay flag (`INV …:q`).
  * The other side accepts automatically only while it is searching for exactly that mode.
    Searching counts as consent.
  * Anything else is dropped without a popup and without an answer: an unsolicited Quickplay
    invite, a different mode, an ignored player, or a player skipped after a failed match.
* **Ready check.** This is the normal duel lobby. Both press Ready, then the normal duel runs with
  all its fairness rules (shared pauses, peer replay check, verdict exchange).
* **Fall-through.** If the rival doesn't press Ready, cancels or disconnects, the other player is
  put back into the search and skips that rival for 2 minutes. A player who didn't press Ready
  themselves (away) is not put back into the search.
* **Rematch.** This is a normal invite that the rival must accept with the popup. It is not
  automatic.
* **Timeout.** After 5 minutes with no opponent: "No opponent found", with the reason.
* **Web adapter.** `Quickplay.adapters.web` exists with the interface
  `{ status, search, cancel }` and always reports `not_connected`. The UI says
  "Web players (stackrivals.io): not connected". A real connection needs an allowed, tested
  transport (see section 7).

## 3. Character cards

Each addon sends its own card once the lobby opens (`PRF`, sent twice in case a whisper is lost).

| Field | Source | Trust |
|---|---|---|
| character name, realm | WoW (the real sender of the addon message) | checked by WoW |
| faction, race, class, level | `UnitFactionGroup`, `UnitRace`, `UnitClass`, `UnitLevel` on the sender's PC | **self-reported** |
| duel W/L | sender's SavedVariables (played-out, replay-checked duels) | **self-reported** |
| match chat on/off | sender's setting | self-reported |
| StackRivals rank / level | — | **Unknown** until an account is linked (Text 2/4) |

* The rival's card says "unverified".
* "Share my card" off sends `-` for every field, and the rival sees Unknown.
* Never sent: Battle.net tag, account names, guild, location, gold, gear, `gameAccountID`.
* A card is display only. It can't change anyone's records or results (there is a test for this).

## 4. Match chat

* The chat panel sits on the right edge of the StackRivals window during a duel: in the lobby, in
  the match and on the result screen.
  * It has text and Send, quick messages (GL / GG / WP / Rematch?), Mute, Chat on/off, and a
    fold-away tab with an unread count.
* **Both must have chat on.** Each card carries the flag. If one side has chat off, nobody can send.
* **Same faction:** free text. **Different factions or an unknown faction:** quick messages only.
  WoW doesn't let the factions talk, so the addon doesn't either.
* **Never posted to a WoW channel.** Lines go by addon whisper to the rival only (`CH` / `QM`).
* **Limits.**
  * Lines are at most 80 bytes.
  * Sending: 1 line per 1.5 s and 8 per 30 s.
  * A rival's lines beyond 10 per 30 s are dropped.
  * Control characters are stripped, and `|` is escaped, so a line can't inject links, colours or
    textures.
* **Mute** is per player, is remembered, and the muted player is not told.
* **Disconnect:** chat turns off with "lost contact with your rival".

## 5. Protocol additions (prefix `StackRivals`, protocol 1, all optional for old clients)

```
1:QS:<qid>:<ruleset>:<addonVersion>                       searching (b120 | r180 | s180)
1:INV:<mid>:<ruleset>:<engine>:<commit>:q                 Quickplay invite (flag q)
1:PRF:<mid>:<A|H|N|->:<race|->:<class|->:<level 0-200>:<w36>:<l36>:<chat 0|1>
1:CH:<mid>:<n>:<hex UTF-8, 2-160 hex chars>
1:QM:<mid>:<n>:<1 GL | 2 GG | 3 WP | 4 Rematch?>
```

* 0.6.0 and older ignore these kinds and are never matched by Quickplay.
* A normal challenge between 0.6.1 and 0.6.0 still works, without cards or chat (tested).

## 6. Shared data contract (proposal, version 1, JSON field names)

These are the shapes the addon uses internally, written so that the web can use the same names.
They are not exchanged with the web yet.

```jsonc
// PlayerProfile: a StackRivals account (the web is the source; the addon only displays it)
{ "v": 1, "profileId": null, "displayName": null, "rank": null, "level": null, "xp": null,
  "wins": 0, "losses": 0, "linked": false }

// CharacterProfile: one WoW character, as one addon reports it to another
{ "v": 1, "name": "Bob", "realm": "Firemaw", "faction": "Horde", "race": "Orc", "class": "SHAMAN",
  "level": 38, "duelWins": 12, "duelLosses": 8, "chat": true,
  "source": "self-reported" }            // "wow-api" for your own character

// MatchmakingStatus
{ "v": 1, "state": "idle|searching|matched|none", "mode": "b120|s180",
  "startedAt": 0, "reach": { "guild": true, "group": false, "friends": 2 },
  "adapters": { "native": "available|unavailable", "web": "not_connected" },
  "note": "no_opponent|fell_through|cancelled|you_not_ready|null" }

// MatchInvitation
{ "v": 1, "matchId": "a1b2c3", "ruleset": "b120|r180|s180", "engineVersion": 1,
  "from": "Alice-Realm", "to": "Bob-Realm", "quickplay": true, "rematch": false,
  "commit": "…" }                       // seed commitment, see docs/CROSS_PLATFORM_MULTIPLAYER.md

// MatchChatMessage (never stored, never forwarded)
{ "v": 1, "matchId": "a1b2c3", "n": 3, "from": "Alice-Realm", "kind": "text|quick",
  "text": "Good luck!", "quickCode": 1 }

// MatchResult: the addon's peer-checked duel result (unchanged from 0.5)
{ "v": 1, "matchId": "a1b2c3", "ruleset": "b120", "outcome": "win|loss|draw|void",
  "basis": "replay|rejected|forfeit|timeout|void", "agreement": "agreed|disputed|unconfirmed",
  "myScore": 0, "theirScore": 0 }       // proof for the web = SR1 / SR2 input logs, not this summary

// RematchRequest = a MatchInvitation with "rematch": true, same ruleset, new matchId
```

Ruleset ids and engine versions are the existing ones (`docs/SR2_DRAFT.md`,
`docs/CROSS_PLATFORM_MULTIPLAYER.md`). The full integration contract (accounts, linking, import
and export) comes in `docs/STACKRIVALS_WEB_INTEGRATION.md` (Texts 2–4).

## 7. What the WoW addon can't do alone

* Reach stackrivals.io. An addon has no HTTP or WebSocket access, so web↔WoW Quickplay needs an
  allowed, tested transport. None exists today. The addon will never claim it works.
* Find strangers. There is no global addon channel in Classic, so it only finds players it can
  reach.
* Verify a rival's faction, race, class or level. These are self-reported.
* Give out rewards. Profiles and cards are display only.

## 8. Needs a real WoW test (not proven by the simulated tests)

| Scenario | Why it is open |
|---|---|
| Two real players in one guild find each other with Quickplay | real delivery and throttling of `GUILD` / whispers |
| Party / raid Quickplay | `PARTY` / `RAID` delivery |
| Friend on another realm (connected realms) | cross-realm addon whispers |
| Different factions on one realm: quick messages arrive | **cross-faction addon whispers are unverified**; if they don't arrive, chat stays off |
| Typing in the chat box during a live match | keyboard focus: the game must not move pieces while you type |
| Faction emblem and class icon textures | Blizzard texture paths (placeholders in previews) |
| Classic Era, Forever and Retail clients | API differences (`UnitRace` tokens, `CLASS_ICON_TCOORDS`) |

## 9. Tests (simulated clients)

`tests/test_quickplay.lua` covers:

* Matching:
  * two searchers matched, with no popup;
  * nobody searching → "no opponent";
  * cancel;
  * different modes never match;
  * Spell Duel Quickplay;
  * three searchers → one pair and one still searching (no double booking);
  * a player who isn't ready, with fall-through and skip;
  * cancel in the lobby.
* Trust and safety:
  * unsolicited Quickplay invites ignored;
  * an ignored player never matched;
  * forged or out-of-range cards rejected;
  * a third party can't write a card or chat line;
  * a card never changes records.
* Compatibility:
  * a friend on another realm;
  * an older client never matched, while a normal duel with it still works;
  * rematch = a normal invite.
* Chat:
  * text and escaping, never on a WoW channel;
  * quick messages;
  * send and receive rate limits;
  * mute;
  * chat off;
  * cross-faction quick-only;
  * disconnect;
  * the chat panel (Enter, fold, unread).
* Names: the mode names and the unchanged ids.
