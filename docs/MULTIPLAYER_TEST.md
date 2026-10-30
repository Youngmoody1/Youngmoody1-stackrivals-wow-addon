# Multiplayer-test med to rigtige WoW-klienter (dansk, til ejeren)

Dueller er indtil nu kun testet med **simulerede** klienter (tests/netsim.lua). Denne guide er den
første rigtige test. Først når alle ✅-punkter er gennemført med to rigtige klienter, må duellerne kaldes
"klienttestet". Testen tager ca. 45 minutter.

## Det skal I bruge

- **To spillere med betalt game time.** Trial- og Veteran-konti kan ikke sende addon-beskeder.
  Det er Blizzards regel, og addon'et viser det tydeligt.
- **Samme realm eller connected realms og samme faction.** Whisper på tværs af factions er ikke
  dokumenteret og testes separat i punkt 13.
- **Samme guild** (til "Find players"), ellers en fælles party.
- **Multiplayer-buildet (0.4.0-dev) installeret hos begge.** Det er ikke det samme som 0.3.1.
  Claude installerer det med backup, når du siger til. 0.3.1 testes først og forbliver release-kandidaten.

## 0. Før testen (begge spillere)

```
/console scriptErrors 1
/sr version
/sr duel debug
```

Tag et screenshot af `/sr duel debug` hos begge. Første linje skal sige `transport: on, prefix result 0`
(eller `1`). Står der `off`, eller nævnes Trial, så stop: duellerne kan ikke virke på den konto.

Lad chatten være synlig under hele testen. Røde fejlvinduer: screenshot med det samme.

## 1. Testliste

Spiller **A** udfordrer, spiller **B** svarer, medmindre andet står. Tag screenshot ved hvert ✱.

| # | Gør dette | Det skal ske | ✅ |
|---|---|---|---|
| 1 | A: `/sr duel` → **Find players** ✱ | B står på listen med "v0.4.0". Prøv også i en party uden guild | |
| 2 | A: **Challenge** B (Blitz 2:00). B: **Decline** | B får en popup med 30 s nedtælling. A ser "declined your challenge" | |
| 3 | A udfordrer igen. B: **Accept**. Begge: **Ready** ✱ | Lobby hos begge. Nedtællingen starter samtidig (±1 s) | |
| 4 | Sammenlign NEXT-brikkerne lige efter start ✱ | **Samme brikker i samme rækkefølge** hos begge (samme seed) | |
| 5 | Spil. Hold øje med modstanderens score under NEXT | Den opdateres ca. hvert 2. sekund. Rød = modstanderen fører | |
| 6 | Spil til tiden er gået ✱ (begge) | VICTORY hos den ene og DEFEAT hos den anden. Begge scorer passer. Tekst: "replayed to the same score on your PC (peer check)" | |
| 7 | A: **Rematch**. B: Accept, Ready | Popup "Rematch from A". Nye brikker. Kampen gennemføres | |
| 8 | Duel med **3:00 web rules** | Tidsgrænse 3:00 og 4 s nedtælling | |
| 9 | Under kampen: B angriber en træningsdukke (combat) | Bs spil pauser med det samme, mens A spiller videre. Efter kampen: B trykker Resume. Duellen afsluttes normalt | |
| 10 | Under kampen: B skriver `/reload` | A spiller videre og vinder efter sin tid ("Your rival left the duel"). Efter reload: `/sr duel debug` hos B viser ingen duel. Bs nederlag er gemt | |
| 11 | I lobbyen: B logger helt ud | A ser "is offline" eller "Lost contact" inden for ca. 35 s. Ingen sejr eller tab registreres. **Notér præcis hvilken systemlinje A får** ("No player named ..." eller "Player is offline."), og om den gentages | |
| 12 | Under kampen: B trykker Esc, så **Forfeit duel** | Første klik: "Click again to forfeit". Andet klik: B taber, og A vinder efter sin tid | |
| 13 | Valgfri: A og B af **forskellig faction** på samme realm | Notér om Find players/Challenge virker. Det er udokumenteret, så alt er et nyttigt resultat | |
| 14 | A og B trykker **Challenge** på hinanden samtidig | Begge havner i **samme** lobby (ikke "busy") | |
| 15 | B har markøren i chatten (skriver), når nedtællingen starter | Bs spil starter pauset: "Paused so you can type" | |
| 16 | Valgfri: begge i en dungeon (inde i instansen), samme gruppe | Duellen virker. Gentag punkt 5–6 | |

### 1b. Spell Battle (kun 0.5.0)

Spell Battle har sine egne testprocedurer: **`docs/SPELL_BATTLE_TEST.md`** (A: mod bot, B: to spillere).

## 2. Efter hver duel

Begge skriver `/sr duel debug` og tager screenshot. Det viser:

- om modstanderen bliver hørt ("last heard 1.2 s ago");
- modstanderens tick og score;
- hvor mange log-stykker der er modtaget;
- om resultatet er bekræftet ("rival confirmed (FIN)");
- hvilke afsendelseskoder klienten har givet (0 = ok, 3/8 = throttle, 11 = lockdown, 12 = offline).

## 3. Når testen er færdig

1. Begge skriver `/reload`. Først nu skrives SavedVariables-filen.
2. Begge kører `tools\collect-diagnostics.ps1` (ændrer og sletter intet; kontonavne anonymiseres),
   eller sender `WTF\Account\<konto>\SavedVariables\StackRivals.lua`.
3. Send zip/filer og screenshots til Claude.

Filen indeholder de sidste 5 dueller (`duelDiag`): match-id, modstanderens navn, roller, regler,
klient-build, resultat, tællere og en kort hændelseslog, fx:

```
0.0 >INV            sendt og accepteret af klienten (accepteret er IKKE leveret)
1.2 <ACC            modtaget
3.1 ~lobby          vores tilstand skiftede
14.0 <SC 1200/5400  modstanderens spil: tick 1200 (20 s), score 5400
95.2 =win checked 61200-58800
```

Ingen chat, ingen kontodata, kun de to karakternavne i duellen.

## 4. Sådan læser Claude diagnostikken

| Det ses | Det betyder sandsynligvis |
|---|---|
| A har `>INV`, men B har ingen `<INV` | Whisper når ikke frem: realm/faction/navneformat. Navnet i Bs log viser formatet |
| Mange `r3`/`r8` | Throttling. Bliver det ved inde i instanser, sænkes tempoet |
| `r11` | Lockdown (12.x). Comm prøver igen af sig selv. Skal forsvinde efter kampen |
| `r12` eller `!END offline` | Klienten melder modstanderen offline |
| `maxGap` over 20 s | Lang tavshed fra modstanderen (loadingskærm, lag, disconnect) |
| `sent.LOG` hos A ≠ `recv.LOG` hos B | Log-stykker tabt. RQ skal have hentet dem; ellers bliver resultatet "no result" |
| Forskellig `result` hos A og B for samme `mid` | Fejl. Skal rettes før lancering |

## 5. Det kan kun denne test afgøre

- Hvilket format afsendernavnet har i `CHAT_MSG_ADDON` (med eller uden realm).
- Om ens egne guild-beskeder kommer tilbage (addon'et filtrerer dem uanset hvad).
- Om klienten returnerer `TargetOffline` (12) med det samme, eller kun viser systemlinjen.
- Om chatfilteret (`ChatFrame_AddMessageEventFilter` / `ChatFrameUtil.AddMessageEventFilter`)
  findes i klienten og skjuler "No player named ...".
- Lockdown-situationer (12.x) og throttling inde i instanser.
- Forevers egen klient: dueller kan først testes der efter lanceringen 5. nov.
