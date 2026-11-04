# Testlog: rigtig WoW Classic Era (1.15.9, interface 11509)

Kun rigtige klienttests og det, der er observeret på den rigtige installation, står her.
Automatiske tests står i CI og `docs/STATUS.md`. Fremgangsmåden står i
`docs/FIRST_TEST_CLASSIC_ERA.md` (B1–B20).

**Installeret build:** 0.7.0 dev, commit `9a68952`, ZIP SHA-256
`1c9a8850cc6e2100456d0745f69436d165b76c30c167d241d66435e7d9280b1d`. Den bliver ikke opdateret,
før du har rapporteret og godkendt en ny test-ZIP. Rettelser på branchen efter `9a68952` (se
"Problemer") er **ikke** i den installerede build.

Resultatord: **OK**, **FEJL** (med fejlnummer nedenfor), **DELVIS**, **IKKE TESTET**.

## Kørsler

| Dato | Build | Hvem | Hvad | Resultat |
|---|---|---|---|---|
| 2026-11-04 | 0.3.1 (`5d57439`) | dig | Smoke-test: indlæsning, `/sr version`, Classic, Blitz, Daily | **OK**. SavedVariables bekræfter Classic 426, Daily 250, Blitz 288 |
| 2026-11-04 | 0.7.0 dev (`9a68952`) | Claude | Installation (kun filer) | 69 filer læst tilbage, byte-identiske med ZIP og commit. SavedVariables ikke rørt |
| | 0.7.0 dev | dig | Første test, punkt 1–8 nedenfor | IKKE TESTET |

Notér for kørslen: dato, klokkeslæt, karakterens level / klasse / faction, realm-type
(normal / Hardcore / Anniversary), og om andre addons var slået til (du har bl.a. Questie,
Details, DBM, WeakAuras, Bagnon).

## 1. Version og korrekt indlæsning

| # | Tjek | Forventet | Resultat | Noter |
|---|---|---|---|---|
| 1.1 | Fuld genstart af WoW efter installationen | — | IKKE TESTET | |
| 1.2 | AddOns-listen på karaktervalget | StackRivals med flueben, ikke "Out of date" | IKKE TESTET | |
| 1.3 | `/sr version` | `version 0.7.0, engine v1, interface 11509` | IKKE TESTET | Skriv den præcise tekst: |
| 1.4 | `/sr` | Menuen åbner; minimap-knappen står samme sted som før | IKKE TESTET | |

## 2. Bevarede rekorder og Continue last run

| # | Tjek | Forventet | Resultat | Noter |
|---|---|---|---|---|
| 2.1 | Menu → Records | Classic 426, Daily 250, Time Trial 288 (fra 0.3.1) | IKKE TESTET | |
| 2.2 | Dine taster (↑/Z rotér, C hold, Space drop, P pause) | Som i 0.3.1 | IKKE TESTET | |
| 2.3 | Midt i Classic: `/reload` → **Continue last run** | Fortsætter præcis hvor du var, på pause | IKKE TESTET | |
| 2.4 | Log helt ud og ind | Rekorder og indstillinger er der stadig | IKKE TESTET | |

## 3. Classic, Time Trial og Daily Challenge

| # | Tjek | Forventet | Resultat | Noter |
|---|---|---|---|---|
| 3.1 | Classic 2–3 min | Alle taster reagerer; score, linjer og level tæller | IKKE TESTET | |
| 3.2 | Kamp med et mob under spil | Pauser selv, fortsætter efter kampen | IKKE TESTET | |
| 3.3 | Time Trial hele 2:00 | Slutter ved 0:00 med resultat; ny rekord gemmes | IKKE TESTET | |
| 3.4 | Daily Challenge to gange | Samme brikker begge gange; antal forsøg tæller | IKKE TESTET | |
| 3.5 | FPS (Ctrl+R) med og uden StackRivals åbent | Ingen tydelig forskel | IKKE TESTET | FPS: / |

## 4. Spell Battle vs Bot og sejrsregler

Reglen (som på stackrivals.io): **den, der topper ud først, taber**, uanset score. Når 3:00 er
gået, vinder den højeste score.

| # | Tjek | Forventet | Resultat | Noter |
|---|---|---|---|---|
| 4.1 | Pick Spells: 2 til dit bræt, 2 til bottens | Ikonerne vises; Start låser valget | IKKE TESTET | |
| 4.2 | Spells på Q/E/R/F og 1–4 | Mana trækkes, 3 s cooldown, effekten lander | IKKE TESTET | |
| 4.3 | Bomb: vælg mål på dit bræt | Målet vises og rammer det valgte sted | IKKE TESTET | |
| 4.4 | Botten bruger spells mod dig | FROZEN / SPEED UP / BLACKOUT-skilte; brikkerne opfører sig derefter | IKKE TESTET | |
| 4.5 | Botten topper ud først | **VICTORY** med det samme | IKKE TESTET | |
| 4.6 | Du topper ud først (også selvom du fører på point) | **DEFEAT** med det samme | IKKE TESTET | |
| 4.7 | Begge overlever til 3:00 | Højeste score vinder | IKKE TESTET | |
| 4.8 | Niveau 1 og et højere niveau | Højere niveau er tydeligt sværere; ingen hakken | IKKE TESTET | |
| 4.9 | `/reload` midt i Spell Battle | Kampen kan fortsættes eller afsluttes ærligt | IKKE TESTET | |

## 5. Account og Sync

| # | Tjek | Forventet | Resultat | Noter |
|---|---|---|---|---|
| 5.1 | Account → `A7K9-P2XJ` → Link | **PENDING** og en `SRL1…`-kode; ingen password- eller e-mailfelter | IKKE TESTET | |
| 5.2 | `A7K9-P2XK` (tastefejl) | Tydelig fejlbesked | IKKE TESTET | |
| 5.3 | Profile-fanen uden link | "Link account"; ingen falske tal | IKKE TESTET | |
| 5.4 | Sync → `SR1C.b120.e1.srchal-7f3k2p9d.b70e70d3` | Spiller netop den udfordring | IKKE TESTET | |
| 5.5 | Kopiér resultatkoden (Ctrl+C) og indsæt den i Notepad | En lang `SR1R…`-kode på én linje | IKKE TESTET | Længde: |

## 6. Quickplay og Guild Duels

| # | Tjek | Forventet | Resultat | Noter |
|---|---|---|---|---|
| 6.1 | QUICKPLAY → Duel 2:00 → Search → Cancel | SEARCHING med ur; "Search cancelled" | IKKE TESTET | |
| 6.2 | Dit kort på Quickplay-skærmen | Din klassefarve; Alliance blå / Horde rød | IKKE TESTET | |
| 6.3 | Search i 5 min | "No opponent found" med forklaring | IKKE TESTET | |
| 6.4 | Guild Duels → fanerne Guild / Friends / Battle.net / Group / Recent → Refresh | Lister fyldes; navne i klassefarver; ingen "ready" uden StackRivals | IKKE TESTET | Kortet hedder "Guild Duel" i denne build (se fejl 3) |
| 6.5 | Guild Duels → ukendt navn → Challenge | Tydelig fejl | IKKE TESTET | |

## 7. Loot Duel-menu og invitationer

Alene kan kun menuen testes. Invitationer kræver en gruppe (afsnit C i guiden).

| # | Tjek | Forventet | Resultat | Noter |
|---|---|---|---|---|
| 7.1 | Loot Duel uden gruppe | "Join a party or raid first." | IKKE TESTET | |
| 7.2 | I en gruppe som leder: shift-klik et item | Navn i kvalitetsfarve, ikon, tooltip | IKKE TESTET | |
| 7.3 | Vælg 1 spiller → Invite | Afvist: "Pick at least 2 players." | IKKE TESTET | |
| 7.4 | Invitér 2+ → popup hos dem | Item, tid, "Winning doesn't hand you the item"; Join / Pass | IKKE TESTET | Kræver flere spillere |
| 7.5 | Start med kun 1 tilmeldt | Knappen siger "Start: needs 2" og kan ikke trykkes | IKKE TESTET | Kræver flere spillere |

## 8. Lua-fejl og UI-problemer

Slå fejlvisning til før testen: `/console scriptErrors 1` og `/reload`.

| # | Hvornår | Fejltekst (første linje) eller UI-problem | Screenshot | Fejlnr. |
|---|---|---|---|---|
| | | | | |

UI-ting at se efter: knapper der ikke reagerer, tekst der klippes eller overlapper, forkerte
farver, vinduet for stort eller lille, tastatur der "hænger" i spillet efter du lukker
StackRivals, beskeder i WoW-chatten du ikke selv har klikket på.

## Problemer og observationer

| # | Fundet | Hvad | Alvor | Status |
|---|---|---|---|---|
| 1 | Installation | WoW gemte kl. 09:11:56, 14 s før installationen, så klienten var sandsynligvis åben. Nye filer indlæses først efter fuld genstart | proces | Guiden starter med "genstart WoW helt" |
| 2 | Installation | 0.3.1-testen efterlod et afbrudt Classic-spil. 0.7.0 fortsætter et sådant spil med samme tilstand som 0.3.1's motor, og 0.3.1-rekorder inkl. `bestLog` / `bestDate` bevares | sikring | Regressionstests i `tests/test_stress.lua` (syntetiske data) |
| 3 | Gennemgang | Menukortet hed "Guild Duel", skærmen "GUILD DUELS" | kosmetisk | **Rettet på branchen** (kun tekst; mode-ID'er, protokol og SavedVariables uændrede), med test. Kommer i næste test-ZIP, ikke i den installerede build |
| 4 | **Din observation i den rigtige klient** (Spell Battle) | En **rød kasse** over brættet under Spell Battle | synlig fejl | **Årsag fundet i koden:** Bomb-spellens målmarkering (`bombTarget` i `UI/SpellUI.lua`) var en frame *over* brættet med en rød 2-px kant. Den blev tegnet, så længe Bomb kunne kastes. **Rettet på `feature/loot-duel-raid`** (commit `bbb9c81`): målmarkeringen er nu en svag rød flade i brættets baggrundslag *under* brikkerne, og den er skjult uden mana. Regressionstest i `tests/test_spellbattle.lua`, der fejler på den gamle kode. **Ikke bekræftet i klienten:** send gerne et screenshot af kassen, så vi kan se, at det er den samme. Kommer i 0.7.2-test-ZIP'en, ikke i den installerede 0.7.0 |

**Næste test-ZIP (0.7.2 dev)** indeholder rettelse 3 (Guild Duels) og 4 (rød kasse) og Loot Duel
2–40. Den installeres ikke uden din godkendelse.

## Status pr. funktion (fire kategorier)

| Funktion | Automatiske tests (simuleret) | Observeret i rigtig WoW | Kræver 2+ spillere | Ikke implementeret |
|---|---|---|---|---|
| Indlæsning, menu, Classic, Time Trial, Daily | ja | 0.3.1-smoke-test OK; 0.7.0 IKKE TESTET | – | – |
| Spell Battle vs Bot | ja | den røde kasse (fejl 4) | – | – |
| Account / Sync-koder | ja | IKKE TESTET | – | rigtig webforbindelse (bevidst) |
| Quickplay | ja | IKKE TESTET | match kræver en modstander | webmatchmaking (bevidst) |
| Guild Duels / Battle.net-dueller | ja | IKKE TESTET | ja | – |
| Loot Duel 2–10 | ja | IKKE TESTET | ja | – |
| Loot Duel 11–40 | ja (15/20/25/40 simuleret) | IKKE TESTET | ja (en rigtig raid) | – |
| Resultatfarver, CONGRATULATIONS | ja (previews) | IKKE TESTET | ja | – |
| Forever, Retail, Anniversary, Mists | kun mock-indlæsning | IKKE TESTET | – | klient-specifik verifikation (næste opgave) |

Nye fejl fra din test får næste nummer, med testpunkt (fx 4.6), og rettes på `feature/loot-duel`
med en regressionstest, før næste test-ZIP bygges.

## Senere: kompatibilitet med de andre klienter

Efter de første Classic Era-tests. Én fælles spilmotor (`Engine/`, uændret mellem klienter);
klient-specifikke tilpasninger kun i API-laget, hvor det er nødvendigt.

| Klient | Mappe hos dig | Status |
|---|---|---|
| Classic Era | `_classic_era_` | installeret, test i gang |
| Hardcore | samme klient som Classic Era (Hardcore-realms) | IKKE TESTET. Tjek ekstra: ingen påvirkning af karakteren, pause i kamp |
| Anniversary | `_anniversary_` | IKKE TESTET. Interface-nummeret skal aflæses i klienten |
| Classic Progression (Cataclysm / MoP Classic) | `_classic_` | IKKE TESTET. Interface-nummeret skal aflæses i klienten |
| WoW Forever | `_forever_` (1.60.1) | IKKE TESTET. TOC har 16001 |
| Retail | `_retail_` | IKKE TESTET. TOC har 120105 |

For hver: `/dump select(4, GetBuildInfo())` giver interface-nummeret; sammenlign med TOC'ens
`## Interface`-linje, før noget installeres (altid med backup og din godkendelse).
