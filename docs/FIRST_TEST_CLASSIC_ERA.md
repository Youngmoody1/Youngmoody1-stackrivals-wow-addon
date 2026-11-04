# Første test i WoW Classic Era (0.7.0 dev) – kort plan

Gælder build `StackRivals-0.7.0-lootduel-dev.zip` (branch `feature/loot-duel`). Den fulde guide
er `docs/INSTALL_AND_TEST.md`. Alt herunder er **IKKE TESTET**, indtil du selv har prøvet det i
klienten. De automatiske tests og previews er simulerede og tæller ikke som klienttests.

## Før du starter (5 min)

1. Luk WoW helt.
2. Tag backup:
   * `_classic_era_\Interface\AddOns\StackRivals`;
   * `_classic_era_\WTF\Account\<KONTO>\SavedVariables\StackRivals.lua` (+ `.lua.bak`).
3. Slet den gamle `StackRivals`-mappe og pak ZIP'en ud. Der skal være præcis én mappe:
   `Interface\AddOns\StackRivals\StackRivals.toc`.
4. Start WoW. Står der "Out of date", så slå **Load out of date AddOns** til.

## Solo (1 spiller, ca. 20 min)

| # | Gør dette | Forventet | Resultat |
|---|---|---|---|
| S1 | `/sr version` | 0.7.0, engine v1, interface 11509 (eller hvad klienten siger) | IKKE TESTET |
| S2 | `/sr` → Classic, spil 1 minut | Brikker, taster, score og pause i kamp virker | IKKE TESTET |
| S3 | Time Trial og Daily Challenge | 2:00-ur, Daily-seed er den samme efter `/reload` | IKKE TESTET |
| S4 | Spell Battle vs Bot, niveau 1 | Spells på Q/E/R/F og 1–4, Victory/Defeat | IKKE TESTET |
| S5 | Quickplay-skærmen | Dit kort: din klasse i klassefarve, Alliance blå / Horde rød; "Web players: not connected" | IKKE TESTET |
| S6 | Account → indtast en web-kode | PENDING, ingen password-felter | IKKE TESTET |
| S7 | Sync → indsæt en SR1-kode fra stackrivals.io | Den spiller præcis den udfordring | IKKE TESTET |
| S8 | Loot Duel uden gruppe | "Join a party or raid first." | IKKE TESTET |
| S9 | Log ud og ind | Rekorder, indstillinger og kontostatus er der stadig | IKKE TESTET |
| S10 | Hele vejen igennem | Ingen "Interface action failed", ingen chatbeskeder du ikke selv klikkede på | IKKE TESTET |

## Med to spillere (samme realm, samme guild eller gruppe, ca. 30 min)

| # | Gør dette | Forventet | Resultat |
|---|---|---|---|
| T1 | Guild Duels → Refresh | Den anden står som "ready" | IKKE TESTET |
| T2 | Duel 2:00: invitér, Ready, spil | Samme brikker, samme resultat på begge PC'er | IKKE TESTET |
| T3 | Quick Duel: begge trykker Search | Match found → kort med klassefarve, faction, "unverified" på modstanderen | IKKE TESTET |
| T4 | Match-chat under kampen | Beskeder kommer frem; brikkerne flytter sig ikke, mens du skriver | IKKE TESTET |
| T5 | Spell Duel 3:00 | Spells lander hos modstanderen; første top-out taber | IKKE TESTET |
| T6 | Loot Duel: leder vælger et item og begge spillere | Popup med item og "Winning doesn't hand you the item"; Start er låst til 2 har klikket Join | IKKE TESTET |
| T7 | Loot Duel: spil til slut | Samme vinder på begge PC'er; intet loot flyttes; Announce poster kun ved klik | IKKE TESTET |

Send screenshots af alle fejl og `StackRivals.lua` fra SavedVariables tilbage (se
`INSTALL_AND_TEST.md` afsnit 5).

## Det kræver stadig to (eller flere) rigtige spillere

Disse ting kan ikke afgøres med automatiske tests; de skal ses mellem rigtige klienter:

1. **Levering af addon-beskeder** (WHISPER / GUILD / PARTY / RAID) og WoW's throttling under en
   kamp: kommer duel-logs frem til tiden?
2. **Duel 2:00 / 3:00 og Spell Duel**: samme brikker, samme resultat og samme replay på begge PC'er.
3. **Quick Duel**: om søgningen finder hinanden via guild, gruppe og venner, og hvor lang tid det tager.
4. **Battle.net-transport** mellem venner på forskellige, ikke-forbundne realms: om
   `C_BattleNet.SendGameData` overhovedet leverer i Classic Era 1.15.9 og WoW Forever 1.60.x.
5. **Tværs af factions** (Alliance + Horde): quick messages og Battle.net-chat.
6. **Match-chat**: tastaturfokus, mute og at intet havner i WoW's egne kanaler.
7. **Karakterkort**: modstanderens klasse, race, level og faction kommer frem og vises rigtigt.
8. **Loot Duel** med 3–5 spillere og derefter en raid på 20–40: tid fra invite til resultat,
   kanalbelastning, disconnect / `/reload` midt i, en spiller uden addon, master looter som ikke
   er leder, paging i listen (L1–L12 i `LOOT_DUEL.md`).
9. **Rematch, pause-budget og frakobling** midt i en kamp.
10. **Forskellige addon-versioner** mod hinanden (0.6.x mod 0.7.0): ældre klienter skal stadig kunne
    duellere og ignorere Loot Duel-beskeder.
