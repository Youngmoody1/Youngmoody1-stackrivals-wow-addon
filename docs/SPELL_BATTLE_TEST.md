# Spell Battle 0.5.0: test i rigtige WoW-klienter

**Rækkefølge:** først 0.3.1 (solo) i en rigtig klient (`docs/TEST_DAY.md`). Når den test er bestået:
procedure A (Spell Battle mod bot, én klient), derefter procedure B (to spillere).

**Status:** alt nedenfor er **UTESTET i WoW**. Der findes kun automatiske tests i en simuleret
WoW-klient (373+ Lua-tests). Hvert punkt er først bestået, når det er krydset af her efter en rigtig
klienttest.

## Før testen

1. **Tag backup** af `WTF\Account\<KONTO>\SavedVariables\StackRivals.lua` og af mappen
   `Interface\AddOns\StackRivals`. 0.3.1-installationen skal kunne lægges tilbage uændret.
2. **Installér 0.5.0** fra branchen `spellbattle`: hent ZIP'en fra GitHub Actions (artifact
   "StackRivals-build") eller fra `tools/build_release.sh`. Mappen skal hedde `StackRivals`.
3. **Start WoW.** Skriv `/sr version` og tag screenshot: det skal vise "version 0.5.0, engine v1, interface …".
4. **Røde fejlvinduer:** tag screenshot med det samme. `/console scriptErrors 1` viser Lua-fejl.

---

## A. Spell Battle mod bot (én klient)

| # | Gør dette | Det skal ske | Resultat |
|---|---|---|---|
| A1 | `/sr` → kortet **Spell Battle** ✱ | Pick Spells: 9 spells med ikoner, 2 + 2 valgt, 5 bot-niveauer, rekord for det valgte niveau | UTESTET |
| A2 | Klik spells i begge grupper | Kun 2 + 2 kan være valgt. Det ældste valg i gruppen skiftes ud. Teksten "Your keys: Q … E … R … F …" følger med | UTESTET |
| A3 | Vælg **Rookie** → Start ✱ | 4 s nedtælling. Brættet er dit. Venstre: SCORE, MANA 0/20, 4 felter med tast og pris. Højre: NEXT og ROOKIE BOT med minibræt | UTESTET |
| A4 | Ryd linjer | MANA stiger (1/3/5/8 + combo). Et felt får en tyk kant og et lille "bump", når det kan kastes | UTESTET |
| A5 | Tryk **Q** (eller **1**) | Effekten ses på brættet, og "LINE BLAST" vises. Alle 4 felter får nedtælling (3,0 → 0,0 s) | UTESTET |
| A6 | Tryk en spell uden nok mana | "NOT ENOUGH MANA" vises, og der sker intet andet | UTESTET |
| A7 | Kast **Garbage** (R) ✱ | "GARBAGE SENT". Efter ca. 1,5 s får bottens minibræt 2 grå rækker | UTESTET |
| A8 | Lad botten kaste på dig (prøv Contender/Elite) ✱ | "INCOMING GARBAGE 1.4s", en blå bjælke ved brættet, derefter grå rækker. FROZEN / SPEED UP / BLACKOUT vises øverst på brættet | UTESTET |
| A9 | Vind: botten topper ud, mens du fører | **VICTORY** med det samme. Uret står stille, og taster/spells gør ikke mere i spillet | UTESTET |
| A10 | Botten topper ud, mens du er bagud | Du spiller videre, og panelet viser "beat N to win". Når du passerer scoren: VICTORY | UTESTET |
| A11 | Top selv ud | "FINISHED – The bot is finishing its run…" i et øjeblik, derefter VICTORY / DEFEAT | UTESTET |
| A12 | Spil 3:00 færdigt | Kampen slutter ved 0:00. Rekorden står i Pick Spells | UTESTET |
| A13 | Prøv alle 5 bot-niveauer (1 kamp hver) | Rookie er tydeligt lettere end Rival. Notér scorerne | UTESTET |
| A14 | Gå i combat midt i en kamp | Begge brætter står stille. Resume virker først efter combat | UTESTET |
| A15 | Midt i en kamp: `/reload` → **Continue your Spell Battle run** | Brættet, botten, mana og spells på vej er præcis som før | UTESTET |
| A16 | Efter kampen: tryk Q / E / R / F / 1–4 uden for et run | Det er WoW's egne taster igen (bevægelse, actionbar) | UTESTET |
| A17 | Settings → **Spells 1-4**: skift Q til en anden tast | Den nye tast virker i næste kamp. Pick Spells viser den nye tast | UTESTET |
| A18 | UI-skala: Settings → Size 70 % og 140 %; WoW-UI-skala lav/høj ✱ | MANA, pris og nedtælling på felterne er stadig læsbare. Notér den mindste skala, hvor de kan læses | UTESTET |
| A19 | Performance: vis FPS (Ctrl+R) under en kamp mod Rival-botten | Ingen hak, heller ikke når du topper ud. Notér FPS med og uden vinduet åbent | UTESTET |
| A20 | Log ud, og ind igen | Rekorderne og dit valg af spells/bot er gemt | UTESTET |

## B. Spell Battle mellem to spillere (to klienter, samme realm eller forbundne realms)

| # | Gør dette | Det skal ske | Resultat |
|---|---|---|---|
| B1 | Begge: `/sr version` | Begge viser 0.5.0 | UTESTET |
| B2 | A: Duel → **Spell Battle** → Find players ✱ | B står på listen med "v0.5.0" (en 0.4-spiller vises som "needs 0.5.0") | UTESTET |
| B3 | A: Challenge. B: Accept | Begge lobbyer viser "SPELL DUEL - 3:00" og dine 4 spells | UTESTET |
| B4 | Begge: **Change spells** → vælg → Done → **Ready** ✱ | Der står "locked" ud for dine spells. Nedtællingen starter samtidig (±1 s) | UTESTET |
| B5 | Sammenlign NEXT lige efter start ✱ | Samme brikker hos begge (fælles seed) | UTESTET |
| B6 | A kaster Garbage på B ✱ | B ser "INCOMING GARBAGE" og grå rækker ca. 1,5 s senere. **Notér forsinkelsen** | UTESTET |
| B7 | Hold øje med "VS …"-panelet | Modstanderens score opdateres ca. hvert 2. sekund | UTESTET |
| B8 | B går i combat i 10 s | **Begge** spil pauser. A's knap siger "Waiting for rival…". Når B er ude af combat og trykker Resume, kører begge igen | UTESTET |
| B9 | B trykker P og bliver i pause i over 60 s | B's duel opgives ("paused for more than a minute"). A vinder ("Your rival left the duel") | UTESTET |
| B10 | Spil 3:00 færdigt (begge) ✱ | Samme to tal hos begge (spejlvendt). "Both games replayed together on your PC" og efter et øjeblik **"Confirmed by both PCs."** | UTESTET |
| B11 | **Rematch** | Ny lobby, Spell Battle igen, og spells vælges igen | UTESTET |
| B12 | Midt i en kamp: B lukker WoW (Alt+F4) | A vinder efter ca. 35 s ("Lost contact with your rival") | UTESTET |
| B13 | Efter hver duel: begge skriver `/sr duel debug` ✱ | Screenshot. Viser beskeder, forsinkelser og resultat | UTESTET |

✱ = tag screenshot.

## Efter testen

- Gem `WTF\Account\<KONTO>\SavedVariables\StackRivals.lua` fra **begge** maskiner (der ligger
  `duelDiag` med diagnostik). Ingen kontooplysninger ligger i den fil.
- Læg 0.3.1-backuppen tilbage, hvis 0.5.0 ikke skal blive liggende.
- Send screenshots og de to SavedVariables-filer til Claude. Først derefter kan punkterne krydses af.
