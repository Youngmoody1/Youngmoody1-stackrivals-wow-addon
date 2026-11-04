# Installation og test i rigtig WoW (alle builds)

Dette er den samlede guide. Detaljerede tjeklister ligger i:

* `docs/TESTING_IN_WOW.md` (solo, engelsk);
* `docs/SPELL_BATTLE_TEST.md` (procedure A–F, dansk);
* `docs/LOOT_DUEL.md` (T1–T14: test med 10 rigtige spillere);
* `docs/FIRST_TEST_CLASSIC_ERA.md` (den korte plan til første test i Classic Era, og hvad der
  kræver to rigtige spillere).

**Status lige nu (4/11):** 0.3.1 smoke-test i Classic Era **OK** (din melding), og 0.7.0 dev er installeret i Classic Era (se `docs/TEST_LOG_CLASSIC_ERA.md`). **Ingen 0.7.0-funktion er testet i klienten endnu.** Alt er kun testet automatisk i simulerede
WoW-klienter (lua-tests i GitHub CI). Et punkt er først bestået, når du har krydset det af efter
en rigtig test. Automatiske tests må aldrig skrives som klienttests.

## 1. Hvilket build tester du?

| Build | ZIP | Branch | Indhold | Hvornår |
|---|---|---|---|---|
| **0.3.1** (stabil solo) | `StackRivals-0.3.1.zip` | `release/0.3.1` | Classic, Blitz, Daily | **først** |
| **0.5.1 vs Bot** | `StackRivals-0.5.1-vsbot.zip` | `spellbattle` | + Spell Battle mod bot (dueller slået fra) | når 0.3.1 er godkendt |
| **0.7.0 dev** (installeret i Classic Era) | `StackRivals-0.7.0-lootduel-dev.zip` | `feature/loot-duel` | 0.6.1 (Quickplay, chat, konto, sync, Battle.net) + rettelser + WoW-farver + Loot Duel | testes nu |
| **0.7.1 dev** (nyeste, ikke installeret) | `StackRivals-0.7.1-lootraid-dev.zip` | `feature/loot-duel-raid` | 0.7.0 + Loot Duel for 2–10 på én gang, Invite Party / All / Selected, live-liste, Loot Duel-kort i menuen, genvejsknap | efter din 0.7.0-test og din godkendelse |

0.6.0 og 0.6.1 findes stadig uændret. 0.7.0 indeholder alt fra dem, så du behøver ikke teste dem
hver for sig.

## 2. Klienter og mapper

| Klient | Addon-mappe | Bemærkning |
|---|---|---|
| **Classic Era** (1.15.x) | `World of Warcraft\_classic_era_\Interface\AddOns\` | testes nu |
| **WoW Forever** (1.60.x) | den mappe Battle.net viser: vælg WoW Forever → tandhjul → **Show in Explorer**, derefter `Interface\AddOns\` | når klienten er åben. Mappenavnet er ikke bekræftet, så gæt det ikke |

Hvis der står "Out of date" i AddOns-listen, så sæt flueben i **Load out of date AddOns**, og skriv
klientens interface-nummer ned: `/dump select(4, GetBuildInfo())`.

## 3. Før hver installation: backup (vigtigt)

1. Luk WoW helt.
2. Kopiér `Interface\AddOns\StackRivals` til en backup-mappe, fx `Skrivebord\StackRivals-backup-<dato>\AddOns`.
3. Kopiér `WTF\Account\<KONTO>\SavedVariables\StackRivals.lua` (og `.lua.bak`, hvis den findes)
   til samme backup-mappe.
4. Slet den gamle `Interface\AddOns\StackRivals`, og pak den nye ZIP ud.
   * Resultatet skal være `Interface\AddOns\StackRivals\StackRivals.toc`, ikke
     `StackRivals\StackRivals\…`.
   * Der må kun være **én** StackRivals-mappe.
5. Start WoW helt forfra. `/reload` er ikke nok efter en ny installation.

**Tilbage til et ældre build:** læg backup-filerne tilbage, både mappen **og** `StackRivals.lua`.
Et ældre build forstår ikke de nyere data (konto, sync, Loot Duel) og rydder dem væk, når det
gemmer. Dine rekorder overlever, men læg alligevel backup'en tilbage.

## 4. Testrækkefølge (din prioritering)

Skriv resultatet for hvert punkt: **OK**, **FEJL** (med screenshot) eller **IKKE TESTET**.

| # | Område | Build | Antal spillere | Tjekliste |
|---|---|---|---|---|
| 1 | Addon-indlæsning og `/sr` | alle | 1 | `TESTING_IN_WOW.md` trin 1–5. `/sr version` viser version, engine v1 og interface |
| 2 | Gameplay og spells | 0.3.1, derefter 0.5.1 | 1 | `TESTING_IN_WOW.md` 6–20; `SPELL_BATTLE_TEST.md` procedure A |
| 3 | Quickplay mellem to spillere | 0.7.0 | 2 (samme guild) | `SPELL_BATTLE_TEST.md` procedure D (D1–D10) |
| 4 | Battle.net-kommunikation | 0.7.0 | 2 Battle.net-venner på **forskellige, ikke-forbundne** realms | procedure F (F1–F5) |
| 5 | Kommunikation på tværs af factions | 0.7.0 | Alliance + Horde på samme realm | D11, F4 |
| 6 | Match-chat | 0.7.0 | 2 | D5, D6 (skriv **under** kampen: brikkerne må ikke flytte sig), D10 |
| 7 | Konto-link og kode-import | 0.7.0 | 1 | procedure E (E1–E6). Hjemmesiden mangler Link-siden, så kun PENDING kan testes |
| 8 | SavedVariables | alle | 1 | Log ud og ind: rekorder, indstillinger, konto-status og Sync-resultater er der stadig. Tjek backup og gendannelse fra afsnit 3 |
| 9 | Loot Duel med en gruppe | 0.7.1 | 5, derefter 10 i raid | `LOOT_DUEL.md` T1–T14 |

**Ekstra ting at holde øje med under alle tests:**

* Klassefarverne skal matche raid-UI'et (fx Shaman blå `#0070DD`, Warrior `#C69B6D`). Alliance-kort
  skal være blå og Horde-kort røde.
* Ingen "Interface action failed".
* Ingen beskeder i WoW's chat, som du ikke selv har klikket på (kun "Share" og "Announce" må poste).
* FPS under spil.

## 5. Det skal du sende tilbage

* Screenshots (`<spilmappe>\Screenshots\`) af alle FEJL.
* `WTF\Account\<KONTO>\SavedVariables\StackRivals.lua` efter testen. Filen indeholder addon'ets
  egen diagnose (klient, interface og duel-log).
* Udfyldte tabeller (OK / FEJL / IKKE TESTET) og klientversion (`/sr version`).

## 6. Regler, der gælder for alle tests

* Installér kun dev-builds efter din egen godkendelse. Tag altid backup først.
* Ingen CurseForge-upload og ingen offentlig release, før du siger til.
* Addon'et styrer aldrig din karakter, uddeler aldrig loot og poster aldrig i chat uden dit klik.
