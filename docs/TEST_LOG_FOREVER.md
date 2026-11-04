# Testlog: rigtig WoW Forever (1.60.1, `_forever_`)

Her står kun rigtige klienttests og det, der er set på den rigtige installation. Automatiske
tests står i CI. Testpunkterne kommer fra `TEST_PLAN_FOREVER_CLASSIC.md` (S1–S11 og M1–M9) og
`FOREVER.md` (F1–F9).

**Testversion (fastfrosset):**

| Felt | Værdi |
|---|---|
| Version | StackRivals 0.8.1 Alpha |
| Branch | `alpha/0.8.1` (`2d1bd44`) |
| Addon-kode | `ae4c7f5` |
| ZIP | `StackRivals-0.8.1-alpha.zip`, 82 filer |
| SHA-256 | `27fbb470f81c2a16ea106ba3a2a2aff43c86b777254596f0c4c611a611d7ea95` |

**Status:** IKKE INSTALLERET. Den installeres først, når du skriver GO.

Classic Era (0.7.0), dens SavedVariables og alle backups røres ikke.

Resultatord: **OK**, **FEJL** (med fejlnummer nedenfor), **DELVIS**, **IKKE TESTET**.

## 0. Installation (kun efter dit GO)

| # | Trin | Resultat | Noter |
|---|---|---|---|
| I1 | WoW er helt lukket (Forever og Classic Era) | IKKE TESTET | |
| I2 | `_forever_\Interface\AddOns\StackRivals\` findes ikke i forvejen | IKKE TESTET | Findes den, stopper vi og tager backup først |
| I3 | ZIP'ens SHA-256 er den samme som ovenfor | IKKE TESTET | |
| I4 | Pakket ud til `_forever_\Interface\AddOns\StackRivals\` | IKKE TESTET | |
| I5 | Alle filer er læst tilbage og byte-identiske med ZIP'en | IKKE TESTET | |
| I6 | `_classic_era_` er uændret: AddOns-mappen, `WTF` og backups | IKKE TESTET | Sammenlign mappelisten før og efter |

## Kørsler

| Dato | Build | Hvem | Hvad | Resultat |
|---|---|---|---|---|
| | 0.8.1 (`2d1bd44`) | Claude | Installation (kun filer) | IKKE TESTET |
| | 0.8.1 | dig | Solo S1–S11 | IKKE TESTET |
| | 0.8.1 | dig + 1–4 | Multiplayer M1–M4 | IKKE TESTET |

Notér for hver kørsel:
* dato og klokkeslæt;
* karakterens level og klasse;
* realm-type: normal, Hardcore eller Fresh;
* andre addons, der var slået til.

## 1. Solo (1 spiller)

| # | Tjek | Forventet | Resultat | Noter |
|---|---|---|---|---|
| S1 | `/dump WOW_PROJECT_ID, select(4, GetBuildInfo())` | `18` og et interface-nummer | IKKE TESTET | **Skriv det rigtige interface-nummer:** |
| S2 | AddOns-listen på karaktervalget | StackRivals med flueben, ikke "out of date" | IKKE TESTET | Står der "out of date", så skriv tallet fra S1 ned |
| S3 | `/sr version` | `… WoW Forever 1.60.1 (…)` | IKKE TESTET | Den præcise tekst: |
| S4 | Classic 2 min, Time Trial og Daily | Taster, score og rekorder virker. Daily giver de samme brikker to gange | IKKE TESTET | |
| S5 | **Spell Battle vs Bot**, 1–2 min, med pause og genoptag | **Ingen rød kasse eller bjælke** over bottens eller dit bræt. Bomb-målet er en svag markering under brikkerne | IKKE TESTET | Tag et screenshot |
| S6 | Kamp mod et mob midt i et spil | Spillet pauser, tasterne går tilbage til WoW, ingen Lua-fejl | IKKE TESTET | |
| S7 | `/reload` midt i et spil, derefter Continue | Det samme spil, sat på pause | IKKE TESTET | |
| S8a | **Account** | Ingen felter til password eller e-mail. Koden `A7K9-P2XJ` giver PENDING og en `SRL1`-kode | IKKE TESTET | Cancel bagefter |
| S8b | **Profile** uden link | "No profile yet … Link your stackrivals.io account" | IKKE TESTET | |
| S8c | **Sync** | Fanen åbner, og resultatkoder kan markeres og kopieres | IKKE TESTET | |
| S9 | **Loot Duel-menuen** alene | Kortet og quick-knappen findes. Lobbyen siger "Join a party or raid first" | IKKE TESTET | |
| S10 | **Quickplay** alene: Search og derefter Cancel | SEARCHING med ur, derefter "Search cancelled". Ingen falsk modstander | IKKE TESTET | |
| S11 | `/sr report` | Linjen starter med `SRDIAG1;` og indeholder `client=forever;project=18;` | IKKE TESTET | Kopiér hele linjen herind: |
| S12 | Lua-fejl i hele sessionen | Ingen | IKKE TESTET | Kopiér de første linjer af en eventuel fejl. `/console scriptErrors 1` viser dem |

## 2. Multiplayer (kræver rigtige spillere med 0.8.1)

Et punkt tæller kun, når **en anden klient svarer**. Planen står i `TEST_PLAN_FOREVER_CLASSIC.md` §2.

| # | Tjek | Spillere | Resultat | Noter |
|---|---|---|---|---|
| M1 | `/sr commtest` i den åbne verden | 2–5 | IKKE TESTET | |
| M2 | `/sr commtest` inde i en dungeon, uden kamp (F2) | 2–5 | IKKE TESTET | **Det vigtigste Forever-spørgsmål** |
| M3 | `/sr commtest` under en bosskamp | 2–5 | IKKE TESTET | |
| M4 | Loot Duel med 5: Invite Party, 3 Join, 1 Pass, Start, løb | 5 | IKKE TESTET | Samme vinder på alle PC'er? |
| M5–M8 | Quick Duel, Guild Duels, match-chat, Battle.net | 2 | IKKE TESTET | |
| M9 | Raid, 10–20 spillere | 10–20 | IKKE TESTET | Først fra 9. december |

## Problemer

| # | Fundet | Beskrivelse | Status |
|---|---|---|---|
| | | | |
