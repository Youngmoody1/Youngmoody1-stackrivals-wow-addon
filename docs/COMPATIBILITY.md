# Client compatibility

Status levels — used strictly:

- **UNTESTED** – nothing run for this client.
- **SIMULATED** – automated tests pass against a mock of that client's API. Proves logic, not the client.
- **CLIENT TESTED** – the 10-minute pass (TESTING_IN_WOW.md) was done in the real client and passed.
- **RELEASE READY** – client tested, issues fixed, interface number confirmed, owner approved.

| Client | Game type / TOC suffix | Interface in TOC | Status | Notes |
|---|---|---|---|---|
| WoW Forever | forever / `_Forever` (family `_Mainline`) | 16001 (beta number; live number unknown until launch) | SIMULATED | Beta closed 23 Oct. Real test on launch night (5 Nov 00:00 CET). |
| Retail (Midnight) | standard / `_Standard`, `_Mainline` | 120105 | SIMULATED — **installed on the owner's PC 29 Oct, awaiting test** | Secret-value guard for `UnitAffectingCombat`; chat-lockdown guard. |
| Classic Era (incl. Hardcore realms) | vanilla / `_Vanilla`, `_Classic` | 11509 | SIMULATED — **installed on the owner's PC 29 Oct, awaiting test** | Falls back to global `SendChatMessage` / `GetAddOnMetadata` (tested). No addon compartment (TOC line ignored). |
| Anniversary | tbc / `_TBC` (Warcraft Wiki: Anniversary runs on the TBC game type) | 20506 | UNTESTED | Client is installed on the owner's PC but has no AddOns yet. |
| TBC / Wrath / Titan Reforged / Cata / Mists Classic | `_TBC` / `_Wrath` / `_Cata` / `_Mists` | 20506, 38002, 30405, 40402, 50504 | UNTESTED | Listed so the addon isn't marked "out of date"; test before claiming support. |

Interface numbers: Warcraft Wiki TOC page (edited 17 Oct 2026). Forever's release value is blank there.

## One TOC for all clients

`StackRivals.toc` has no suffix, so every client loads it, and `## Interface:` lists all numbers
(comma lists are supported since 10.2.7 / the current Classic clients). If one client ever needs
different files, add e.g. `StackRivals_Forever.toc` next to it — a game-type file wins over the plain
one on that client only, so the others are unaffected.

## API surface the addon depends on

All UI comes from a small set of long-standing calls; everything newer is feature-detected:

| Need | Call | Fallback / guard |
|---|---|---|
| Version text | `C_AddOns.GetAddOnMetadata` | global `GetAddOnMetadata`, then `"dev"` |
| Share to chat | `C_ChatInfo.SendChatMessage` | global `SendChatMessage`; skipped during `C_ChatInfo.InChatMessagingLockdown()` |
| Combat check | `InCombatLockdown()` | `UnitAffectingCombat("player")`, ignored if `issecretvalue` says it's secret |
| Events | `RegisterEvent` | wrapped in `pcall` (unknown events don't error) |
| Sounds | `PlaySoundFile(path, "SFX")` | `pcall`, then without channel; never errors |
| Window position | `SetDontSavePosition` | only if present |
| Addon menu entry | `## AddonCompartmentFunc` | ignored by clients without the compartment |

Engine, session and saved-data code use no WoW API at all, so a client difference can only affect the
UI layer — and a Lua error in this addon cannot affect other clients (each client has its own copy of
the files and its own SavedVariables).

## Forever specifics we know (beta reports, Sep–Oct 2026)

Forever uses the modern Mainline API; reported differences that matter elsewhere (combat-log access,
spell/item info moved to `C_Spell`/`C_Item`, secret unit values) don't touch anything StackRivals calls.
`WOW_PROJECT_ID` is reported as 18 on recent beta builds; the addon doesn't branch on it.
