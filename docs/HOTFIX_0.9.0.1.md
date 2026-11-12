# Hotfix 0.9.0.1: sikkerhedsrettelser til den offentlige 0.9.0

Branch `hotfix/0.9.0.1`, bygget på den frosne 0.9.0 (`84dbb62`). **Ikke udgivet, ikke installeret, ikke
merget.** 0.9.0 på CurseForge er uændret.

**Bevisgrundlag:** Alle fejl er fundet og genskabt med simulerede klienter (`tests/netsim.lua`: flere
komplette addon-instanser på et simuleret netværk). Ingen af dem er set i en rigtig WoW-klient, og ingen
rettelse er prøvet i en rigtig klient endnu.

## 1. Hvad hotfixet retter

| # | Fejl i 0.9.0 | Rettelse | Fil |
|---|---|---|---|
| H1 | **Kritisk.** Hver `/sr commtest`-besked (ping) fra hvem som helst, også som whisper, udløste et svar med normal prioritet. Med en chat-makro kunne én spiller holde en andens beskedkø (64 pladser) fuld. Så blev den andens resultat aldrig sendt: Loot Duel-vinderen skiftede (41.686 point tabte til 224), og en duelsejr blev til "rival sent no log" | Et ping besvares kun over gruppekanalen, kun fra et gruppemedlem, højst én gang hvert 5. sekund for alle afsendere tilsammen, med lav prioritet og på én køplads | `Core/Report.lua` |
| H2 | Når et løb med en høj påstået score ikke nåede frem, vandt det næstbedste løb, som om alt var i orden | Hvis et løb, der kunne have vundet, ikke kan kontrolleres, nævnes ingen vinder: **UNVERIFIED**, med navnet på den, hvis løb mangler | `Core/LootDuel.lua`, `UI/LootDuelUI.lua` |
| H3 | "Announce" skrev sin egen PC's vinder i gruppechatten, selv når PC'en vidste, at resultatet var omstridt, og påstod altid "Every PC replayed every run" | Et omstridt resultat annonceres som **DISPUTED**. Teksten er nu "Checked by replay on my PC" | `UI/LootDuelUI.lua` |
| H4 | En invitation med Quickplay-mærket blev accepteret uden popup fra enhver, der kendte kampens id. Bagefter kunne Quickplay stå i "searching" uden starttid: Lua-fejl i hver frame, og alle duel- og Loot Duel-timere stod stille til `/reload` | Kun kampens egen modstander. Quickplay kan ikke søge uden starttid | `Core/Duel.lua`, `Core/Quickplay.lua` |
| H5 | Ventetiden på modstanderens replay var 60 sekunder på uret. Et langt, gyldigt replay sendt i en instance (0,8 whispers pr. sekund) tog længere, så den ærlige vinder blev dømt som den, der gav op | Ventetiden tæller fra den sidst modtagne del. Hårdt loft: 60 s + 1,5 s pr. del | `Core/Duel.lua` |
| H6 | Quickplay-svar på en søgning brugte en ny køplads hver gang | Én køplads pr. spiller | `Core/Quickplay.lua` |

Ingen protokolændring: 0.9.0 og 0.9.0.1 kan spille sammen. Ingen ændring i engine, XP, Shards,
SavedVariables-format eller udseende (ud over teksterne UNVERIFIED / DISPUTED).

## 2. Dine to spørgsmål

**Gælder grænsen pr. afsender?** Nej, og det er med vilje. Grænsen er samlet: ét svar pr. 5 sekunder,
uanset hvor mange der sender. En grænse pr. afsender ville give 40 svar ad gangen i en raid på 40. I testen
sender syv gruppemedlemmer ti ping i sekundet hver i 6 sekunder: offeret sender højst 3 svar, og køen er
aldrig over 1.

**Kan et ondsindet gruppemedlem stadig skabe køproblemer?** Ikke via de veje, jeg har fundet. Jeg har
gennemgået alle steder, hvor en modtaget besked får addon'et til at sende noget:

| Vej | Grænse |
|---|---|
| Ping (`CTP`) → svar | Rettet (H1) |
| Invitation → afslag ("busy", "combat", "version") | Fandtes i forvejen: ét svar pr. afsender pr. interval, lav prioritet |
| "Hello" → "Hi" | Samme grænse som ovenfor |
| Quickplay-søgning → svar | Nu én køplads pr. spiller (H6). Gælder kun, mens man selv søger |
| Loot Duel: "send dit løb igen" | Fandtes i forvejen: hver del højst hvert 4. sekund, 40 gensendelser pr. løb |
| Duel: modstanderen beder om en replay-del igen | Én køplads pr. del |

Det, der står tilbage:
* Et gruppemedlem kan stadig forhindre andres `/sr commtest`-svar ved selv at pinge hele tiden (kun testen
  påvirkes, ikke kampe).
* En spiller kan med vilje undlade at sende sit replay efter en høj påstået score. Før hotfixet tabte han
  bare. Nu bliver resultatet UNVERIFIED for alle: han kan altså **ødelægge** en Loot Duel, men ikke
  **vinde** den. Det er den sikre side at fejle til, og navnet på den, hvis løb mangler, står på skærmen.
* Blizzards egen grænse for addon-beskeder gælder stadig. Den kan addon'et ikke ændre.

## 3. Risiko

| Ændring | Risiko | Hvorfor |
|---|---|---|
| H1 ping-svar | Lav | Kun svarvejen for `/sr commtest`. Den normale test er dækket af en test (alle svarer én gang) |
| H2 UNVERIFIED | **Mellem** | Ændrer, hvem der vinder, når et løb mangler: fra "næstbedste vinder" til "ingen bekræftet vinder". Det er meningen, men det er en adfærdsændring, og det giver en ny måde at ødelægge en Loot Duel på (se ovenfor). Bør prøves med rigtige spillere |
| H3 Announce | Lav | Kun tekst |
| H4 Quickplay | Lav | Den normale Quickplay-vej er dækket af en test |
| H5 ventetid | Lav til mellem | En duel, hvor modstanderen virkelig tilbageholder sit replay, slutter senere: op til 60 s + 1,5 s pr. del (ca. 2,5 min. for et meget langt replay) i stedet for 60 s |
| Versionsnummer `0.9.0.1` | Lav | Fire tal i stedet for tre. Addon'ets egne versionstjek og hjemmesidens kodetjek accepterer det (kontrolleret i koden). CurseForge og WoW's addon-liste er ikke prøvet med det |

## 4. Automatiske tests

`tests/test_hotfix.lua`: 15 tests. 8 af dem fejler på den uændrede 0.9.0-kode og består nu.

| Krav | Test |
|---|---|
| Beskedspam | Ping som whisper mod den bedste spiller (Loot Duel) og mod vinderen (duel) |
| Ondsindet gruppemedlem | Ping over gruppekanalen, 10 pr. sekund; syv medlemmer på én gang |
| Manglende replay-dele | Mangler på alle PC'er → UNVERIFIED; mangler for et løb, der ikke kunne vinde → ingen ændring |
| Forsinkede beskeder | 2–6 s forsinkelse, 10 % tab, dubletter → samme vinder overalt |
| Uenige klienter | Én PC mangler det bedste løb → DISPUTED, og Announce nævner ingen vinder |
| Disconnect under resultatudveksling | En spiller går offline 2 s efter løbet → ingen opfundet vinder, lederens og vinderens PC er enige |
| Normal `/sr commtest` | Alle gruppemedlemmer svarer én gang, også anden gang |
| Normal Quickplay og Loot Duel | To søgende spillere matches; en normal Loot Duel giver samme vinder på alle PC'er |
| Langt replay i en instance | Den rigtige vinder vinder, og begge er enige |
| Replay, der aldrig kommer | Kampen slutter ved loftet, som DISPUTED og ikke talt |

CI-resultatet (Lua 5.1) for hele testpakken står i afsnit 7.

## 5. Manuel test i rigtig WoW (kun efter dit GO til installation)

Brug 2–5 spillere. Skriv resultaterne i testloggen for klienten.

| # | Test | Forventet |
|---|---|---|
| T1 | `/sr version` hos alle | `0.9.0.1` |
| T2 | `/sr commtest` i gruppen, to gange med 10 sekunders mellemrum | Alle svarer begge gange |
| T3 | Loot Duel med 2–5 spillere, helt normalt | Samme vinder på alle skærme. "Announce" skriver "... wins ... Checked by replay on my PC." |
| T4 | Under en Loot Duel: én spiller kører denne makro 20 gange hurtigt mod den bedste spiller: `/run C_ChatInfo.SendAddonMessage("StackRivals","1:CTP:t"..math.random(10000,99999),"WHISPER","Navn")` | Resultatet er det samme som uden makroen. Den bedste spiller vinder |
| T5 | Duel mellem to spillere, normalt | Begge ser samme resultat, "agreed" |
| T6 | Duel i en dungeon eller raid, 3:00, hvor den ene holder soft drop nede hele tiden | Resultatet kommer (kan tage op til et par minutter), og den rigtige vinder vinder |
| T7 | Quickplay: to spillere søger samme mode | De matches som før |
| T8 | En spiller, der ikke søger Quickplay, får en almindelig invitation | Popup som før. Ingen kamp starter uden et klik |
| T9 | Loot Duel, hvor den bedste spiller logger ud lige efter sit løb | Enten vinder han (løbet nåede frem), eller der står UNVERIFIED med hans navn. Aldrig en anden vinder uden forklaring |
| T10 | 0.9.0 og 0.9.0.1 i samme gruppe | Dueller og Loot Duel virker mellem de to versioner |
| T11 | `/console scriptErrors 1` under det hele | Ingen Lua-fejl |

## 6. Installation (kun efter dit GO)

Som i `TEST_PLAN_0.9.1.md` del A: luk WoW, tag backup af `Interface\AddOns\StackRivals` og
`WTF\Account\<konto>\SavedVariables\StackRivals.lua`, pak ZIP'en ud over 0.9.0, og sammenlign filerne med
ZIP'en. SavedVariables ændres ikke af hotfixet.

## 7. Build

| Felt | Værdi |
|---|---|
| Version | 0.9.0.1 |
| Kode-commit | `fda4e0e` (branch `hotfix/0.9.0.1`) |
| Bygget på | `84dbb62` = den offentlige 0.9.0. Kontrolleret: den commit bygger en ZIP med SHA-256 `d1d846fe…4686`, den samme som filen på CurseForge |
| ZIP | `StackRivals-0.9.0.1.zip`, 86 filer, samme filliste som 0.9.0 |
| SHA-256 | `4dd7ebafe66e34f1f14772fd711d046b08935b9ab64c419637702fa00a710c17` |
| Bygget to gange | Lokalt og i CI (run 43262085154): samme SHA-256 |
| Automatiske tests | CI, Lua 5.1: 849 bestået, 0 fejl (0.9.0's tests + 15 nye) |
| Ændrede filer i addon-mappen | `Core/Report.lua`, `Core/Duel.lua`, `Core/Quickplay.lua`, `Core/LootDuel.lua`, `UI/LootDuelUI.lua`, `StackRivals.toc` (kun versionsnummeret) |

## 8. GO / NO-GO

**Koden: GO til test.** Rettelserne er små, protokollen er uændret, og alle automatiske tests består.

**Udgivelse: NO-GO, indtil mindst T1–T5, T7 og T10 er prøvet i en rigtig klient med mindst to spillere.**
Hotfixet er aldrig indlæst i WoW. Den fejl, det retter, er også kun set i simulering. Det mindste, der
bør ses i en rigtig klient før udgivelse: addon'et indlæses som 0.9.0.1, en normal duel og en normal Loot
Duel giver samme resultat hos alle, og `/sr commtest` svarer.
