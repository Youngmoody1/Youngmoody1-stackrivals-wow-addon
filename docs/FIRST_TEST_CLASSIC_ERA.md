# Rigtig test i WoW Classic Era: 0.7.0 dev

Alt står som **IKKE TESTET**, indtil du har prøvet det i klienten. Automatiske tests og previews
er simulerede og tæller ikke som klienttests. Problemer registreres i
`docs/TEST_LOG_CLASSIC_ERA.md`.

## Status (4. november 2026)

| Trin | Status |
|---|---|
| A. Smoke-test af 0.3.1 | **OK** (dig, 4/11). Gemt: Classic 426, Daily 250, Blitz 288 |
| Backup før installation | `StackRivals-backups\2026-11-04_0.3.1_before-0.7.0\` (addon + gemte data) og `…\2026-11-04_after-0.3.1-smoketest\` (gemte data efter smoke-testen) |
| Installation af 0.7.0 | Kun Classic Era. 69 filer, læst tilbage og byte-identiske med ZIP'en og commit `9a68952`. TOC: version 0.7.0, interface 11509. SavedVariables ikke rørt |
| B. Test af 0.7.0 | IKKE TESTET |

Din klient: Classic Era **1.15.9** (build 70576, interface **11509**).

## Først: genstart WoW helt

WoW var sandsynligvis åbent under installationen. Nye addon-filer indlæses kun efter en
**fuld genstart**; `/reload` eller at gå tilbage til karaktervalget er ikke nok.

1. Luk WoW helt (Exit Game, eller luk vinduet).
2. Start WoW Classic Era igen fra Battle.net (WoW Classic → Classic Era → Play).
3. På karaktervalget: **AddOns** → StackRivals har flueben. Står der "Out of date", så sæt flueben
   i **Load out of date AddOns** og skriv det ned.
4. Log ind, og slå Lua-fejl til (én gang):
   ```
   /console scriptErrors 1
   /reload
   ```
5. Skriv `/sr version`. Forventet: `version 0.7.0, engine v1, interface 11509`.
6. Skriv `/sr` → menuen åbner. Dine rekorder fra 0.3.1 skal stå under **Records**.

## B. Test af 0.7.0 alene (prioriteret)

### Prioritet 1: spillet

| # | Gør dette | Forventet | Resultat |
|---|---|---|---|
| B1 | Menu → **Records** | Classic 426, Daily 250, Time Trial (tidligere Blitz) 288 fra 0.3.1 er der | IKKE TESTET |
| B2 | **Classic**: spil 2–3 minutter. Alle taster: ←/→, ↑ og Z (rotér), ↓, Space (drop), C (hold), P (pause) | Alt reagerer uden forsinkelse; dine tastvalg er bevaret | IKKE TESTET |
| B3 | Mens du spiller: gå i kamp med et mob | Spillet pauser selv; fortsæt bagefter | IKKE TESTET |
| B4 | Midt i et Classic-spil: `/reload` | Menuen tilbyder **Continue last run**; spillet fortsætter præcis hvor det var | IKKE TESTET |
| B5 | **Time Trial** (`/sr trial`): spil hele 2:00 | Uret går til 0:00; resultat og rekord | IKKE TESTET |
| B6 | **Daily Challenge** (`/sr daily`) to gange | Samme brikker begge gange; "tries" tæller op | IKKE TESTET |
| B7 | **Spell Battle vs Bot** (`/sr spell`): vælg 2 + 2 spells, niveau 1 (Rookie) | Spells på Q/E/R/F og 1–4, mana, cooldown, bombens mål; Victory eller Defeat | IKKE TESTET |
| B8 | Spell Battle: niveau 3 eller højere | Botten er mærkbart stærkere; ingen hakken | IKKE TESTET |
| B9 | FPS under spil (Ctrl+R viser FPS) | Skriv tallet ned, med og uden StackRivals åbent | IKKE TESTET |

### Prioritet 2: konto, Quickplay og Guild Duels (tidligere Challenge Friends)

| # | Gør dette | Forventet | Resultat |
|---|---|---|---|
| B10 | **Account** → skriv testkoden `A7K9-P2XJ` → Link | **PENDING** og en lang `SRL1…`-kode. Ingen felter til password eller e-mail. (Hjemmesiden har ikke Link-siden endnu, så du kan ikke blive LINKED) | IKKE TESTET |
| B11 | Skriv en forkert kode: `A7K9-P2XK` | En tydelig fejl om en tastefejl, ingen Lua-fejl | IKKE TESTET |
| B12 | Account → **Sync** → indsæt `SR1C.b120.e1.srchal-7f3k2p9d.b70e70d3` | Starter netop den udfordring (2:00); bagefter kan du kopiere en `SR1R…`-kode (Ctrl+C) | IKKE TESTET |
| B13 | Account → **Profile** | "Link account"-knap; ingen falske tal | IKKE TESTET |
| B14 | **QUICKPLAY** → Duel 2:00 → **Search**, efter 30 s **Cancel search** | "SEARCHING" med ur og "Looking in: …"; dit kort i din klassefarve og faction-farve; "Web players: not connected" | IKKE TESTET |
| B15 | Search igen og vent 5 minutter | "No opponent found" med forklaring (forventet, når ingen andre søger) | IKKE TESTET |
| B16 | **Guild Duel**-kortet → fanerne Guild / Friends / Battle.net / Group / Recent → **Refresh** | Listerne fyldes; navne i klassefarver; spillere uden StackRivals står ikke som "ready" | IKKE TESTET |
| B17 | Guild Duel → skriv et navn, der ikke findes → Challenge | En tydelig fejl, ingen Lua-fejl | IKKE TESTET |
| B18 | **Loot Duel** uden gruppe | "Join a party or raid first." | IKKE TESTET |
| B19 | Hele vejen | Ingen beskeder i din WoW-chat, som du ikke selv har klikket på | IKKE TESTET |
| B20 | Log helt ud og ind | Indstillinger, rekorder og Account-status bevaret (PENDING udløber efter 15 min) | IKKE TESTET |

## C. Forberedt: test med flere rigtige spillere

Kræver at alle har 0.7.0 dev installeret (med backup og deres godkendelse) og har kørt
`/console scriptErrors 1`. Skriv realm, faction og klientversion ned for hver spiller.

| Test | Hvem | Opsætning | Tjekliste |
|---|---|---|---|
| **Guild Duels** | 2 | Samme guild eller samme gruppe | `SPELL_BATTLE_TEST.md` procedure B/C (Duel 2:00, Spell Duel 3:00, Rematch), og B16 med to spillere |
| **Quick Duel** | 2 | Samme guild | Procedure D (D1–D10) |
| **Match-chat** | 2 | Under en Quick Duel eller Guild Duel | D5, D6 (skriv **under** kampen), D10 (Mute) |
| **Battle.net** | 2 | Battle.net-venner på **forskellige, ikke-forbundne** realms, samme WoW-version | Procedure F (F1–F5) |
| **Tværs af factions** | 2 | Alliance + Horde på samme realm | D11, F4 |
| **Loot Duel, gruppe** | 3–5 | Én party; lederen har et item i tasken | `LOOT_DUEL.md` L1–L8, L10, L12 |
| **Loot Duel, raid** | 10–40 | Raid; helst master loot | L9, L11. Notér tid fra invite til resultat |
| **Ældre version** | 2 | Én med 0.6.x, én med 0.7.0 | Duel virker; 0.6.x ignorerer Loot Duel-beskeder |

Loot Duel uddeler aldrig items og ændrer aldrig loot-indstillinger: vinderen får itemet af
raidlederen eller master looteren med WoW's normale loot.

## Fejlrapport

Send dette for hver fejl (kopier skabelonen):

```
Fejl nr.:
Test-punkt (fx B7):
Hvad gjorde jeg lige før:
Hvad skete der:
Hvad forventede jeg:
Lua-fejlboks? (ja/nej - screenshot vedlagt)
/sr version siger:
Tid (ca. klokkeslæt):
```

Vedhæft:

* **Screenshots** (Print Screen): `C:\Program Files (x86)\World of Warcraft\_classic_era_\Screenshots\`.
* **SavedVariables**: kun filen
  `_classic_era_\WTF\Account\<din konto>\SavedVariables\StackRivals.lua`. Claude kan også selv
  læse den fra din computer, når du siger til.

Kopiér aldrig passwords, Battle.net-oplysninger eller andre private kontooplysninger ind i en
fejlrapport. StackRivals beder aldrig om dem.

Hver fejl rettes på `feature/loot-duel` med en regressionstest, og du får en ny testbuild.

## Gå tilbage til 0.3.1

1. Luk WoW helt.
2. Slet `_classic_era_\Interface\AddOns\StackRivals`.
3. Kopiér `StackRivals-backups\2026-11-04_0.3.1_before-0.7.0\AddOns\StackRivals` til
   `_classic_era_\Interface\AddOns\`.
4. Kopiér `StackRivals-backups\2026-11-04_after-0.3.1-smoketest\SavedVariables\MIKESUNE\StackRivals.lua`
   til `_classic_era_\WTF\Account\MIKESUNE\SavedVariables\` (erstat den, der ligger der).
5. Start WoW.

Claude kan også gøre det for dig, når du beder om det.

## Det kræver stadig to (eller flere) rigtige spillere

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
