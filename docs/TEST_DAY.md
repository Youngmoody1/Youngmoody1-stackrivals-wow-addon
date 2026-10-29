# Testdag – den første rigtige WoW-test (dansk, til ejeren)

StackRivals **0.3.1** er allerede installeret i dine klienter: **Retail**, **Classic Era** og
**Anniversary** (`Interface\AddOns\StackRivals`). 0.2.1 og 0.3.0 er gemt som backup i
`World of Warcraft\StackRivals-backups\`. Du skal ikke installere noget selv.

Vælg **én** klient. Retail eller Classic Era er bedst. Forever findes først fra 5. nov. kl. 00.00.

## 0. Før du logger ind (1 min)

1. Start spillet via Battle.net, og lad det opdatere færdigt.
2. **Luk spillet helt og start det igen**, hvis det allerede kørte. Nye addon-filer indlæses kun ved en fuld genstart.
3. På karaktervalget: **AddOns** (nederst til venstre). Tjek at **StackRivals** er slået til.
   - Står der *Out of date*: sæt flueben i **Load out of date AddOns**.
   - Står StackRivals der slet ikke: se *Hvis addon'et ikke indlæses* nederst.

## 1. Hurtig test – 10 minutter (vigtigst)

Skriv i chatten:

```
/console scriptErrors 1
/sr version
```

Tag et screenshot (**Print Screen**) af hver ✱ og af alt, der ser forkert ud.

| # | Gør dette | Det skal ske |
|---|---|---|
| 1 | `/sr` ✱ | Først "How to play" → klik **Got it** → mode-menuen. Du kan stadig gå med WASD |
| 2 | Klik **Classic** ✱ | 3-2-1, så falder brikker. ←/→, ↑/Z, Space, C virker |
| 3 | Hold ← nede et sekund | Brikken glider jævnt til kanten |
| 4 | Ryd en linje | Blink, "SINGLE/DOUBLE", lyd. Score og Lines stiger |
| 5 | Tryk **P** | Pause. Nu går WASD til din figur. Tryk **P** igen → 2-1 og spillet fortsætter |
| 6 | Tryk **Enter** under spil | Spillet pauser, og chatten åbner |
| 7 | Angrib en mob / træningsdukke ✱ | Spillet pauser med det samme, vinduet forsvinder, du kan kæmpe. **Ingen** "Interface action failed" |
| 8 | Kampen slutter ✱ | Vinduet kommer tilbage på pause. **Resume** virker |
| 9 | Spil **Blitz 2:00** færdig ✱ | "TIME!", score, "NEW BEST". Tryk **Space** efter 1 sekund → nyt spil |
| 10 | Start Classic, placér 5 brikker, skriv `/reload` | `/sr` viser **Continue last run**. Brættet er præcis det samme |

**Stop og send mig det**, hvis der kommer rød fejltekst eller "Interface action failed", eller hvis din figur bliver ved med at løbe.

## 2. Udvidet test – 10 minutter mere (hvis alt ovenfor virkede)

| # | Gør dette | Det skal ske |
|---|---|---|
| 11 | **Daily Blitz** | Kortet viser "new in Xh YYm". Spil et spil, og menuen viser "Today: …" |
| 12 | **Records** i menuen ✱ | Top 5 med datoer og statistik |
| 13 | Settings → bind *Hold* om til **V** | V virker som hold, og bundteksten viser V |
| 14 | Settings → størrelse − og + | Vinduet skalerer. `/sr reset` nulstiller |
| 15 | Settings → lyd fra | Ingen spil-lyde |
| 16 | Træk minimap-ikonet rundt, `/reload` | Ikonet bliver hvor du satte det |
| 17 | Højreklik minimap-ikonet | Settings åbner |
| 18 | Ændr WoW's UI-skala (System → Grafik) | Vinduet passer stadig på skærmen |
| 19 | Spil i en by med mange spillere | Ingen mærkbart lavere FPS |
| 20 | Log helt ud og ind igen | Rekorder, taster og indstillinger er der stadig |

## 3. Vurdér det som spiller (2 minutter, vigtigt)

Skriv kort til mig:
- Føles styringen skarp eller træg? Er ←/→ for hurtig eller for langsom?
- Er brikkerne og tallene nemme at læse?
- Er lydene for høje, for lave eller irriterende?
- Fik du lyst til at prøve en gang til for at slå din rekord?

## 4. Send resultater

Det letteste: sig "færdig", så henter jeg selv dine StackRivals-data og skærmbilleder fra
WoW-mappen. Mappen er allerede delt med denne chat, og jeg læser kun.

Alternativt kan du køre `tools/collect-diagnostics.ps1` fra GitHub-repoet. Det laver en ZIP på dit
skrivebord med **kun** StackRivals' egne data. Kontonavne bliver erstattet, og intet i WoW-mappen
bliver ændret.

## Hvis addon'et ikke indlæses

1. Tjek at stien er `…\_retail_\Interface\AddOns\StackRivals\StackRivals.toc`. Der må ikke være en StackRivals-mappe inde i en anden StackRivals-mappe.
2. Genstart spillet helt (ikke kun `/reload`).
3. Sæt flueben i **Load out of date AddOns**.
4. Kommer der stadig ingen besked ved login, så skriv `/sr version`. Får du "Unknown command", er addon'et ikke indlæst. Tag et screenshot af AddOns-listen og send det.
5. Vil du tilbage til 0.2.1? Backup'en ligger i `World of Warcraft\StackRivals-backups\`. Eller sæt bare StackRivals til *disabled* i AddOns-listen. Intet andet afhænger af den.
