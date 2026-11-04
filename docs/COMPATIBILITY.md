# Compatibility: every official WoW client (0.8.1, branch `feature/multi-client`)

One addon, one code base, one game engine for every official client. Client differences live only in
`Core/Client.lua` (which client, what it can do) and the transport (`Net/Comm.lua`). Private servers
are not supported.

**Nothing in this file is a real-client result unless the "Tested in real client" column says so.**
TOC compatibility (the addon loads without "out of date") never counts as feature verification.

Facts were checked on 4 Nov 2026. Most come from warcraft.wiki.gg: the `WOW_PROJECT_ID`, TOC format,
Public client builds, `SendAddonMessage`, `InChatMessagingLockdown` and `IsAddOnRestrictionActive`
pages, and the Patch 1.60.1 / 12.0.0 / 12.0.5 API notes, which quote Blizzard's own posts. Each
client's data is in `tools/clients.json`.

## 1. The clients

| Client | `WOW_PROJECT_ID` | Interface (TOC) | TOC suffix the client prefers | API family | CurseForge flavor | Priority |
|---|---|---|---|---|---|---|
| **WoW Forever** 1.60.1 (launches 4 Nov 2026, 23:00 UTC) | 18 `WOW_PROJECT_CAMELOT` | 16001: the beta / test number; the live number is still blank on the wiki | `_Forever` / `_Camelot`, then `_Mainline` | **Mainline** (Retail's), not Classic Era's | Forever | highest |
| **Classic Era** 1.15.9, incl. **Hardcore** and **Season of Discovery** realms | 2 `WOW_PROJECT_CLASSIC` | 11509 | `_Vanilla` | Classic (1.15.9's API "very closely matches" 2.5.6) | Classic | highest |
| **Retail / Midnight** 12.1.5 | 1 `WOW_PROJECT_MAINLINE` | 120105 | `_Standard`, then `_Mainline` | Mainline | Retail | high |
| **TBC Classic Anniversary** 2.5.6 (all Anniversary realms since Jan 2026) | 5 | 20506 | `_TBC` | Classic | Classic TBC | high |
| **Mists of Pandaria Classic** 5.5.4 | 19 | 50504 | `_Mists`, then `_Classic` | Classic | MoP Classic | high |
| **Titan Reforged – Chrono** 3.80.2 (China only) | 11 (Wrath game type) | 38002 | `_Wrath` | Classic (older; the 12.x-era APIs are not documented there) | Titan Reforged Classic | high (no access from EU) |
| Cataclysm Classic | 14 | 40402 | – | – | **gone**: it became the Mists pre-patch on 1 Jul 2025. Removed from the TOC |
| Wrath Classic | 11 | 30405 | – | – | **no live realm found**. Removed from the TOC |
| PTR / Beta (kept apart; never in a release TOC) | – | Retail PTR 120107; Forever Beta/Test 16001; Classic Era Test 11508 | – | – | test only |

**Forever is not Classic Era.** Blizzard, 15 Sep 2026: "WoW Forever shares Mainline WoW's UI
architecture, including the vast majority of APIs available in 12.1.5." It also says "the addon
disarmament changes introduced in Midnight, including secrets, will also be active in Forever." So
Forever gets Retail's restrictions, not Classic's freedoms. `Core/Client.lua` treats it as a
Mainline-family client of its own type. Details are in `docs/FOREVER.md`.

## 2. One ZIP or one per client?

**One universal ZIP is enough, and it is safer.**

* The single `StackRivals.toc` lists every live interface:
  `16001, 11509, 120105, 20506, 50504, 38002`.
  * Comma lists are supported since 10.2.7 and in all current Classic clients.
  * Deadly Boss Mods ships its core the same way: `11509, 16001, 20506, 30405, 38002, 40402, 50504,
    120105, 120107`.
* Every client loads the same files. Client-specific TOC files (`StackRivals_Forever.toc` etc.)
  only help when a client needs *different files*. None does: every difference is a runtime
  feature check.
  * Seven copies of the file list would have to be kept in sync.
  * A forgotten suffix would load nothing on that client.
* Per-client ZIPs would be byte-identical. The build (`tools/build_release.sh`) makes the one ZIP
  plus a manifest (`dist/StackRivals-<version>.json`) that lists the clients from
  `tools/clients.json` with their interface numbers.
* `tools/validate_addon.py` refuses a TOC whose interface list differs from the live clients in
  `tools/clients.json`. That way no dead or guessed number ships.
* **Watch item:** if Forever's live interface turns out not to be 16001, the addon shows "out of
  date" in Forever until the TOC gets the new number. Check: `/dump select(4, GetBuildInfo())` in
  Forever after launch. Players can tick "Load out of date AddOns" meanwhile.

## 3. What differs per client, and how the addon handles it

| Area | Classic Era / Hardcore / SoD, TBC, Mists | Titan Reforged | Forever and Retail (Mainline) | Handled by |
|---|---|---|---|---|
| Client detection | project 2 / 5 / 19 | project 11 | project 18 / 1 | `Client.detect()`. `WOW_PROJECT_ID` decides; the interface range only when it is missing. An unknown client is named "unknown", not guessed |
| Hardcore / SoD realm rules | `C_GameRules.IsHardcoreActive`, `C_Seasons` | – | – | detected; shown in `/sr version` and the diagnostics |
| Addon messages (PARTY / RAID / GUILD / WHISPER) | yes; restrictions off in Classic (Blizzard, Apr 2026) | yes | yes, **except during WoW's addon chat lockdown**: boss encounter, Mythic+ run, PvP match (Blizzard, 11 Oct 2025) | `Comm` holds every message while `InChatMessagingLockdown()` says so, or after result 11 (`AddOnMessageLockdown`). Nothing is lost, nothing is retried early, and nothing works around it |
| Whole-zone lockdown | – | – | **unclear**: the wiki's Secret Values page also lists "a communication-restricted map such as a dungeon or raid" | if the client reports `Map`, Loot Duel says "this zone" and doesn't run there. Needs the real client (`docs/FOREVER.md`) |
| Message limit | 10 per prefix, +1/s (server may change it) | same | same; whispers count inside instances | our buckets: group 8 then 0.9/s, whispers 8 then 2/s (0.8/s in instances), and one shared bucket of 9, +0.9/s, for everything WoW counts |
| Trial / Veteran accounts | – | – | can't send addon messages | Loot Duel and duels say so |
| Secret values | – | – | combat state and some unit data can be secret | never compared; `issecretvalue` guards (combat pause) |
| Loot method (read only) | `C_PartyInfo.GetLootMethod` (1.15.8 / 2.5.5 / 5.5.1; the old global was removed there) | old `GetLootMethod` | `C_PartyInfo.GetLootMethod`; Forever's methods are **unknown** | `Client.lootMethod()`, either API. **Never changed** |
| Item info | `C_Item.GetItemInfo` (and the global) | global | `C_Item.GetItemInfo` only (the global's fallback was removed in 12.1.5) | `C_Item` first, then the global |
| Battle.net game data | `C_BattleNet.SendGameData` (`BNSendGameData` marked removed) | `BNSendGameData` likely | `C_BattleNet.SendGameData` | `Net/BNet.lua` uses whichever exists, only between friends in the **same** WoW version. Cross-client delivery is unverified |
| Chat from addons | `SendChatMessage` | same | `C_ChatInfo.SendChatMessage`; blocked during the lockdown | Share and Announce only on a click, and refused during the lockdown |
| Removed globals the addon never relies on | – | – | `GetSpellInfo`, `UnitAura`, `GetItemInfo` | the mock profiles remove them; the addon still loads and plays |
| Addon compartment | ignored | ignored | used | TOC `## AddonCompartmentFunc` |

## 4. Feature matrix

* **Implemented:** the code exists for that client, and missing APIs have fallbacks.
* **Automated tests passed:** the mock profile in `tests/clients.lua` passes in GitHub CI on
  Lua 5.1, plus the multiplayer simulations. This proves the logic, not the client.
* **Tested in real client:** seen working in that client by you. Only one entry so far.
* **Limited:** works with a documented limitation.
* **Unsupported:** can't work there. The addon says so instead of pretending.

| Feature | Forever | Classic Era / Hardcore / SoD | Retail | TBC Anniversary | Mists Classic | Titan Reforged |
|---|---|---|---|---|---|---|
| Classic, Time Trial, Daily | Implemented · Automated | Implemented · Automated · **Tested in real client: 0.3.1 smoke test only** (Classic, Daily, Time Trial; your 4 Nov report). Not yet 0.7.x / 0.8.0 | Implemented · Automated | Implemented · Automated | Implemented · Automated | Implemented · Automated |
| Spell Battle vs Bot | Implemented · Automated | Implemented · Automated. Red-box fixes **await your check** | Implemented · Automated | Implemented · Automated | Implemented · Automated | Implemented · Automated |
| Quickplay / Quick Duel | Implemented · Automated · **Limited**: not during a lockdown; trial accounts can't | Implemented · Automated | Implemented · Automated · **Limited** (as Forever) | Implemented · Automated | Implemented · Automated | Implemented · Automated |
| Guild Duels (guild, friends, group, by name) | Implemented · Automated · Limited (lockdown, trial) | Implemented · Automated | Implemented · Automated · Limited | Implemented · Automated | Implemented · Automated | Implemented · Automated |
| Battle.net friends (other realms) | Implemented · Automated · Limited: same WoW version only; delivery unverified | same | same | same | same | Implemented (old API) · Automated · Limited |
| Match Chat | Implemented · Automated · Limited: free text within one faction; not during a lockdown | Implemented · Automated · Limited (one faction) | Implemented · Automated · Limited | Implemented · Automated · Limited | Implemented · Automated · Limited | Implemented · Automated · Limited |
| Account link and Profile (copy and paste codes) | Implemented · Automated | Implemented · Automated | Implemented · Automated | Implemented · Automated | Implemented · Automated | Implemented · Automated |
| Sync: challenge codes in, result codes out | Implemented · Automated | Implemented · Automated | Implemented · Automated | Implemented · Automated | Implemented · Automated | Implemented · Automated |
| Loot Duel 2–40 | Implemented · Automated (dungeon of 5, raid with a boss pulled mid-race) · **Limited**: no start during a lockdown; whole-zone lockdown unknown; loot methods unknown | Implemented · Automated (2–40) | Implemented · Automated · **Limited**: personal / group loot only, trade rules apply; lockdown | Implemented · Automated | Implemented · Automated | Implemented · Automated · no lockdown API (none documented) |
| Live web connection (stackrivals.io) | **Unsupported** everywhere: addons have no internet access. The Quickplay web adapter honestly says "not connected" | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported |

**Concrete blockers and unknowns, needing the real clients:**

1. **Forever's live interface number.** It is blank on the wiki. Check after launch.
2. **Forever: are PARTY / RAID addon messages blocked in the whole dungeon, or only during
   encounters?** The documentation conflicts. This decides whether a 5-player Loot Duel can run
   inside a Forever dungeon at all. Test plan: `docs/FOREVER.md` F1–F8.
3. **Forever's loot methods.** Master loot or not; Blizzard hasn't documented them.
4. **Battle.net delivery** between friends on different realms, and between client types.
5. Titan Reforged is China-only, so we have no access. It is modelled from the Wrath game type only.

## 5. Tests

* `tests/test_clients.lua` covers 9 profiles: Forever, Classic Era, Hardcore, Season of Discovery,
  Retail, TBC Anniversary, Mists, Titan, and an unknown future client. Each profile:
  * loads the whole addon;
  * detects the client;
  * plays Classic, Time Trial, Daily and Spell Battle vs Bot to a recorded game;
  * reloads saved data;
  * opens every screen;
  * reads the loot method;
  * checks lockdown and trial handling.
* Loot Duel runs between simulated clients on Forever, Classic Era, Retail, TBC and Mists:
  * a party of 5 on every one;
  * a 10-player raid with a boss pulled mid-race on Forever and Retail;
  * a Start during a lockdown.
* The profiles model what each client has **and lacks** (removed globals, missing namespaces),
  from the documentation. They are not the clients.
* `/sr report` / `/sr commtest` are tested on every profile: report contents and privacy; delivery
  proven by answers on Forever and Classic Era; a commtest during a lockdown.
* Real-client test guides:
  * `docs/FOREVER.md`: Forever, incl. multiplayer;
  * `docs/INSTALL_AND_TEST.md`: install, the 10-minute check and what to report, for every client;
  * `docs/TESTERS.md`: external testers for the clients you don't run;
  * `docs/TROUBLESHOOTING.md`: per client.

## 6. Covering clients we don't run ourselves

You don't need every client installed. Each client is covered by:
* this documentation and the mock profile (automated, every push);
* an external tester's 15-minute script (`docs/TESTERS.md`);
* players' `/sr report` lines.

A report line names the client, its interface, its APIs, the lockdown state and the comm test
result, so most problems can be fixed from the report alone (`tools/diag_report.py`). A client
only moves to "client-tested" with a real report from that client.

## 7. CurseForge

One project and one universal ZIP. Each upload is tagged only with the flavors that passed their
GO list. CurseForge doesn't read flavors from our TOC: the tags are set on upload, so suffixed
TOCs wouldn't help. Details: `docs/CURSEFORGE.md` and `docs/RELEASE_PLAN.md`.
