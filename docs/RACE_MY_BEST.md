# Race My Best (Ghost Mode): prototype til 1.0

Branch `feature/ghost-mode` (bygget på `integration/0.9.1`). Prototype: ikke merget, ikke installeret, ikke
uploadet. Hotfix 0.9.0.1 og `integration/0.9.1` er uændrede.

## Hvad det er

Du spiller de samme brikker som dit bedste løb i Classic eller Time Trial, og dit bedste løb spiller med
ved siden af dig, tick for tick.

* **Menuen:** knappen **RACE MY BEST** på Classic- og Time Trial-kortet. Den er grå, når der ikke er et løb
  at køre imod, og tooltip'en siger hvorfor. `/sr best` (Classic) og `/sr best trial` virker også.
* **To slags bedste:** **Official Best** er din normale Classic- eller Time Trial-rekord. **Race Best** er dit
  bedste resultat i Race My Best. De står hver for sig overalt: panelet, resultatet, menuens tooltip og
  Records. **Et ghost-løb ændrer aldrig Official Best** (din beslutning).
* **Under løbet:** et panel under NEXT i samme stil som modstanderens panel i en duel (stålblå = den anden
  side). Overskriften siger, hvad du kører imod: **OFFICIAL BEST** (din rekord) eller **RACE BEST** (et vundet
  ghost-løb). Panelet viser ghostens score lige nu, level og linjer og en "tovtrækning". I SCORE-panelet står
  **AHEAD** (grøn) / **BEHIND** (rød) / **LEVEL** med forskellen.
* **Når ghosten er færdig før dig** (den toppede ud): panelet viser dens **slutscore**, linjen under skifter
  til "final score" i guld, og AHEAD/BEHIND regnes mod slutscoren.
* **Øjeblikkene:** når du går forbi dit bedste løbs tempo, pulserer panelet. Når du passerer dets
  **slutscore**, kommer det store øjeblik én gang: **NEW RACE BEST** (undertekst "PAST YOUR GHOST"), et gyldent
  skær og en lyd. Ordet "record" bruges ikke, fordi det ikke er en officiel rekord.
  "Reduce effects" beholder tekst og lyd og dropper skæret.
* **Resultatet:** "NEW RACE BEST +N" med "Your next ghost. Official best stays 64,302.", "TIED YOUR OFFICIAL
  BEST" eller "OFFICIAL BEST 64,302 (-620)" / "RACE BEST 66,182 (-620)".
* **Records:** Classic- og Time Trial-kortet har en ekstra linje **Race best**. Antal races står i menuens
  tooltip. Nulstilling af rekorder nulstiller også Race My Best.
* **Til og fra:** "–" på panelet skjuler det (løbet fortsætter, SCORE-panelet viser så kun din bedste
  slutscore), og "+" eller `/sr best panel` viser det igen.

## Data (punkt 7: undersøgt før implementeringen)

Det bedste løb i hver mode var allerede gemt som input-log i `records[mode].bestLog`:
`engineVersion;seed;startLevel;ticks;tick,action ...`. Det er alt, en nøjagtig genafspilning kræver. Der er
**ingen ændring i engine, protokol eller replay-formatet**.

| Gemt | Hvor | Grænse |
|---|---|---|
| Dit bedste løb (som før) | `records.classic.bestLog`, `records.blitz.bestLog` | uændret |
| Et vundet ghost-løb (det næste, du kører imod) | `ghosts.classic`, `ghosts.blitz` (ny) | højst ét pr. mode, højst 300.000 tegn (et 2-min.-løb fylder ca. 8 KB) |
| Race Best | `raceRecords.classic`, `raceRecords.blitz` (ny): bedste score, dato, races, sejre | kun tal; affald droppes |
| Panel til/fra | `settings.raceBestPanel` (ny, standard til) | – |
| Et afbrudt løb (`/reload`) | `suspended.ghostId` (ny): hvilket ghost det var imod | 8 hex-tegn |

**Et løb tilbydes kun som ghost, når:** loggen kan læses, den er fra samme engine-version, startlevel er 1,
og en fuld genafspilning giver præcis den score, der er gemt. Ellers er knappen grå med grunden (ingen
replay fra en ældre version, anden engine-version, andre regler, eller scoren passer ikke). Den fulde
kontrol køres én gang pr. ghost, når du trykker på knappen, ikke ved hver menuopdatering.

## Beslutning (taget)

**Ghost-løb ændrer ikke de normale Classic- eller Time Trial-rekorder.** Du kender brikkerne på forhånd, så
det er en anden konkurrence. En vundet ghost-race bliver dit nye Race Best og det løb, du kører imod næste
gang. Testene kontrollerer, at Official Best er uændret efter både tabte og vundne races.

## TIME LEFT 1:39 på resultatbilledet (punkt 4)

Undersøgt: det var **kun simulerede data**. Previewbillederne 30e/30f stoppede løbet efter 20 sekunder med
`finish("time")`, så uret stod på 1:39. Et rigtigt Time Trial-løb slutter først, når tiden er brugt op.
Billederne går nu helt til tidsgrænsen og viser 0:00, og en ny test kører et ghost-løb til tiden løber ud og
kontrollerer "TIME!" og 0:00.

## UI-skala og mindre skærme (punkt 6)

Hele vinduet skaleres som én enhed (`UI:ApplyScale`: 58 % af skærmhøjden ved 100 %, aldrig større end
skærmen). Panelet ligger inde i vinduet i vinduets egne enheder, så det følger med. Testet i mocken ved
1024×768 med 70 % og 140 %, 1366×768 og 2560×1440 med 140 %: vinduet er på skærmen, panelet inde i vinduet, og
alle panelets tekster (også "OFFICIAL BEST", "LV 20 - 999 lines", "1234 lines") passer i deres bredde, med
mindst 4 enheders luft til "–"-knappen. Mocken bruger en tilnærmet skrift, så **det endelige bevis er rigtig
WoW** (G9 nedenfor).

## Afkortet tekst (punkt 5)

* Statuslinjen er 94 bred (før 90) og bruger "LV 12 - 128 lines". Over 999 linjer (lange Classic-løb)
  vises kun "1234 lines".
* "–"-knappen er smallere (12), så "OFFICIAL BEST" har plads.
* "+"-knappen (vis panelet igen) sidder ved SCORE, så den ikke støder ind i "OFFICIAL BEST" under den.
* "no ghost (changed)" er nu "ghost changed".

## Det, prototypen ikke gør

* **Daily Challenge** kan ikke køres som ghost: brikkerne skifter hver dag, og dagens bedste løb gemmes ikke
  som replay i dag.
* Ingen XP, Shards, rank eller webbelønninger. Intet sendes til andre spillere eller til hjemmesiden.
* Ghostens bræt vises ikke, kun dens tal. Et halvgennemsigtigt bræt oven i dit eget ville forstyrre spillet.

## Tests

`tests/test_ghost.lua`, 20 tests (simulerede klienter, ikke en rigtig WoW-klient). CI på Lua 5.1: se
nederst.

| Krav | Test |
|---|---|
| Data findes (punkt 7) | Et rigtigt bedste løb rummer version, seed, startlevel, ticks og input og genafspilles til rekordens score |
| Replay-paritet (2, 10) | Ghosten trin for trin med tilfældige frame-størrelser (1–90 ticks) = `Engine.replay` ved hvert kontrolpunkt og til sidst |
| Gamle data (9) | Ingen replay, anden engine, andre regler, ændret score: aldrig tilbudt, knappen grå med grunden |
| Løbet (1–4) | Samme seed, regler og startlevel; panel og BEHIND; tabt løb ændrer intet |
| Rekord slået (6) | Det store øjeblik præcis én gang, gyldent skær, fanfare; resultat; vinderen er næste ghost; rekorder uændrede; Play again kører mod den nye |
| Reduce effects (6) | Tekst ja, skær nej |
| Til / fra (5) | Skjul, vis, `/sr best panel`; NEXT giver plads; et normalt løb bagefter viser BEST igen |
| `/reload` (10) | Fortsætter mod samme ghost på samme tick; ændret ghost = fortsætter uden og siger det |
| SavedVariables (8, 10) | Gamle filer indlæses; affald og for store logs droppes |
| Classic | Et endeløst løb, der toppede ud, vises som "topped out" |
| Lokal | Ingen beskeder sendt |
| Official vs Race Best (1–3) | Tabt og vundet race: Race Best, races og sejre opdateres; Official Best uændret; panelet skifter fra OFFICIAL BEST til RACE BEST; Records-linjen og tooltip'en viser begge; nulstilling rydder Race My Best |
| NEW RACE BEST (2) | Overskriften er "NEW" / "RACE BEST" / "PAST YOUR GHOST"; resultatet "NEW RACE BEST +N" og "Official best stays …" |
| Ghosten færdig (7) | Ghost, der toppede ud: slutscore i panelet, "final score", ingen afkortning, sammenligning med slutscoren |
| TIME LEFT (4) | Et ghost-løb til tiden: TIME! og 0:00 |
| Skala / skærme (5, 6) | Fire skærm- og skalakombinationer; tekster passer; luft til knappen |
| Gamle filer | Ingen Race Best indlæses fint; affald i den droppes |
| Ydelse | CI (Lua 5.1): fuld kontrol 18,5 ms én gang pr. ghost; ghosten 3,2 µs pr. frame |

Layout-testene kører også de 9 skærmbilleder igennem for overlap og tekst inden for knapper.

## Billeder

`docs/preview/race/`: 9 simulerede billeder (WoW API-mock, **ikke** skærmbilleder fra WoW). Scorerne i
nogle af dem er sat til for at vise en tilstand. Nye: `30h` (ghosten færdig før dig) og `30i` (Records med
Race best).

## Test i rigtig WoW (når du giver GO til at installere en testversion)

| # | Test | Forventet |
|---|---|---|
| G1 | Spil en Time Trial til ny rekord, gå til menuen | RACE MY BEST er aktiv; tooltip viser Official Best |
| G2 | Klik RACE MY BEST | Samme brikker som dit bedste løb; panel med **OFFICIAL BEST**; ingen Lua-fejl |
| G3 | Stå stille i 10 s | BEHIND i rødt, panelets score stiger |
| G4 | Spil, til du er foran | AHEAD i grønt, en kort puls på panelet |
| G5 | Gå forbi ghostens slutscore | **NEW / RACE BEST / PAST YOUR GHOST** én gang, med skær (uden skær med Reduce effects) |
| G6 | Spil løbet færdigt (vundet) | "NEW RACE BEST +N", "Official best stays …"; uret 0:00 |
| G7 | Records | Official Best uændret; **Race best** viser den nye score |
| G8 | Play again | Panelet hedder nu **RACE BEST** og kører mod det vundne løb |
| G9 | Lad ghosten toppe ud før dig (kør mod et løb, der sluttede tidligt) | Slutscore i panelet, "final score" i guld, intet afkortet |
| G10 | `/reload` midt i et løb, Continue | Samme sted, samme ghost |
| G11 | "–" og "+" (ved SCORE) | Panelet forsvinder og kommer igen; løbet fortsætter; SCORE-panelet viser OFFICIAL BEST / RACE BEST |
| G12 | UI Scale: Interface-indstillingen UI Scale lav (fx 0,64) og høj (1,0), og Settings → Size 70 % og 140 % | Vinduet er på skærmen; ingen afkortet tekst i panelet; "OFFICIAL BEST" rører ikke "–" |
| G13 | Mindre opløsning (vindue-tilstand fx 1280×720) | Som G12 |

Tag gerne et skærmbillede af G6, G9 og G12, så vi kan sammenligne med previewbillederne.
