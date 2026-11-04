# Testplan: StackRivals 0.9.1 (signerede profiler) i rigtig WoW

0.9.1 tilføjer den rigtige signeringsnøgle, så en profil fra stackrivals.io kan vises som **VERIFIED**. Alt andet
er det samme som i 0.9.0. Kun rigtige klienttests tæller. Resultater skrives i testloggen for den klient, der
testes, fx `TEST_LOG_CLASSIC_ERA.md` eller `TEST_LOG_FOREVER.md`.

**Intet installeres uden dit GO.** Hjemmesiden ændres kun af web-chatten.

## 0. Før testen

| # | Trin | Hvem |
|---|---|---|
| P1 | Produktionsnøglen oprettes i hjemmesidens server-hemmeligheder. Den private del vises aldrig | web-chatten, med dit særskilte GO |
| P2 | Kun kid + 64 hex-tegn (den offentlige del) kommer til addon-chatten → `tools/add_public_key.py` → CI grøn | addon-chatten |
| P3 | Test-ZIP for 0.9.1 bygges med SHA-256 og manifest | addon-chatten |
| P4 | Web-chatten bekræfter, at stackrivals.io/wow eksporterer en **signeret** kode: `sig` er ikke `-` | web-chatten |

## A. Installation (kun efter dit GO)

1. Luk WoW helt.
2. Tag backup af:
   * `Interface\AddOns\StackRivals`;
   * `WTF\Account\<konto>\SavedVariables\StackRivals.lua`.
3. Pak 0.9.1 ud over 0.9.0.
4. Læs filerne tilbage, og sammenlign dem med ZIP'en og SHA-256.
5. Start WoW. AddOns-listen skal vise StackRivals uden "out of date". `/sr version` skal sige 0.9.1.
6. Den gamle profil fra 0.9.0 skal stadig være der, som **LINKED - UNVERIFIED**. Den var ikke signeret.

## B. Signeret profil med den rigtige hjemmeside (det vigtigste)

| # | Trin | Forventet |
|---|---|---|
| B1 | Log ind på stackrivals.io/wow | – |
| B2 | Karakteren er linket (eller link den: Link WoW character → kode → Select + Ctrl+C → indsæt) | Linket |
| B3 | Sync status → Export snapshot (SRP2) → kopiér | Koden ender med `.k1…` + 86 tegn + check, ikke `.-.` |
| B4 | WoW: Account → indsæt → Import | Kort "Checking the website's signature...", Import er grå imens. Spillet fryser ikke |
| B5 | Resultat | **VERIFIED** (grøn) og "Signed by stackrivals.io: proves its origin, not character ownership." Profile-tagget siger VERIFIED |
| B6 | Lav en kopi af koden, og ret ét tegn i Shards-feltet (19. punktum-felt) eller i XP | Ved Import: **REJECTED: … changed after stackrivals.io signed it**. Den VERIFIED-profil, du havde, er uændret |
| B7 | Eksportér en ny profil på hjemmesiden (fx efter et spil på web), og importér den | Profilen bliver opdateret, stadig VERIFIED. Den gamle kode igen: "older" eller "already imported" |
| B8 | Collection-fanen | Shards "as of …", events og cosmetics. Nederst VERIFIED. Intet købes, claimes eller anvendes |
| B9 | `/reload` | Stadig VERIFIED |

## C. Ydelse og visning

| # | Test | Forventet |
|---|---|---|
| C1 | B4 med lav FPS (fx i en by med fyldt skærm) | Tager længere tid, men fryser ikke. Skriv tiden ned |
| C2 | Importér den samme kode 3 gange hurtigt efter hinanden | Første gang: kontrol. Derefter straks "already imported" |
| C3 | Account / Profile / Collection ved UI-skala 0,64 og 1,0 og StackRivals-størrelse 70 % og 140 % | Intet overlapper |
| C4 | Lua-fejl (`/console scriptErrors 1`) | Ingen |
| C5 | Loot Duel uden webkonto (en anden karakter, der ikke er linket) | Virker som før |

## D. Bagefter

* `/sr report` fra hver klient i testloggen.
* Screenshots af VERIFIED og REJECTED. Beskær navne.
* Fejl får et nummer i testloggen og rettes med en regressionstest.
