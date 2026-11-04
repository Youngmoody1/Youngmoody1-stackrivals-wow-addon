# Testplan: StackRivals 0.8.1 i WoW Forever og Classic Era

Resultater skrives i testloggen: `TEST_LOG_CLASSIC_ERA.md`, og for Forever i en ny
`TEST_LOG_FOREVER.md`, som oprettes ved første test. Mange punkter kræver flere spillere; de står for
sig, så en solo-test aldrig tæller som bevis for multiplayer.

**Intet installeres uden dit udtrykkelige GO.**

## 0. Installation (kun efter dit GO)

| Klient | Hvad der sker | Hvad der ikke røres |
|---|---|---|
| **Forever** (`_forever_`) | 0.8.1 pakkes ud i `_forever_\Interface\AddOns\StackRivals\`. Mappen findes ikke endnu, så det er en ny installation. Ingen SavedVariables findes der | Classic Era-installationen (0.7.0), dens SavedVariables og alle backups |
| **Classic Era** (`_classic_era_`) | Først senere: opgradering fra 0.7.0 til 0.8.1, med en ny backup af `StackRivals.lua` (SavedVariables) og `AddOns\StackRivals` før installationen | – |

Fremgangsmåde (ligesom ved 0.7.0):
1. Luk WoW helt.
2. Tag backup.
3. Pak ZIP'en ud.
4. Læs filerne tilbage, og sammenlign dem med ZIP'en og SHA-256.
5. Start WoW.

## 1. Solo (1 spiller; begge klienter)

| # | Test | Forventet | Forever | Classic Era |
|---|---|---|---|---|
| S1 | `/dump WOW_PROJECT_ID, select(4, GetBuildInfo())` | Forever `18` + live interface-nummer (skriv det ned). Classic Era `2  11509` | IKKE TESTET | IKKE TESTET |
| S2 | AddOns-listen | StackRivals med flueben, ikke "out of date" | IKKE TESTET | IKKE TESTET |
| S3 | `/sr version` | "… WoW Forever 1.60.1 (…)" / "… Classic Era 1.15.9 (11509)" | IKKE TESTET | IKKE TESTET |
| S4 | Classic 2 min, Time Trial, Daily | Taster, score og rekorder virker; Daily giver samme brikker to gange | IKKE TESTET | IKKE TESTET |
| S5 | **Spell Battle vs Bot**, 1–2 min, inkl. pause + genoptag | **Ingen rød kasse/bjælke** over bottens bræt eller dit bræt. Bomb-målet er en svag markering under brikkerne | IKKE TESTET | IKKE TESTET |
| S6 | Kamp med et mob midt i et spil | Spillet pauser, tasterne går tilbage til WoW, ingen Lua-fejl | IKKE TESTET | IKKE TESTET |
| S7 | `/reload` midt i et spil → Continue | Samme spil, sat på pause | IKKE TESTET | IKKE TESTET |
| S8 | **Account-menuen**: Account / Profile / Sync | Ingen felter til password eller e-mail. Kode `A7K9-P2XJ` → PENDING og en `SRL1`-kode. Profile uden link: "Link account" | IKKE TESTET | IKKE TESTET |
| S9 | **Loot Duel** alene | Lobbyen åbner med "Join a party or raid first". Loot Duel-knappen findes | IKKE TESTET | IKKE TESTET |
| S10 | **Quickplay** alene: Search → Cancel | SEARCHING med ur, derefter "Search cancelled". Ingen falsk modstander | IKKE TESTET | IKKE TESTET |
| S11 | `/sr report` → kopiér linjen ind i testloggen | `client=forever;project=18;…` / `client=vanilla;project=2;…` | IKKE TESTET | IKKE TESTET |
| S12 | Kun Classic Era: data fra 0.7.0 efter opgradering | Rekorder, Spell Battle-statistik, taster og ventende konto-link er bevaret | – | IKKE TESTET |

## 2. Multiplayer (kræver 2+ spillere med StackRivals 0.8.1)

Tæller kun, hvis **en anden klient svarer**. Et vellykket API-kald alene beviser ikke levering.

| # | Test | Spillere | Forventet | Forever | Classic Era |
|---|---|---|---|---|---|
| M1 | `/sr commtest` i en gruppe i den åbne verden | 2–5 | "n of n … answered" | IKKE TESTET | IKKE TESTET |
| M2 | **`/sr commtest` inde i en dungeon uden kamp** (Forever F2) | 2–5 | "n of n answered". Svarer ingen, og der ikke er lockdown, er Loot Duel ikke mulig inde i Forever-dungeons | IKKE TESTET | (ingen lockdown i Classic; test alligevel én gang) |
| M3 | `/sr commtest` under en bosskamp | 2–5 | Forever: result 11 eller ingen svar, med "lockdown" i linjen. Classic Era: svar kommer | IKKE TESTET | IKKE TESTET |
| M4 | Loot Duel i en party på 5: Invite Party → 3 Join, 1 Pass → Start → løb | 5 | Samme vinder på alle PC'er. WINNER grøn, LOST/PASSED rød. CONGRATULATIONS hos alle. Announce kun ved klik | IKKE TESTET | IKKE TESTET |
| M5 | Quick Duel mellem to i samme guild | 2 | Match fundet, ready, duel, resultat og revanche | IKKE TESTET | IKKE TESTET |
| M6 | Guild Duels → udfordring ved navn | 2 | Popup hos modspilleren. Duel og resultat | IKKE TESTET | IKKE TESTET |
| M7 | Match-chat under en duel | 2 | Beskeder vises, og brikkerne flytter sig ikke, mens man skriver | IKKE TESTET | IKKE TESTET |
| M8 | Battle.net-venner på forskellige realms | 2 | Duel via Battle.net (eller tydelig grund, hvis det ikke kan) | IKKE TESTET | IKKE TESTET |
| M9 | Raid (Forever fra 9. dec.): Loot Duel med 10–20 | 10–20 | Starttid, resultattid, FPS og samme vinder | IKKE TESTET | – |

## 3. Efter hver session

1. `/sr report` fra hver deltager. Linjerne indeholder ingen navne eller chat.
2. Første linjer af eventuelle Lua-fejl.
3. Screenshots af resultatskærme. De kan senere bruges på CurseForge. Beskær andres navne og chat.
4. Skriv OK / FEJL / DELVIS ved hvert punkt. Fejl får et nummer i testloggen og rettes med en
   regressionstest.
