# Første rigtige test i WoW Classic Era

Rækkefølge: **A** kort smoke-test af den installerede 0.3.1 → Claude installerer 0.7.0 dev →
**B** test af 0.7.0. Alt står som **IKKE TESTET**, indtil du har prøvet det i klienten.
Automatiske tests og previews er simulerede og tæller ikke som klienttests.

Din klient: Classic Era **1.15.9** (build 70576, interface **11509**). Både 0.3.1 og 0.7.0 har
11509 i TOC'en, så addon'et bør ikke stå som "Out of date".

## Før hver test: slå Lua-fejl til (én gang)

Skriv i chatten, når du er logget ind på en karakter:

```
/console scriptErrors 1
/reload
```

Nu viser WoW en fejlboks, hvis addon'et laver en Lua-fejl. Tag et screenshot af boksen (Print
Screen) og skriv ned, hvad du lige havde gjort.

## A. Smoke-test af 0.3.1 (ca. 10 min, før 0.7.0 installeres)

| # | Gør dette | Forventet | Resultat |
|---|---|---|---|
| A1 | Åbn Battle.net → **WoW Classic** → vælg **Classic Era** → Play | Spillet starter | IKKE TESTET |
| A2 | På karaktervalget: **AddOns** (nederst til venstre) | StackRivals står med flueben | IKKE TESTET |
| A3 | Log ind på en karakter, `/sr version` | `version 0.3.1, engine v1, interface 11509` | IKKE TESTET |
| A4 | `/sr`, spil **Classic** ca. 1 minut | Brikker falder, taster virker, score tæller | IKKE TESTET |
| A5 | **Blitz 2:00** (hedder Time Trial i 0.7.0) | Uret tæller ned fra 2:00 | IKKE TESTET |
| A6 | **Daily Blitz** | Starter; samme brikker efter `/reload` | IKKE TESTET |
| A7 | Hele vejen | Ingen Lua-fejlbokse | IKKE TESTET |
| A8 | Log helt ud (tilbage til karaktervalg) | Gemmer dine rekorder | IKKE TESTET |

Skriv til Claude: **"0.3.1 OK"** (eller hvad der gik galt). Først derefter installeres 0.7.0.
Luk WoW helt, før Claude installerer.

## B. Test af 0.7.0 (efter installation)

### Start

1. Åbn WoW Classic Era (Battle.net → WoW Classic → Classic Era → Play).
2. På karaktervalget: **AddOns** → StackRivals har flueben. Står der "Out of date", så sæt
   flueben i **Load out of date AddOns** og skriv det ned.
3. Log ind på en karakter og skriv `/sr version`.
   Forventet: `version 0.7.0, engine v1, interface 11509`.
4. Skriv `/sr` → menuen åbner.
5. Test funktionerne i rækkefølgen nedenfor.

### Prioritet 1: spillet

| # | Gør dette | Forventet | Resultat |
|---|---|---|---|
| B1 | **Classic**: spil 2–3 minutter. Prøv alle taster: ←/→, ↑ og Z (rotér), ↓, Space (drop), C (hold), P (pause) | Alt reagerer, ingen forsinkelse; dine gamle tastvalg fra 0.3.1 er bevaret | IKKE TESTET |
| B2 | Gå i kamp med et mob, mens du spiller | Spillet pauser selv; fortsæt efter kampen | IKKE TESTET |
| B3 | **Time Trial** (`/sr trial`) | 2:00 ned til 0; resultat og rekord vises | IKKE TESTET |
| B4 | **Daily Challenge** (`/sr daily`), derefter `/reload` og start igen | Samme brikker begge gange | IKKE TESTET |
| B5 | **Spell Battle vs Bot** (`/sr spell`): vælg spells, niveau 1 | Spells på Q/E/R/F og 1–4, mana og cooldown; Victory eller Defeat | IKKE TESTET |
| B6 | Menu → **Records** | Rekorder fra B1–B5 står der; intet fra 0.3.1 er forsvundet | IKKE TESTET |
| B7 | FPS mens du spiller | Skriv tallet ned (Ctrl+R viser FPS) | IKKE TESTET |

### Prioritet 2: konto, Quickplay og chat (alene)

| # | Gør dette | Forventet | Resultat |
|---|---|---|---|
| B8 | Menu → **Account** → skriv testkoden `A7K9-P2XJ` → Link | Status **PENDING** og en lang `SRL1…`-kode. Ingen felter til password eller e-mail. (Hjemmesiden har ikke Link-siden endnu, så du kan ikke blive LINKED.) | IKKE TESTET |
| B9 | Skriv en forkert kode: `A7K9-P2XK` | En tydelig fejl ("typo"), ingen Lua-fejl | IKKE TESTET |
| B10 | Account → **Sync** → indsæt `SR1C.b120.e1.srchal-7f3k2p9d.b70e70d3` | Starter præcis den udfordring (2:00); bagefter kan du kopiere en `SR1R…`-resultatkode | IKKE TESTET |
| B11 | Menu → **Quickplay** → Duel 2:00 → **Search**, efter 30 s **Cancel search** | "SEARCHING" med ur, derefter "Search cancelled"; dit kort i din klassefarve; "Web players: not connected" | IKKE TESTET |
| B12 | Search igen og vent 5 minutter | "No opponent found" med forklaring (forventet, når ingen andre søger) | IKKE TESTET |
| B13 | Chat | Chat kan kun testes med en modstander. Tjek kun, at der ikke er kommet beskeder i din normale WoW-chat, du ikke selv har klikket på | IKKE TESTET |
| B14 | Log helt ud og ind igen | Indstillinger, rekorder og Account-status (PENDING udløber efter 15 min) er bevaret | IKKE TESTET |

### Senere, med flere rigtige spillere

Duel, Quick Duel, Spell Duel, Guild Duels, match-chat, Battle.net og Loot Duel. Se listen
nederst og `docs/LOOT_DUEL.md` L1–L12.

## Fejlrapport

Send dette for hver fejl (kopier skabelonen):

```
Fejl nr.:
Test-punkt (fx B5):
Hvad gjorde jeg lige før:
Hvad skete der:
Hvad forventede jeg:
Lua-fejlboks? (ja/nej - screenshot vedlagt)
/sr version siger:
Tid (ca. klokkeslæt):
```

Vedhæft:

* **Screenshots**: `C:\Program Files (x86)\World of Warcraft\_classic_era_\Screenshots\`.
* **Addon-version og klient**: teksten fra `/sr version`.
* **SavedVariables**: kun filen
  `_classic_era_\WTF\Account\<din konto>\SavedVariables\StackRivals.lua`. Den indeholder
  addon'ets indstillinger, rekorder og en lille diagnose (klient, interface). Send ikke andre filer
  fra WTF-mappen.

Kopiér aldrig passwords, Battle.net-oplysninger eller andre private kontooplysninger ind i en
fejlrapport. StackRivals beder aldrig om dem.

Fejl rettes på udviklingsbranchen med en regressionstest, og du får en ny testbuild.

## Gå tilbage til 0.3.1

Backup ligger i
`C:\Program Files (x86)\World of Warcraft\StackRivals-backups\2026-11-04_0.3.1_before-0.7.0\`
(se `LAES-MIG.txt` i mappen):

1. Luk WoW helt.
2. Slet `_classic_era_\Interface\AddOns\StackRivals`.
3. Kopiér backup-mappen `AddOns\StackRivals` til `_classic_era_\Interface\AddOns\`.
4. Kopiér den nyeste backup af `StackRivals.lua` til
   `_classic_era_\WTF\Account\<din konto>\SavedVariables\` (erstat den, der ligger der).
5. Start WoW.

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
