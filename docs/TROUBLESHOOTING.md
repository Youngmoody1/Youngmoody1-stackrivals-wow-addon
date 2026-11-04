# Install and troubleshooting, per WoW client

One ZIP works for every client. Unzip it so this file exists:
`<client folder>\Interface\AddOns\StackRivals\StackRivals.toc`. Then restart the game fully. A
`/reload` is not enough for new files.

## Where the AddOns folder is

The default install is `C:\Program Files (x86)\World of Warcraft\`. Exact path: Battle.net → pick
the game version → gear icon → **Show in Explorer**.

| Client | Folder | Interface shown in the AddOns list |
|---|---|---|
| WoW Forever | `_forever_\Interface\AddOns\` (create `Interface\AddOns` if the client hasn't yet) | 16001 (live number to be confirmed) |
| Classic Era, Hardcore, Season of Discovery | `_classic_era_\Interface\AddOns\` | 11509 |
| Retail (Midnight) | `_retail_\Interface\AddOns\` | 120105 |
| TBC Classic Anniversary | `_anniversary_\Interface\AddOns\` | 20506 |
| Mists of Pandaria Classic | `_classic_\Interface\AddOns\` | 50504 |
| Titan Reforged (China) | the client's own `Interface\AddOns\` | 38002 |

With the CurseForge app: pick the right game version in the app, then search "StackRivals". It
installs into the right folder by itself.

## Common problems (every client)

| Symptom | Cause / fix |
|---|---|
| Not in the AddOns list | Wrong folder level: it must be `AddOns\StackRivals\StackRivals.toc`, not `AddOns\StackRivals\StackRivals\…`. Restart the game fully |
| "Out of date" | The client has a newer interface number than our TOC. Tick **Load out of date AddOns**, then send us `/sr report`. We add the number in the next build |
| `/sr` does nothing | The addon didn't load: check the AddOns list. `/console scriptErrors 1`, `/reload`, and send the first error lines |
| Keys don't reach WoW | They only belong to StackRivals while a run is live. Press P (pause) or Esc. If a key stays captured, `/reload` and tell us |
| The window is too big or small | `/sr scale 0.8` (any value 0.6–1.4) or Settings |
| A Lua error popup | Copy its first lines, then `/sr report`. Post both |

## Client-specific notes

**WoW Forever and Retail (Mainline clients)**
* During a **boss fight, a Mythic+ run or a PvP match** WoW blocks addon messages for every addon.
  * Duels, Quickplay and Loot Duel wait. Loot Duel can't be started then and says why.
  * Solo modes are not affected.
  * This is WoW's rule; StackRivals doesn't work around it.
* **Trial and Veteran accounts** can't send addon messages, so they get no multiplayer.
* Forever: whether addon messages work **inside dungeons between pulls** is not verified yet
  (`docs/FOREVER.md` F2). `/sr commtest` in the dungeon shows it.

**Classic Era, Hardcore, Season of Discovery, TBC Anniversary, Mists**
* No addon-chat lockdown on these clients.
* Hardcore: StackRivals never acts in combat. It pauses, hides and gives your keys back, so it
  can't get you killed while you play. Still, don't play it next to mobs.

**Titan Reforged**
* Modelled from the older Wrath game type only. Not tested.

## Multiplayer doesn't connect

1. Both players: `/sr version`. Every multiplayer mode needs a recent StackRivals on both sides
   (Loot Duel: 0.7.3+).
2. In a group: `/sr commtest`. It must say "n of n answered".
   * "0 of n" with no lockdown: the others don't run StackRivals, or WoW doesn't deliver addon
     messages here. Send us the `/sr report` line.
3. Different realms: only friends on connected realms, or Battle.net friends in the **same** WoW
   version, can be reached.
4. Different factions: duels work, but free-text match chat only works within one faction (quick
   messages work across).

## Sending a report

`/sr report` → click the box → Ctrl+C → paste into a CurseForge comment, a GitHub issue
(https://github.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/issues) or Discord. The line has
no character, realm or chat data.
