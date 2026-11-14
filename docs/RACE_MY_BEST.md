# Race My Best (Ghost Mode): prototype til 1.0

Branch `feature/ghost-mode` (bygget på `integration/0.9.1`). Prototype: ikke merget, ikke installeret, ikke
uploadet. Hotfix 0.9.0.1 og `integration/0.9.1` er uændrede.

## Hvad det er

Du spiller de samme brikker som dit bedste løb i Classic eller Time Trial, og dit bedste løb spiller med
ved siden af dig, tick for tick.

* **Menuen:** knappen **RACE MY BEST** på Classic- og Time Trial-kortet. Den er grå, når der ikke er et løb
  at køre imod, og tooltip'en siger hvorfor. `/sr best` (Classic) og `/sr best trial` virker også.
* **Under løbet:** et panel under NEXT i samme stil som modstanderens panel i en duel (stålblå = den anden
  side). Det viser dit bedste løbs score lige nu, level og linjer og en "tovtrækning". I SCORE-panelet står
  **AHEAD** (grøn) / **BEHIND** (rød) / **LEVEL** med forskellen.
* **Øjeblikkene:** når du går forbi dit bedste løbs tempo, pulserer panelet. Når du passerer dets
  **slutscore**, kommer det store øjeblik én gang: **NEW BEST / PERSONAL RECORD**, et gyldent skær og en lyd.
  "Reduce effects" beholder tekst og lyd og dropper skæret.
* **Resultatet:** "BEAT YOUR BEST +N", "TIED YOUR BEST" eller "YOUR BEST 64,302 (-620)".
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
| Panel til/fra | `settings.raceBestPanel` (ny, standard til) | – |
| Et afbrudt løb (`/reload`) | `suspended.ghostId` (ny): hvilket ghost det var imod | 8 hex-tegn |

**Et løb tilbydes kun som ghost, når:** loggen kan læses, den er fra samme engine-version, startlevel er 1,
og en fuld genafspilning giver præcis den score, der er gemt. Ellers er knappen grå med grunden (ingen
replay fra en ældre version, anden engine-version, andre regler, eller scoren passer ikke). Den fulde
kontrol køres én gang pr. ghost, når du trykker på knappen, ikke ved hver menuopdatering.

## En beslutning, du skal tage stilling til

**Et ghost-løb ændrer ikke dine normale rekorder.** Du kender brikkerne på forhånd, så en score mod dit
eget bedste løb er en anden konkurrence end en ny Time Trial med nye brikker. En vundet ghost-race bliver i
stedet det løb, du kører imod næste gang. Hvis du hellere vil have, at en vundet race også tæller som ny
rekord, er det en ændring på én linje.

## Det, prototypen ikke gør

* **Daily Challenge** kan ikke køres som ghost: brikkerne skifter hver dag, og dagens bedste løb gemmes ikke
  som replay i dag.
* Ingen XP, Shards, rank eller webbelønninger. Intet sendes til andre spillere eller til hjemmesiden.
* Ghostens bræt vises ikke, kun dens tal. Et halvgennemsigtigt bræt oven i dit eget ville forstyrre spillet.

## Tests

`tests/test_ghost.lua`, 15 tests (simulerede klienter, ikke en rigtig WoW-klient). CI på Lua 5.1: 922 bestået, 0 fejl (`50e906d`).

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
| Ydelse | CI (Lua 5.1): fuld kontrol 18,5 ms én gang pr. ghost; ghosten 3,2 µs pr. frame |

Layout-testene kører også de 7 nye skærmbilleder igennem for overlap.

## Billeder

`docs/preview/race/`: 7 simulerede billeder (WoW API-mock, **ikke** skærmbilleder fra WoW). Scorerne i
nogle af dem er sat til for at vise en tilstand.

## Test i rigtig WoW (når du giver GO til at installere en testversion)

| # | Test | Forventet |
|---|---|---|
| G1 | Spil en Time Trial til ny rekord, gå til menuen | RACE MY BEST er aktiv på Time Trial-kortet |
| G2 | Klik RACE MY BEST | Samme brikker som dit bedste løb; panel under NEXT; ingen Lua-fejl |
| G3 | Stå stille i 10 s | BEHIND i rødt, panelets score stiger |
| G4 | Spil, til du er foran | AHEAD i grønt, en kort puls på panelet |
| G5 | Gå forbi din rekord | NEW BEST én gang, med skær (uden skær med Reduce effects) |
| G6 | `/reload` midt i et løb, Continue | Samme sted, samme ghost |
| G7 | "–" og "+" | Panelet forsvinder og kommer igen; løbet fortsætter |
| G8 | Efter løbet: Records | Den normale rekord er uændret |
