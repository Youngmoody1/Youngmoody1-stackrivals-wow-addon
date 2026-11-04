# Testlog: rigtig WoW Classic Era (1.15.9, interface 11509)

Kun rigtige klienttests og det, der er observeret på den rigtige installation, står her.
Automatiske tests står i CI og `docs/STATUS.md`.

## Kørsler

| Dato | Build | Hvem | Hvad | Resultat |
|---|---|---|---|---|
| 2026-11-04 | 0.3.1 (`release/0.3.1`, `5d57439`) | dig | Smoke-test: indlæsning, `/sr version`, Classic, Blitz, Daily | **OK** (din melding). SavedVariables bekræfter 3 afsluttede spil: Classic 426, Daily 250, Blitz 288; diagnose: klient 1.15.9 build 70576, 3 indlæsninger |
| 2026-11-04 | 0.7.0 dev (`9a68952`) | Claude | Installation i Classic Era (kun filer, intet gameplay) | 69 filer skrevet og læst tilbage: byte-identiske med ZIP (SHA-256 `1c9a8850…0b1d`) og commit. SavedVariables ikke rørt |
| – | 0.7.0 dev | dig | `FIRST_TEST_CLASSIC_ERA.md` B1–B20 | IKKE TESTET |

## Problemer og observationer

| # | Fundet | Hvad | Alvor | Status |
|---|---|---|---|---|
| 1 | Installation | WoW gemte SavedVariables kl. 09:11:56, 14 s før installationen begyndte, så klienten var sandsynligvis åben. Nye addon-filer indlæses først efter en fuld genstart af WoW | proces | Guiden starter med "genstart WoW helt" |
| 2 | Installation | 0.3.1-smoke-testen efterlod et afbrudt Classic-spil (`suspended`). Det er nu bevist med en test, at 0.7.0 fortsætter et sådant spil med præcis samme tilstand som 0.3.1's motor (hash `e2950641`), og at 0.3.1's rekorder inkl. `bestLog` / `bestDate` bevares | sikring | Regressionstests i `tests/test_stress.lua` (syntetiske data, ikke dine) |
| 3 | Gennemgang | Menukortet hedder "Guild Duel", skærmen og dokumenterne "Guild Duels". Bevidst valgt ved omdøbningen (testen låser "Guild Duel") | kosmetisk | Åbent: din beslutning, om kortet skal hedde "Guild Duels" |

Nye fund fra din test tilføjes her med nummer, testpunkt og status (åbent / rettet i commit X med
test Y / afvist med begrundelse).
