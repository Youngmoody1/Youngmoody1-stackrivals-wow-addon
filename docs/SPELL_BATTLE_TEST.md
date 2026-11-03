# Spell Battle 0.5.x: test i rigtige WoW-klienter

**Rækkefølge:** først 0.3.1 (solo) i en rigtig klient (`docs/TEST_DAY.md`). Når den test er bestået:
procedure A (Spell Battle mod bot, én klient), derefter procedure B (to spillere).

**Status:** alt nedenfor er **UTESTET i WoW**. Der findes kun automatiske tests i en simuleret
WoW-klient (Lua-tests, se `docs/SPELL_BATTLE.md` §5). Hvert punkt er først bestået, når det er
krydset af her efter en rigtig klienttest.

**To separate testbuilds** (begge fra branchen `spellbattle`, begge bygget og tjekket af GitHub Actions):

| Build | Fil | Til | Hvornår |
|---|---|---|---|
| **vs Bot-testbuild** | `StackRivals-0.5.1-vsbot.zip` (artifact **StackRivals-vsbot-test**) | procedure A | når 0.3.1-testen er godkendt |
| **Fuld build (dueller)** | `StackRivals-0.5.1.zip` (artifact **StackRivals-build**) | procedure B | først efter din godkendelse af A |

vs Bot-buildet er den samme kode, men guild-dueller er slået fra: addon'et registrerer og besvarer
ingen addon-beskeder, Duel-kortet siger "Off in this test build", og `/sr duel` siger, at dueller
er slået fra. `/sr version` viser "build vsbot (duels off)". Mappen hedder stadig `StackRivals`.

## Før testen

1. **Tag backup** af `WTF\Account\<KONTO>\SavedVariables\StackRivals.lua` og af mappen
   `Interface\AddOns\StackRivals`. 0.3.1-installationen skal kunne lægges tilbage uændret.
2. **Installér det rigtige build** (se tabellen ovenfor): pak ZIP'en ud, så mappen
   `Interface\AddOns\StackRivals` erstattes. Rør ikke andre addons.
3. **Start WoW.** Skriv `/sr version` og tag screenshot: det skal vise "version 0.5.1, engine v1, interface …"
   og, for procedure A, "build vsbot (duels off)".
4. **Røde fejlvinduer:** tag screenshot med det samme. `/console scriptErrors 1` viser Lua-fejl.

---

## A. Spell Battle mod bot (én klient)

| # | Gør dette | Det skal ske | Resultat |
|---|---|---|---|
| A1 | `/sr` → kortet **Spell Battle** ✱ | Pick Spells: 9 spells med ikoner, 2 + 2 valgt, 5 bot-niveauer, rekord for det valgte niveau | UTESTET |
| A2 | Klik spells i begge grupper | Kun 2 + 2 kan være valgt. Det ældste valg i gruppen skiftes ud. Teksten "Your keys: Q … E … R … F …" følger med | UTESTET |
| A0 | Menuen: kortet **Duel** ✱ | Gråt, "Off in this test build". `/sr duel Navn` skriver, at dueller er slået fra | UTESTET |
| A3 | Vælg **Rookie** → Start ✱ | 4 s nedtælling. Brættet er dit. Venstre: SCORE, MANA 0/20, 4 felter med ikon og, under ikonet, tast (venstre) og pris (højre). Højre: NEXT og ROOKIE BOT med minibræt | UTESTET |
| A4 | Ryd linjer | MANA stiger (1/3/5/8 + combo). Et felt får en tyk kant og et lille "bump", når det kan kastes | UTESTET |
| A5 | Tryk **Q** (eller **1**) | Effekten ses på brættet, og "LINE BLAST" vises **under brættet** (ikke oven på brikkerne). Alle 4 felter får nedtælling (3,0 → 0,0 s) | UTESTET |
| A6 | Tryk en spell uden nok mana | "NOT ENOUGH MANA" vises, og der sker intet andet | UTESTET |
| A7 | Kast **Garbage** (R) ✱ | "GARBAGE SENT". Efter ca. 1,5 s får bottens minibræt 2 grå rækker | UTESTET |
| A8 | Lad botten kaste på dig (prøv Contender/Elite) ✱ | "INCOMING GARBAGE 1.4s" **under brættet**, en blå bjælke ved brættets venstre kant, derefter grå rækker. FROZEN / SPEED UP / BLACKOUT vises på samme linje under brættet. Intet spell-tekst dækker den faldende brik | UTESTET |
| A9 | Botten topper ud, mens du stadig spiller (også hvis du er bagud) | **VICTORY** med det samme, uanset score. Uret står stille, og taster/spells gør ikke mere | UTESTET |
| A10 | Pick Spells ✱ | Under rekorden står "First to top out loses. At 3:00 the higher score wins." | UTESTET |
| A11 | Top selv ud (også hvis du fører) | **DEFEAT** med det samme: "You topped out first: the bot wins, whatever the score." Botten stopper, hvor den var | UTESTET |
| A12 | Spil 3:00 færdigt (ingen topper ud) | Kampen slutter ved 0:00, og den højeste score vinder. Rekorden står i Pick Spells | UTESTET |
| A13 | Prøv alle 5 bot-niveauer (1 kamp hver) | Rookie er tydeligt lettere end Rival. Notér scorerne | UTESTET |
| A14 | Gå i combat midt i en kamp | Begge brætter står stille. Resume virker først efter combat | UTESTET |
| A15 | Midt i en kamp: `/reload` → **Continue your Spell Battle run** | Brættet, botten, mana og spells på vej er præcis som før | UTESTET |
| A16 | Efter kampen: tryk Q / E / R / F / 1–4 uden for et run | Det er WoW's egne taster igen (bevægelse, actionbar) | UTESTET |
| A17 | Settings → **Spells 1-4**: skift Q til en anden tast | Den nye tast virker i næste kamp. Pick Spells viser den nye tast | UTESTET |
| A18 | UI-skala: Settings → Size 70 % og 140 %; WoW-UI-skala lav/høj ✱ | MANA, tast, pris og nedtælling på felterne og linjen under brættet er stadig læsbare. Notér den mindste skala, hvor de kan læses | UTESTET |
| A19 | Performance: vis FPS (Ctrl+R) under en kamp mod Rival-botten | Ingen hak, heller ikke når du topper ud. Notér FPS med og uden vinduet åbent | UTESTET |
| A20 | Log ud, og ind igen | Rekorderne og dit valg af spells/bot er gemt | UTESTET |

## B. Spell Battle mellem to spillere (to klienter, samme realm eller forbundne realms)

| # | Gør dette | Det skal ske | Resultat |
|---|---|---|---|
| B1 | Begge: `/sr version` | Begge viser 0.5.1 | UTESTET |
| B2 | A: Duel → **Spell Battle** → Find players ✱ | B står på listen med "v0.5.1" (en 0.4-spiller vises som "needs 0.5.0") | UTESTET |
| B3 | A: Challenge. B: Accept | Begge lobbyer viser "SPELL DUEL - 3:00" og dine 4 spells | UTESTET |
| B4 | Begge: **Change spells** → vælg → Done → **Ready** ✱ | Der står "locked" ud for dine spells. Nedtællingen starter samtidig (±1 s) | UTESTET |
| B5 | Sammenlign NEXT lige efter start ✱ | Samme brikker hos begge (fælles seed) | UTESTET |
| B6 | A kaster Garbage på B ✱ | B ser "INCOMING GARBAGE" og grå rækker ca. 1,5 s senere. **Notér forsinkelsen** | UTESTET |
| B7 | Hold øje med "VS …"-panelet | Modstanderens score opdateres ca. hvert 2. sekund | UTESTET |
| B8 | B går i combat i 10 s | **Begge** spil pauser. A's knap siger "Waiting for rival…". Når B er ude af combat og trykker Resume, kører begge igen | UTESTET |
| B8b | A og B i combat på samme tid (overlappende) | Den der kommer først ud, venter ("Waiting for rival…"). Begge kører igen, når begge har trykket Resume | UTESTET |
| B8c | B trykker P og Resume 5 gange hurtigt | Pausetælleren falder med mindst 3 s pr. pause ("Pause left") | UTESTET |
| B9 | B trykker P og bliver i pause i over 60 s | B: **FORFEIT** ("paused for more than a minute"). A: **WALKOVER** ("Your rival left the duel"). Efter et øjeblik "Confirmed by both PCs." | UTESTET |
| B10 | Spil 3:00 færdigt (begge) ✱ | Samme to tal hos begge (spejlvendt). **VICTORY / DEFEAT** (kun her), "Both games replayed together on your PC" og efter et øjeblik **"Confirmed by both PCs."** | UTESTET |
| B11 | **Rematch** | Ny lobby, Spell Battle igen, og spells vælges igen | UTESTET |
| B12 | Midt i en kamp: B lukker WoW (Alt+F4) | A spiller videre og får **WALKOVER** ("Lost contact with your rival" / "went offline"), ikke VICTORY | UTESTET |
| B12c | B topper ud tidligt og trykker **Leave duel**, mens A spiller videre | B er tilbage i menuen. Når A er færdig, står resultatet i B's chat (VICTORY/DEFEAT), ikke "NO RESULT". B kan ikke starte en ny duel imens ("still being decided") | UTESTET |
| B12d | Midt i en kamp: A får en loading screen (fx portal) | B's spil venter. Bagefter kører begge videre, og resultatet er "Replay-checked" (ikke afvist) | UTESTET |
| B12b | Duel-arket bagefter | "YOUR DUELS (PLAYED OUT, REPLAY-CHECKED)" tæller kun B10-kampe; under det "Forfeits: N won, M lost - Disputed: 0" | UTESTET |
| B13 | Efter hver duel: begge skriver `/sr duel debug` ✱ | Screenshot. Viser beskeder, forsinkelser og resultat | UTESTET |

✱ = tag screenshot.

## C. Challenge Friends (branch `multiplayer`, build 0.6.0, kun efter din godkendelse)

To spillere med 0.6.0, i samme guild **og** som WoW- eller Battle.net-venner. Alt er **UTESTET i WoW**.

| # | Gør dette | Det skal ske | Resultat |
|---|---|---|---|
| C1 | A: `/sr` → kortet **Challenge** ✱ | Arket "CHALLENGE FRIENDS" med fanerne Guild, Friends, Battle.net, Group og Recent. Der står "Press Refresh to ask who has StackRivals". Ingen er "ready" endnu | UTESTET |
| C2 | A: fanen **Guild** → **Refresh** ✱ | B står med en grøn prik og "StackRivals v0.6.0 - ready". Guildmedlemmer uden addon'et står med "no StackRivals answer yet", og deres knap er grå | UTESTET |
| C3 | A: fanen **Friends** → **Refresh** | B er "ready". Offline venner står som "offline" og får ingen besked. Der kommer ingen "No player named…"-linjer i chatten | UTESTET |
| C4 | A: fanen **Battle.net** → **Refresh** ✱ | B er "ready", hvis B spiller samme WoW-version på samme (eller en forbundet) realm. Venner på en anden realm står som "other realm", og venner i en anden WoW-version som "other WoW version" | UTESTET |
| C5 | A: vælg **Spell Battle** → **Challenge** ud for B | B får en popup. Accept → lobby → Pick Spells → Ready → duel | UTESTET |
| C6 | A: skriv B's navn i **OR BY NAME** → Challenge | Det samme som C5 | UTESTET |
| C7 | B sætter A på ignore-listen (`/ignore A`). A: Refresh | B svarer ikke, og A kan ikke udfordre B. B får ingen popup | UTESTET |
| C8 | Efter en duel: fanen **Recent** | Modstanderen står der. Refresh → "ready", hvis modstanderen er online | UTESTET |
| C9 | Forskellige factions på samme realm (hvis muligt) | Notér, om B bliver "ready" | UTESTET |

## D. Quickplay, karakterkort og match-chat (branch `feature/connected`, build 0.6.1, kun efter din godkendelse)

To spillere med 0.6.1 i samme guild. Alt er **UTESTET i WoW**. Previews er simulerede, ikke screenshots.

| # | Gør dette | Det skal ske | Resultat |
|---|---|---|---|
| D1 | A: `/sr` | Menuen viser Classic, Time Trial, Daily Challenge, den røde **QUICKPLAY**-knap, Spell Battle og Guild Duel | UTESTET |
| D2 | A: **QUICKPLAY** → Duel 2:00 → **Search** ✱ | "SEARCHING" med tid og "Looking in: your guild…". "Web players (stackrivals.io): not connected" | UTESTET |
| D3 | B: **QUICKPLAY** → Duel 2:00 → **Search** ✱ | Inden for ca. 20 s: begge får lobbyen "QUICK DUEL - MATCH FOUND". Ingen popup | UTESTET |
| D4 | Kig på kortene | Navn, realm, faction i farve, race/class/level. B's kort hos A siger "unverified" | UTESTET |
| D5 | Chat i lobbyen: tryk **GL**, skriv en linje + Enter | Den anden ser linjen i StackRivals-chatpanelet. **Intet** i WoW's chatvindue | UTESTET |
| D6 | Begge **Ready** → spil → skriv i chatten under kampen ✱ | Brikkerne bevæger sig **ikke**, mens du skriver i chatboksen. Notér, hvad der sker | UTESTET |
| D7 | Efter resultatet: **Rematch** | Den anden får en almindelig popup og skal acceptere | UTESTET |
| D8 | A: Search. B: lad være med at søge i 5 min | A får "NO OPPONENT" med forklaringen | UTESTET |
| D9 | Match igen, men B trykker ikke Ready | Efter ca. 1 min søger A igen. B's søgning stopper ("You didn't press Ready…") | UTESTET |
| D10 | B: **Mute** i chatpanelet. A skriver | B ser intet. A får ingen besked om det | UTESTET |
| D11 | Hvis muligt: Alliance mod Horde (venner på samme realm) | Kun hurtigbeskeder. Notér, om de overhovedet kommer frem | UTESTET |

## E. Konto (branch `feature/connected`, build 0.6.1, kun efter din godkendelse)

Én spiller. Hjemmesiden har endnu ikke "Link WoW character", så kun addon-siden kan testes: at koden accepteres, og at linket forbliver **PENDING**.

| # | Gør dette | Det skal ske | Resultat |
|---|---|---|---|
| E1 | `/sr` → **Account** | "STACKRIVALS ACCOUNT", status NOT LINKED. Ingen felter til e-mail eller adgangskode | UTESTET |
| E2 | Skriv `A7K9-P2XJ` (testkode) → **Link** | Status PENDING og "Not linked yet". En lang SRL1-kode står i boksen | UTESTET |
| E3 | Klik i boksen → Ctrl+C → indsæt i Notesblok ✱ | Hele koden (SRL1. …) kommer med. Notér, om kopiering virker i WoW | UTESTET |
| E4 | Skriv `A7K9-P2XK` (én forkert) → Link | "That link code has a typo" | UTESTET |
| E5 | `/reload` → Account | Stadig PENDING (i 15 min), derefter NOT LINKED med "The link request expired" | UTESTET |
| E6 | Faneblad **Profile** | "Linking is not finished…" (ingen opdigtet profil) | UTESTET |

## F. Battle.net på tværs af realms (build 0.6.1, kun efter din godkendelse)

To spillere, der er **Battle.net-venner** på **forskellige realms, der ikke er forbundne**, i samme WoW-version. Alt er **UTESTET i WoW**.

| # | Gør dette | Det skal ske | Resultat |
|---|---|---|---|
| F1 | A: `/sr` → **Guild Duel** → fanen **Battle.net** → **Refresh** ✱ | B står som "ready" (ikke "other realm") | UTESTET |
| F2 | A: **Challenge** ud for B → B: Accept → begge Ready → spil færdig ✱ | En normal duel med resultatet "Confirmed by both PCs" | UTESTET |
| F3 | Begge: **QUICKPLAY** → Duel 2:00 → Search | Match found inden for ca. 20 s | UTESTET |
| F4 | Chat i lobbyen (også hvis I er Alliance og Horde) | Tekst kommer frem. Intet i WoW's chatvindue | UTESTET |
| F5 | B: `/reload` midt i en duel | Duellen fortsætter eller ender med en ærlig grund. Notér, hvad der sker | UTESTET |

## Efter testen

- Gem `WTF\Account\<KONTO>\SavedVariables\StackRivals.lua` fra **begge** maskiner (der ligger
  `duelDiag` med diagnostik). Ingen kontooplysninger ligger i den fil.
- Læg 0.3.1-backuppen tilbage, hvis 0.5.x ikke skal blive liggende.
- Send screenshots og de to SavedVariables-filer til Claude. Først derefter kan punkterne krydses af.
