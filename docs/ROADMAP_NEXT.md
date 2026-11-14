# StackRivals i WoW: næste generation (roadmap, november 2026)

Svar på oplægget "StackRivals – næste generation af WoW-addon'et" (12 funktioner). Dette er en plan, ikke
kode: der er ingen prototyper, intet merget, intet installeret. Branch `plan/next-generation`, bygget på
`integration/0.9.1`. Hotfix 0.9.0.1 og integrationsbranchen er uændrede.

**Forudsætning for det hele:** ingen af addon'ets multiplayerfunktioner er endnu set virke mellem to
rigtige spillere. Hotfix 0.9.0.1 er kun prøvet solo i Forever. Før den første nye multiplayerfunktion skal
dueller og Loot Duel være bekræftet i en rigtig gruppe (fase 0).

## 1. Hvad addon'et allerede har

Flere af de 12 funktioner findes allerede helt eller delvist. Roadmappen bygger videre på dem.

| Funktion i oplægget | Findes i dag | Hvor |
|---|---|---|
| 1. Loot Duel 2.0 | **Det meste.** Item fra loot-vinduet eller shift-klik, ikon og navn, 2–40 deltagere, samme brikker til alle, live-liste med placering og score, replay-kontrol af de 10 bedste, vinder / TIE / UNVERIFIED, manuel Announce. Addon'et uddeler aldrig loot | `Core/LootDuel.lua`, `UI/LootDuelUI.lua`, `docs/LOOT_DUEL.md` |
| 3. Spectator Mode | **Delvist.** Gruppemedlemmer, der ikke deltager i en Loot Duel, ser live-listen og resultatet. Dueller kan ikke følges af andre | samme |
| 6. Victory-effekter | **Delvist** (0.9.1). Effekter i tre niveauer, skær bag sejr og ny rekord, lyd ved Loot Duel-resultat, "Reduce effects" | `UI/Fx.lua` |
| 7. Weekly Challenges | **Grundlaget.** Daily Challenge med samme seed for alle pr. UTC-dag, og web-challenges via kode | `Core/Main.lua`, `Net/Codes.lua` |
| 10. Cosmetic Showroom | **Grundlaget.** Collection-fanen viser katalog, ejet og udstyret. WoW tegner endnu ingen skins | `UI/CollectionUI.lua` |
| 11. Match History | **Delvist.** De sidste 20 dueller gemmes (modstander, score, resultat, hvordan afgjort). Loot Duel-resultater huskes kun til `/reload` | `Core/DB.lua` (`duels.history`), `LD.history` |
| 5. Ghost Mode | **Data findes.** Det bedste løb pr. mode gemmes som input-log (`bestLog`), men bruges ikke til noget. Seedet gemmes ikke med | `Core/DB.lua` |
| 2, 4, 8, 9, 12 | Nej | – |

Andet, alt nyt kan bygge på: deterministisk engine (samme seed + input = samme resultat, også på
hjemmesiden), replay-kontrol (`Engine/Verify.lua`), guild-liste og venner (`Core/Social.lua`), dueller med
gensidig bekræftelse ("agreed"), og en beskedkø med prioritet og grænser (`Net/Comm.lua`).

## 2. De hårde grænser (gælder alle funktioner)

1. **Beskedbudget.** Blizzard tillader pr. addon-præfiks ca. 10 beskeder i et ryk og derefter 1 pr. sekund,
   delt mellem *alle* kanaler. Addon'et holder sig under (9 og 0,9/s). Alt nyt (spectator, turneringer,
   holdkampe) deler det budget med dueller og Loot Duel. Hver besked er højst 255 tegn, og en sendt besked
   er ingen garanti for, at den kommer frem.
2. **Ingen server.** Alt, der ikke er replay-kontrolleret eller bekræftet af begge PC'er, er en påstand fra
   én PC. Det betyder noget for ranglister (afsnit 3, punkt 4).
3. **Hjemmesiden ejer XP, Shards, rank, seasons og cosmetics.** Addon'et laver ingen egne belønninger.
   Beskyttede cosmetics kræver en VERIFIED og aktuel profil.
4. **Blizzards addon-regler:** gratis, ingen reklamer, ingen betalingslåste funktioner. Desuden bør addon'et
   ikke gøre det let at spille om guld eller items mellem spillere uden for loot-fordeling (indsatser).
5. **Ingen automatik i combat** og intet, der styrer karakteren.

## 3. Vurdering af hver funktion

Skala: værdi for spillerne, hvor meget arbejde, teknisk risiko.

| # | Funktion | Værdi | Arbejde | Risiko | Vurdering |
|---|---|---|---|---|---|
| 1 | Loot Duel 2.0 | Høj | **Lille** (det meste findes) | Lav | Gør det. Det, der mangler, er: et tydeligt **"Godkend resultat"**-trin for raidlederen, før Announce; item-kvalitet som farvet kant; og en **loot-log**, der overlever `/reload` (hvem vandt hvad, hvornår, og om resultatet var kontrolleret) |
| 2 | Guild Tournaments | Høj | Stor | Mellem | Gør det, men **bygget på dueller**, ikke på ny netværkskode: en turnering er en række almindelige dueller, som arrangøren holder styr på. Kun dueller med "agreed" går videre i bracket'en; omstridte kampe spilles om eller afgøres af arrangøren |
| 3 | Spectator Mode | Mellem | Mellem | **Mellem til høj** | For Loot Duel findes den. For dueller: kun i gruppe, og kun ved at genbruge de scorebeskeder, der allerede sendes (én af de to spillere videresender hver 5. sekund). Ikke for guild-kanalen: for mange modtagere, for lidt budget |
| 4 | Guild Leaderboards og Seasons | Mellem | Mellem | **Høj (tillid)** | Kun i en ændret form: en **guild-stige** bygget alene på dueller, som begge PC'er har bekræftet. Selvrapporterede rekorder kan forfalskes af enhver, så de vises kun som "påstået". Navnet "season" bør undgås, fordi hjemmesiden har seasons med XP og rank. Synkronisering til stackrivals.io: se afsnit 6 |
| 5 | Ghost Mode | Mellem til høj | **Lille** | **Lav** (solo) | Gør det tidligt. Data og replay-motor findes. Mangler: gem seedet ved det bedste løb, og afspil det gamle løb tick for tick ved siden af det nye (score foran/bagud). Ingen netværk |
| 6 | Victory-effekter | Mellem | Lille | Lav | Bygger videre på `UI/Fx.lua`: Loot Duel-finale, turneringssejr, perfect clear (kræver de nye `lastClear`-felter, aftalt med web-chatten) |
| 7 | Weekly Challenges | Mellem | Lille | Lav | Samme mekanisme som Daily (seed ud fra ugenummer) plus mål som "Clear 20 lines". Kun lokal markering af gennemført; **ingen Shards eller XP** fra addon'et |
| 8 | Team Battles 2v2 / 3v3 | Høj (sjovt) | Stor | **Høj** | Del op. **Hold-scoreløb** (alle spiller samme seed, holdets samlede score tæller) kan genbruge Loot Duel-motoren og er realistisk. **Ægte holdkamp med garbage mellem spillerne** kræver lockstep mellem 4–6 PC'er inden for beskedbudgettet; det fraråder jeg |
| 9 | Dungeon Break Mode | Mellem | Lille | Lav til mellem | En Loot Duel **uden item** ("Fun race"). Kræver en lille protokoludvidelse (item-feltet er obligatorisk i dag), med versionsnummer, så ældre versioner afviser pænt. Start aldrig i combat (findes allerede) |
| 10 | Cosmetic Showroom | Mellem | Mellem til stor | Lav | Venter på produktionsnøglen og på, at hjemmesiden har skins, der kan tegnes med WoW's egne teksturer. Previews kan laves først; aktivering kun med VERIFIED og aktuel profil |
| 11 | Match History og Replay Viewer | **Høj (tillid)** | Mellem | Lav | Gør det tidligt. Udvid historikken med Loot Duel-resultater og afgørelsesstatus (agreed / disputed / unverified). Replay-viewer: afspil en gemt input-log på brættet. Pas på pladsen i SavedVariables: et 2-min.-løb fylder ca. 8 KB, så kun de seneste/bedste gemmes |
| 12 | Training Academy | Mellem (nye spillere) | Mellem | Lav | Små solo-øvelser med samme engine (fx "10 rotationer", "lav en QUAD"). Godt sammen med onboarding. Kan vente |

### Det, jeg vil udfordre i oplægget

* **Loot Duel 2.0 er mindre, end oplægget antyder.** Kernen er bygget. Den største reelle forbedring er
  raidlederens godkendelse og en loot-log, ikke en ny konkurrence.
* **Spectator foran Match History og Ghost Mode giver mest risiko for mindst gevinst.** Spectator for Loot
  Duel findes allerede. For dueller koster den beskedbudget i netop de kampe, der skal være sikre. Match
  History og Ghost Mode giver værdi med næsten ingen risiko.
* **Guild-ranglister kan ikke gøres troværdige uden en server.** Kun gensidigt bekræftede dueller kan bruges.
* **Ægte 2v2 / 3v3 er det dyreste og mest skrøbelige punkt på listen.** Hold-scoreløb giver det meste af
  det sjove til en brøkdel af risikoen.

## 4. Roadmap

Hver fase har en port: den næste begynder først, når portens krav er opfyldt.

### Fase 0: fundamentet (i gang)

* Hotfix 0.9.0.1 testet med mindst én anden spiller (`HOTFIX_0.9.0.1.md` T2–T5, T7) og udgivet efter GO.
* 0.9.1 med produktionsnøglen, testet i rigtig klient (`TEST_PLAN_0.9.1.md`), udgivet efter GO.
* **Port:** en normal duel og en normal Loot Duel med samme resultat på to rigtige PC'er.

### Rækkefølge (aftalt 14. nov. 2026)

1. Multiplayer-hotfixet (fase 0).
2. **Race My Best (Ghost Mode)** og **Fun Race**. Ghost Mode er lavet som prototype på
   `feature/ghost-mode` (`docs/RACE_MY_BEST.md`).
3. Loot Duel 2.0.
4. Guild Tournaments.

**Fun Race** er en Loot Duel uden item: fem spillere i en dungeon venter på næste boss, én åbner
StackRivals og vælger Fun Race, og alle kæmper om den højeste score uden en loot-beslutning. Det er den
nemmeste måde at få nye spillere til at prøve addon'et. Det kræver en lille, versioneret protokoludvidelse
(item-feltet er obligatorisk i dag), så ældre versioner afviser pænt i stedet for at fejle.

### Fase 1 (1.0): Loot Duel 2.0 + solo-værdi

Lav netværksrisiko. Ingen nye beskedtyper, undtagen det valgfrie "Fun race".

| Del | Indhold | Automatiske tests | Rigtig klient |
|---|---|---|---|
| Loot Duel 2.0 | "Godkend resultat" for lederen før Announce; kvalitetskant på item; loot-log der overlever `/reload` | Godkend kun mulig ved et kontrolleret resultat; DISPUTED / UNVERIFIED kan ikke godkendes; loglængde begrænset; gamle SavedVariables indlæses | 2–5 spillere: samme vinder, lederen godkender, log efter `/reload` |
| Match History | Dueller + Loot Duels, med status (agreed / disputed / unverified) | Status vises rigtigt i alle afgørelsestyper; maks. antal | Efter en duel og en Loot Duel |
| Ghost Mode | Spil mod dit eget bedste løb (samme seed); foran/bagud undervejs | Ghosten afspilles bit for bit som originalen; gamle `bestLog` uden seed giver ingen ghost og ingen fejl | Solo |
| Fun Race (prioriteret) | Loot Duel uden item (Dungeon Break) | Ældre versioner afviser pænt; aldrig i combat; samme vinder på alle PC'er | 2–5 spillere |

**Port:** fase 1 testet med 2–5 rigtige spillere, ingen Lua-fejl, release efter GO.

### Fase 2 (1.1): flere grunde til at spille solo

| Del | Indhold | Tests |
|---|---|---|
| Weekly Challenges | Ugentligt seed + 1–3 mål; kun lokal markering | Samme seed for alle i samme uge (UTC); ingen XP/Shards |
| Replay Viewer | Afspil gemte løb fra Match History | Afspilning = original; pladsgrænse |
| Training Academy | 4–6 korte øvelser | Hver øvelse kan gennemføres; tæller ikke som rekord |
| Victory-effekter | Loot Duel-finale; perfect clear, når `lastClear`-felterne er aftalt med web-chatten | "Reduce effects" respekteres; ingen Lua pr. frame |

### Fase 3 (1.2): guild-oplevelsen

| Del | Indhold | Tests |
|---|---|---|
| Guild Tournaments | 4 / 8 / 16 spillere, knockout; arrangøren styrer bracket'en; kampene er almindelige dueller | Kun "agreed" går videre; en spiller, der forsvinder, taber på walkover efter en frist; arrangøren kan afgøre omstridte kampe; bracket overlever arrangørens `/reload` |
| Duel-spectator i gruppe | Videresendte scorer hver 5. sekund til gruppen | Beskedbudget: målt, aldrig over grænsen; spectator-beskeder har laveste prioritet og kan aldrig fortrænge resultatbeskeder |
| Guild-stige | Kun gensidigt bekræftede dueller | Påstande fra én PC vises som "påstået" og tæller ikke |

**Port:** en rigtig guild-turnering med 4 spillere og en duel-spectator i gruppe.

### Fase 4 (senere): holdspil og cosmetics

* **Hold-scoreløb 2v2 / 3v3** på Loot Duel-motoren.
* **Cosmetic Showroom** med aktivering, når hjemmesiden har skins og produktionsnøglen er i brug.
* **Ægte holdkamp med garbage:** først en teknisk forundersøgelse; ikke på roadmappen før det er vist, at
  lockstep for 4–6 PC'er kan holde sig inden for beskedbudgettet.

## 5. Sikkerhed for de nye funktioner

| Trussel | Hvor | Modtræk |
|---|---|---|
| Falsk vinder | Turnering, stige, holdløb | Kun replay-kontrollerede eller gensidigt bekræftede resultater tæller; ellers DISPUTED / UNVERIFIED, aldrig en vinder |
| Beskedspam | Spectator, turneringer | Laveste prioritet og egen kø-nøgle pr. funktion; svar kun til gruppemedlemmer (samme mønster som hotfix H1) |
| Forfalsket rekord i SavedVariables | Ghost, stige, history | Lokale tal er kun til eget brug; alt, der vises for andre, skal kunne replay-kontrolleres |
| Indsatser om guld | Turneringer | Ingen funktion til indsatser eller præmier i addon'et |
| Beskyttede cosmetics | Showroom | VERIFIED **og** aktuel profil (allerede i 0.9.1) |
| SavedVariables-vækst | History, replays, ghost | Faste grænser pr. liste; ældste fjernes først |

## 6. Til web-chatten (senere, intet haster)

* **Synkronisering af WoW-resultater til stackrivals.io** kan ikke signeres af addon'et (det har ingen
  hemmelig nøgle, og det må det ikke have). Den mulige vej: hjemmesiden afspiller selv input-loggen med sin
  egen engine (samme seed og regler giver samme score). Det beviser, at scoren er opnåelig, ikke hvem der
  spillede. Det skal aftales med web-chatten, før addon'et lover noget.
* `lastClear.rows` og `perfect` (allerede aftalt i princippet) bruges i fase 2.

## 7. Det næste konkrete skridt

1. Fase 0: multiplayer-testen af hotfixet med én anden spiller.
2. Når porten er passeret: fase 1 på en egen branch, med Ghost Mode først (solo, ingen netværk), derefter
   Match History og Loot Duel 2.0.
