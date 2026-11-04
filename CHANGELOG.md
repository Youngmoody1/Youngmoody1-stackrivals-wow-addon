# Changelog

## 0.9.0 (development) — Ready for the website integration (branch `feature/web-integration`, not released, not installed)

0.8.1 is frozen on `alpha/0.8.1` as the test version. This branch prepares the integration with
stackrivals.io. New formats come from the website: `SRP2` v1 was defined there on 2026-11-04 (below).

- **SRP2 v1 (2026-11-04, defined by stackrivals.io)** — the website answered C3 with its own spec (`docs/WOW_SRP2.md`
  on the website; shared vectors `docs/vectors/srp2_v1.json`, catalog `docs/vectors/cosmetics_catalog_v1.json`):
  - `AccountCodes.parseProfile2` / `profile2`: SRP1's fields 1–18 (same rules) + `shards`, `asOf`, `equipped`
    (skin / frame / victory), `owned` (sorted ids, byte order), `events` (Shard Storm / XP Overdrive, up / live).
    All 16 website parse vectors decode or fail exactly as stated, and every decoded code re-encodes byte for byte.
  - **Import**: an `SRP2` paste goes through the same checks as `SRP1` (character, link, clock, newest wins). SRP1
    stays fully supported; an `SRP3` is refused with "update" (the `newer_format` flow vector now uses SRP3).
  - **Profile view**: `format`, `shards` (the Profile tab's prepared "N SHARDS" now fills from SRP2), `asOf`,
    `equipped`, `owned`, `events`. Saved and sanitised (bounded like the parser).
  - **Display only**: nothing is applied, bought or claimed from an SRP2 code. No local Shards.
- **Signed profiles: SRP1-SIG v1 and SRP2-SIG v1 verified in WoW** (the website's C4 decision):
  - `Net/Ed25519.lua`: Ed25519 verification (RFC 8032) with SHA-512 in **pure Lua 5.1**:
    - no C library;
    - WoW's `bit` library when present, normalised to unsigned 32-bit; byte tables otherwise;
    - TweetNaCl's 16-bit limbs, exact in doubles;
    - one-pass double scalar multiplication;
    - S < L and point checks.
    About 110–150 ms per verification here; the real WoW time is a client test.
  - `Net/SnapshotSig.lua`: the website's rules exactly. These are tested with all 11 `srp1_sig_v1.json` cases
    and all 9 SRP2 signature cases, plus RFC 8032 TEST 1–3:

    | Code | Result |
    |---|---|
    | sig `-` | UNVERIFIED |
    | Unknown kid | UNVERIFIED ("update StackRivals") |
    | Signature invalid, or not kid + 86 characters | **REJECTED** (the code was changed after signing) |
    | Valid | **VERIFIED** |

    The domain strings differ per format, so a signature can't be moved between SRP1 and SRP2.
  - **No production key ships yet.** The website owner creates it and publishes the public half. Until then
    every real code shows UNVERIFIED.
  - The RFC test key `t1` exists only in tests, and a test fails if it is ever shipped.
  - VERIFIED survives a reload only while this version still ships that key, so a retired key's codes
    become UNVERIFIED.
  - `Account.canApplyCosmetic(id)` is the one gate for any future cosmetic drawing: it allows only a VERIFIED
    profile that owns or equips the item. WoW draws no cosmetics yet.
- **Collection tab** (Account > Collection), display only:
  - **Shards**: the website's balance "as of <time>". A `-` code shows NOT AVAILABLE, never 0.
  - **Events**: Shard Storm and XP Overdrive in the code's own wording:
    - "upcoming …";
    - "live until …, as of …";
    - "ended" by this PC's clock.

    Overdrive values are the multiplier × 100 (200 = 2x). Claims happen only on the website; a WoW match
    earns nothing from events.
  - **Cosmetics** from the website's catalog (`Core/CosmeticsCatalog.lua`, generated from
    `cosmetics_catalog_v1.json` by `tools/gen_cosmetics.py`; 32 items):
    - Equipped, then Owned, then Locked, with how each locked item is obtained;
    - purchasable items say "Shop Upcoming";
    - no buy, claim or equip button.
  - Under the list: UNVERIFIED ("names only, nothing applied in WoW") or VERIFIED.
- **Website names (C2)**: stackrivals.io/wow > Link WoW character / Sync status > Export snapshot / Unlink.
  Import result is shown as "(planned)".
- **Result attribution (C5)**: `link` in SR1R is the binding's public `linkId`, a selector, not a single-use
  code. The flow vectors and docs are corrected (`result_link_reused` removed; `duplicate_run` covers
  re-imports).
- **Profile view** (`Account.profileView()`): the Profile tab reads one format-independent view
  instead of the raw snapshot. A later approved format is mapped into the same shape, so the screen
  doesn't change per format. It records where the data came from (`source = "manual"`), when the
  website made it (`asOf`) and when it was pasted (`importedAt`).
- **"Last updated"**: the Profile tab says "Last updated on stackrivals.io: <date> (<how long ago>).
  Imported by hand, may be out of date." After 7 days it says, in gold, "OUT OF DATE: export a new
  snapshot."
- **Shards display prepared, not built**: the view has a `shards` field that `SRP1` never fills.
  The Profile tab shows "Shards N (website balance)" only when an approved format provides it. The
  addon never computes, adds or spends Shards.
- **Account security pass** (third review):
  - **States** on the Account tab:
    - NOT LINKED;
    - PENDING CONFIRMATION;
    - **LINKED - UNVERIFIED** (gold: a pasted snapshot proves nothing about who owns the website
      account);
    - VERIFIED (green, only after a future signature check);
    - OUT OF DATE;
    - **REJECTED** (red note with the reason; the profile you had is unchanged).
  - A second status line says what the state means.
  - `docs/ACCOUNT_SECURITY.md`: threats T1–T15, what the addon checks, what only the website can
    check.
  - `docs/vectors/account_flow_v1.json` (new): 16 import cases generated by running the addon,
    including `forged_but_rechecked` (the check value only catches typos), and 17 checks the website
    must make.
  - `docs/WEB_CLAUDE_HANDOFF.md`: a short technical handoff with questions C1–C10.
- **Honest copying**:
  - WoW can't copy for an addon. **Select** (link request) and **Select code** (results) select the
    whole text.
  - The screen says "Ctrl+C pressed" only after it saw Ctrl+C (or Cmd+C) in that box (`OnKeyDown`,
    where the client has it). It never says "copied" before.
  - Result rows say "code shown" instead of "copied".
  - The copy boxes keep the longest code the format allows (32,768 characters), tested.
- **Profile edge cases**:
  - Shards up to 12 digits fit their slot.
  - The biggest SRP1 numbers fit.
  - 0 XP and missing rank, season, achievements and cosmetics.
  - An expired snapshot shows OUT OF DATE.
  - With more than 5 matches the header says "5 OF 10, MORE ON STACKRIVALS.IO".
  - Cut texts show the whole text in a **tooltip**.
  - Preview captions state the simulated clock. "12 days ago" and "1 h ago" come from two different
    simulated times, not a bug.
- **Profile tab, second pass** (from the review of the first previews):
  - **Bottom strip** under a divider, two fixed lines:
    - "Last update 26 Oct 2026, 08:36 - 12 days ago";
    - "Pasted by hand, so it may be out of date. Nothing unlocks in WoW." When stale, in gold:
      "OUT OF DATE: paste a new snapshot from stackrivals.io."
  - An **UNVERIFIED** tag: no snapshot signature can be checked yet. It turns green VERIFIED only
    when a scheme exists.
  - The panel is 10 units taller, so 5 recent matches and the strip never touch.
  - **Long texts are cut with "..."** instead of colliding: name, rank (own width), level and season
    values, record, achievements and cosmetics, mode and score.
  - **One date format** on every account screen: "26 Oct 2026, 08:36".
  - **"days ago" counts calendar days**: 26 Oct read on 7 Nov is "12 days ago", even when less than
    12 × 24 h have passed. Same day: minutes or hours; the day before: "yesterday".
  - The Shards slot is on the record line ("12,480 SHARDS", gold, website balance). Without Shards
    the record gets the whole line.
- **Account UX**:
  - Steps "1 of 3 / 2 of 3 / 3 of 3" say exactly what to copy and where to paste it.
  - Website menu names live in one table (`Account.WEB`; provisional until the website confirms
    them), used by the Account and Sync tabs.
  - A code pasted in the wrong box says where it belongs:
    - a link request (`SRL1`) belongs on the website;
    - a result (`SR1R`) belongs on Import result;
    - a challenge (`SR1C`) belongs on the Sync tab.
  - The status line stays on one line.
  - The unlink note names the website's Unlink page.
- **XP / Shards proposal for the website**: `docs/WOW_PROGRESSION_SPEC.md`. It covers:
  - sources and what can be replay-verified;
  - suggested eligibility (names only, no numbers);
  - anti-bot and anti-farming;
  - caps;
  - the safe import flow;
  - the decisions the website must make.

  Loot Duel and WoW duels stay without rewards. `INTEGRATION_CHECKLIST.md` lists the missing web
  contracts as C1–C9.
- Previews:
  - `23-account-start` (not linked);
  - `23c2` (worst case: stale, 5 matches, longest texts);
  - `23c3` (Shards, simulated future format).

  The layout test checks every one for overlaps.
- Tests:
  - the profile view and the "Last updated" line;
  - no Shards row from `SRP1`;
  - an `SRP2` paste is refused with "update" and leaves the profile untouched;
  - **Loot Duel runs with no stackrivals.io account and never calls Account or Sync**, so it can't
    feed XP or Shards;
  - calendar-day "days ago" across months and years;
  - long texts cut, not wrapped;
  - every Profile text at or above the type-scale floor;
  - wrong-kind codes;
  - the `Account.WEB` names used on screen.
- Docs:
  - `docs/TEST_LOG_FOREVER.md`: a point-by-point log for the first Forever test;
  - a reception process for web Claude's next report in `docs/INTEGRATION_CHECKLIST.md`;
  - the 0.8.1 freeze record in `docs/RELEASE_PLAN.md`.

## 0.8.1 — Diagnostics for every client, CurseForge preparation (branch `feature/multi-client`, development, not released, not installed)

- **`/sr report`**: one copyable line (`SRDIAG1;…`) with the addon and engine version, the client type, project ID, interface and build, the Hardcore / Season of Discovery / trial flags, which APIs exist, WoW's addon chat lockdown right now and why, the instance type, group channel and size, loot method, message counters and send result codes, the last comm test, saved-data health, and errors StackRivals caught in its message handlers. No character, realm, guild, friend or chat data; nothing is sent anywhere. `tools/diag_report.py` turns it into a readable table and flags the usual causes. So players on clients we don't run can send us everything we need.
- **`/sr commtest`** (party / raid): one ping on the group channel with StackRivals' registered prefix; every other StackRivals in the group answers on the same channel, and the chat line lists who answered and how fast. That proves delivery, not just "the send call returned OK". It says when WoW reported a lockdown. Once per 15 s; each PC answers each ping once. Protocol: `CTP`, `CTA` (older clients ignore them).
- `docs/FOREVER.md` F1–F6 now use `/sr commtest` + `/sr report`. The 0.8.0 one-liner used an unregistered prefix and counted a send result as delivery, which proves nothing.
- Release preparation: `docs/RELEASE_PLAN.md` (Alpha / Beta / Release, GO / NO-GO per client, readiness per client), `docs/TESTERS.md` (external testers, script, report template), `docs/TROUBLESHOOTING.md` (install and fixes per client), `docs/CURSEFORGE.md` (project page, flavor tagging, upload checklist), `tools/curseforge_upload.py` (dry run by default; uploads only with an exact GO sentence, a token and a project id, and always as "release manually").
- Test profiles now include each client's Battle.net game-data API. Tests: report contents and privacy on every client profile, comm test delivery on Forever and Classic Era, comm test during a lockdown.

## 0.8.0 — One addon for every official WoW client (branch `feature/multi-client`, development, not released, not installed)

- **Client layer** (`Core/Client.lua`): the client type comes from `WOW_PROJECT_ID` (the interface number only when that is missing), with names for Forever (18, `WOW_PROJECT_CAMELOT`, a Mainline-family client: not Classic Era), Retail (1), Classic Era (2, with Hardcore and Season of Discovery detected from the realm rules), TBC Anniversary (5), Wrath / Titan Reforged (11), Cataclysm (14), Mists Classic (19); an unknown future client loads and is named "unknown". Feature checks for addon messages, Battle.net game data, the chat-lockdown and restriction APIs, the loot method, secret values, item info.
- **Addon chat lockdown** (Retail / Forever: boss encounter, Mythic+, PvP match): every message is held, not lost and not counted as a failed try, and goes out when WoW allows it again (also on result 11, `AddOnMessageLockdown`). Loot Duel can't be created or started during it and says why (a whole locked zone is told apart, if the client reports it); during a race every timer waits, your run goes on, the live list says "held by WoW". Never worked around.
- **Trial / Veteran accounts** (no addon messages on Forever and modern clients): Loot Duel says so instead of failing silently.
- **TOC**: `## Interface: 16001, 11509, 120105, 20506, 50504, 38002`, exactly the live clients in `tools/clients.json` (Cataclysm Classic 40402 and Wrath Classic 30405 removed: those clients no longer exist); one universal TOC and one ZIP for every client (see `docs/COMPATIBILITY.md`). The validator checks the list against `tools/clients.json`.
- `/sr version` and the diagnostics in SavedVariables name the client (e.g. "WoW Forever 1.60.1 (16001)").
- Tests: `tests/clients.lua` models 9 client profiles from the documentation (what each has and lacks); `tests/test_clients.lua` loads the whole addon on each, plays every solo mode, opens every screen, reloads saved data, reads the loot method, checks lockdown and trial handling, and runs Loot Duel between simulated clients of 5 client types (a 5-player dungeon party; on Forever / Retail a boss pulled mid-race). Mock tests, not client tests.

## 0.7.3 — Loot Duel QA after the 0.7.2 review (branch `feature/loot-duel-raid`, development, not released, not installed)

- **Checking goes on until there is a valid winner**: a forged claim is rejected at once and the next moves up, as often as needed; if a top log never arrives, every remaining claim is checked in one more 40 s round (0.7.2: 10 at a time, twice). If nothing survives: NO WINNER, never an invented one. Tested with 12 and 25 forged top claims among 40.
- **Fast start on a bad network**: the full list and go follow the one-message versions right away (5% loss, 2.5 s latency, 40 players: 52.8 s → 9.0 s). Group messages: burst 8, 0.9/s (was 4, 0.5/s), and every message WoW counts also goes through one shared bucket of 9, +0.9/s (WoW: 10, +1/s). Shares are repeated after 2.5 s. Claims jump the queue; the leader's go repeats stop once every player has been heard.
- **Runs end together**: go messages carry their age (seconds since the leader's go, stamped when the message leaves the queue); a player whose go came late plays the rest of the time.
- **Asking for missing pieces** (`LDK`): a PC missing a claim or part of a needed log asks once (others wait for that answer); the player resends just that (rate-limited).
- Protocol: offer kind `LDJ` (0.7.2 dev `LDH`), `LDG` / `LDW` carry `<age>`, new `LDK`. `/sr` version 0.7.3; Loot Duel needs 0.7.3 on every PC.
- Tests: 12 and 25 forged claims, a late go, start/lateness measured for every size.

## 0.7.2 — Loot Duel for up to 40 at once, results and fixes (branch `feature/loot-duel-raid`, development, not released, not installed)

- **2–40 players in one Loot Duel, all at once** (was 2–10): no heats, no 1v1 rounds. Invite All works for a full raid of 40 (confirmed with a second click), All / None tick or clear the list, Invite Selected takes 2–40. Nobody is entered automatically.
- **Start in 2 leader messages at any size**: over 10 players the fixed list (`LDS`) and the go (`LDG`) are one message each, built on every PC from the joins and seed shares it already heard and checked against the leader's hashes; the full list / go (`LDQ` / `LDW`) follow only on repeats, for whoever missed a message. Repeats wait until the previous one has left the queue. 40 players: every run started 1.0 s after Start in the simulation (0.7.1's way: 10.2 s). The offer kind is `LDH` (0.7.1 dev `LDF`), so dev builds never mix.
- **Verification at 40 without 40 × 40**: over 10 players only the best 10 claims (+ ties) send their log, once the claims are known, and every PC replays only those; a forged or missing top log is out and the next claim moves up; the rest show as NOT CHECKED and can't win. Replays run one per frame and never during your own run; logs are freed after the check. A player who goes offline without a claim is out at once (nobody waits for the deadline); one who goes offline before revealing cancels the start at once (no re-roll).
- **Result colours with icons**: WINNER green (trophy), LOST red (⊗), PASSED red (⊖), TIE gold (=), playing blue (▶), topped out / finished (⚑), NOT CHECKED / NO RESULT / REPLAY FAILED / disconnected amber (?, ⚠) and never shown as a defeat. Names keep their class colour.
- **CONGRATULATIONS!** on every participant's PC once every needed replay is checked: "[Name] wins the Loot Duel!", score, "#1 of n", "highest replay-checked score", with the item box above; a short glow and pop, once. A tie shows **TIE!** and "Roll off with /roll (the agreed tiebreak). No winner is invented." A local chat line, never group chat; Announce stays a manual click by the leader.
- **Live list for 40**: 10 rows of 30 px, mouse-wheel scrolling through all players, your own row pinned when out of view, status icons, "provisional until the best runs are replayed", redrawn at most 4 times a second. Live scores every 4 / 5 / 6 s by group size. All results can be paged after the race (9 per page under the final header).
- **Invite popup**: shorter text with room above the countdown bar.
- **Spell Battle red box** (seen in the real Classic Era client). Two candidates were found and both are fixed, each with a regression test:
  - (a) Every phase change (pause, resume, countdown) let the duel code show the 5th NEXT piece again and stretch the NEXT panel, so that piece was drawn over the bot's mini board. An I piece is red, so it looked like a red bar or box. It is visible in our own preview since 0.5; we didn't catch it until now.
  - (b) The Bomb target marker was a red-outlined frame above the board. It is now a faint patch under the pieces, hidden without mana.
- **Guild Duels** naming (from 0.7.0's branch) is in this build.
- Tests: `tests/test_loot40.lua` (13: 2, 5, 10, 15, 20, 25, 40 players with message counts, peak traffic, replays, memory; 40 on a bad network with 5 at 5 fps; 3 disconnects; a forged top claim; seed manipulation; a leaver in the lobby; a member who missed messages). Previews for 5-man, 10 / 20 / 40 raids, winner / loser / passed, CONGRATULATIONS, TIE and the 40-player live board. See `docs/LOOT_DUEL.md`.

## 0.7.1 — Loot Duel for dungeons and raids (branch `feature/loot-duel-raid`, development, not released, not installed)

- **2–10 players in one Loot Duel, all at once** (was 2–8): one race on the same pieces, no 1v1 rounds. Works in a party of 5 and in raids of up to 40 (the leader picks up to 10).
- **Start in 2 messages**: players are named by their place in the invite list, so the fixed list (`LDQ`) and the go with every seed share (`LDW`) are one message each (0.7.0 dev: up to 10 messages, up to 31 s for 10 players in the simulation; now under 1 s simulated). Start messages go ahead of queued repeats; the offer is repeated only while someone hasn't answered. The offer kind is now `LDF`, so a 0.7.0 dev client never gets stuck half-way. Commit–reveal, replay checks and every fairness rule are unchanged.
- **Inviting**: Invite Party (one click), Invite All (raids up to 10 online, confirmed with a second click), Invite Selected (tick 2–10). The list shows level, class, raid group and StackRivals status (one hidden group check when the leader opens the lobby); the tooltip adds the faction. Nobody is entered automatically; eligibility is never guessed from the class. **From loot** picks an item from the open loot window (read only).
- **Live list beside the window** for up to 10 players: class colours, your row marked, playing / topped out / finished / no signal / disconnected / checked, provisional until replayed. Results that don't count are listed apart under NOT COUNTED.
- **Main menu**: Classic, Time Trial, **LOOT DUEL** (gold card with an original gem icon, "Compete for raid loot", "Create Loot Duel"), Quickplay, Spell Battle, Guild Duels. **Daily Challenge** moved to the button row (same mode, seed and records; details in its tooltip).
- **Loot Duel quick button** near the group frames: StackRivals' own button (never touches Blizzard's frames), shown in a party or raid, hidden in combat, opens the lobby and sends nothing; Shift-drag moves it, right-click hides it, Settings / `/sr lootbutton [reset]` bring it back. `/sr loot` opens the lobby.
- Fixed before delivery (found by CI on Lua 5.1): a player who lost part of the invite list on a bad network couldn't read the compact start list, which cancelled the whole race; the invite list is now sent again with the start list. Regression test plus 8 bad networks.
- Tests: `tests/test_lootraid.lua` (23: 2–10 players in groups of 5–40, Invite Party / All, leaders and assistants, disconnect, bad network, low FPS, ties, forged and lost results, live board, loot window, menu, quick button). See `docs/LOOT_DUEL.md`.

## 0.7.0 — WoW colours, Loot Duel, 0.6.1 review (branch `feature/loot-duel`, development, not released)

- **WoW's own class colours** everywhere a class is known: lobby cards, Quick Duel "your card", Guild Duels lists (class from the guild roster, friends and Battle.net lists), match chat (the rival's name), the live rival panel and the result. Taken from the client (`C_ClassColor.GetClassColor`, else `RAID_CLASS_COLORS`), with warcraft.wiki.gg's values as fallback (the 9 Classic classes plus Death Knight, Monk, Demon Hunter and Evoker, used only when a client reports them). Item quality colours the same way.
- **Faction themes**: Alliance cards blue, Horde cards red (fill, border, edge, label), dark enough that every class colour reads at 3:1 or better (tested). Your own card shows your real character portrait (`SetPortraitTexture`); the rival's shows the class icon. No invented race colours.
- Profile tab without a profile is compact, with a "Link account" button.
- **Loot Duel** (menu → Loot Duel): the leader, an assistant or the master looter picks an item (shift-click, link or ID; shown in its quality colour), 1:00 or 2:00, and 2–8 group members. Everyone must click **Join** (Pass = /roll instead; no answer = not in). The same pieces for everyone (a seed from every player's nonce), no spells, a live leaderboard. **Every PC replays every run**; replay-checked standings by score, then lines; a tie at the top stays a tie (roll off); a missing or failed run is out, and nobody wins by default. **Announce** posts one line only when clicked. Never ranked, never on the website, no gold or bets, and **no loot API is called** (the loot master hands out the item). Peer-checked, which is said on screen. See `docs/LOOT_DUEL.md`.
- **Loot Duel hardening** after an independent review (8 problems, all fixed with tests): real commit–reveal (64-bit commitments; every PC checks the list; a missing share cancels; a left-out player is told), invites expire after 80 s, the last finisher's PC finishes at once, real-time stepping (frame rate can't slow a run), a running Loot Duel is busy for duels / Quickplay / solo starts, the replay uses the duel and web checks (`Engine/Verify.lua`), a reloading leader can re-offer, and a 15 s pause budget. Also: early results are kept, longer grace for slow logs, `INSTANCE_CHAT`, and safe announce length.
- **Review of 0.6.1** (independent): 6 confirmed problems fixed (chat colour-code injection through line wrapping, a web challenge after /reload, Quickplay searching during a normal duel, Forever reported as Classic, "Share my card" leaking the record, Sync paging) plus 6 plausible ones; each has a regression test (`tests/test_review.lua`). See `docs/STATUS.md`.
- **Final polish** (no new features): invite popups no longer hide their text (a bug since 0.4, now caught by a layout check); Loot Duel lobby is compact, shows joined / invited / declined / ready, "Start: needs 2", "Invite expired", a question-mark icon until the item has loaded, one-line item names, and "winning doesn't hand out the item" everywhere; large raids get a paged list and the heats advice (max 8, nobody entered without a click); card names in class colours with a fuller tooltip; disabled buttons look disabled and picked segments stay visible. `docs/FIRST_TEST_CLASSIC_ERA.md`: a short first test plan and what still needs two real players.
- **Naming**: the menu card is now "Guild Duels", like the screen title (text only; mode ids, protocol and saved data unchanged). After the installed Classic Era test build `9a68952`.
- Docs: `docs/STATUS.md` (every feature's real status), `docs/WEB_HANDOFF.md` (the one handoff file for the website, with the prompt for web Claude), `docs/INSTALL_AND_TEST.md` (one install and real-client test guide for 0.3.1, 0.5.1 and 0.7.0, Classic Era and Forever).

## 0.6.1 — Connected multiplayer (branch `feature/connected`, development, not released)

- **QUICKPLAY** (Quick Duel): a big button on the menu. Pick Duel 2:00 or Spell Duel 3:00 → Search → match found → ready check (the duel lobby) → countdown → match → result → rematch. It finds only players who are searching too and that WoW lets the addon reach (guild, party / raid, friends and Battle.net friends whose StackRivals answered, recent rivals). There is no global or fake queue. Cancel, 5-minute timeout, fall-through (back to searching, the no-show rival is skipped for 2 min), lobby cancel. The stackrivals.io adapter exists and honestly reports "not connected".
- **Character cards** in the lobby: name, realm, faction (colour + emblem), race, class, level, duel record. Yours comes from WoW's API; the rival's is self-reported by their addon and marked "unverified". "Share my card" can switch it off. StackRivals rank / level shows Unknown until an account can be linked.
- **Match chat** beside the window during a duel: text + Send, quick messages GL / GG / WP / Rematch?, Mute (remembered), Chat on/off, fold-away tab. Both must have chat on. Free text only within one faction (quick messages across factions). Rate-limited, escaped, never posted to any WoW channel.
- **WoW-style mode names** (display only): Time Trial (was Blitz 2:00), Daily Challenge (was Daily Blitz), Duel 2:00 / Duel 3:00, Spell Duel, Quick Duel, Guild Duels (was Challenge Friends). Classic and Spell Battle (vs Bot) keep their names. Mode ids, rulesets, protocol, SR1 / SR2 and saved data are unchanged; `/sr trial` and `/sr quickplay` added.
- **Account** (menu → Account): link this character to an existing stackrivals.io account with a one-time code. Type the web code → PENDING (a typed code proves nothing) → copy the link request (SRL1) to the website → paste the website's snapshot (SRP1) → LINKED. States NOT LINKED / PENDING / LINKED / NOT SYNCED (older than 7 days), last synced, Unlink (two clicks). **Profile** tab: name, rank, level + XP, season, W/L/D, achievements, cosmetics, last 5 matches, all display only from the website's snapshot. Newer snapshots replace older ones (no rollback, no duplicates); wrong character / link / expired / future / manipulated codes are refused with clear errors. No password, e-mail or token is ever asked for or stored. Formats DRAFT v1 (`docs/ACCOUNT_SYNC_HANDOFF.md` with vectors, the website's to-do list and a prompt for web Claude). Manual copy / paste sync, not live sync. Companion app: research only.
- **Sync** (Account → Sync): paste an SR1 challenge code from stackrivals.io and play exactly that challenge (never a local record; Play again repeats it); copy SR1 result codes for the last 10 challenges and today's best Daily Challenge run, for the website to replay. The SR1 `link` field carries the character's linkId when linked. Manual copy / paste, said on screen.
- **Shared data contract v1 (DRAFT)**: `tools/contract/types.ts` (PlayerRef, AccountRef, Platform, MatchId, Ruleset, GameMode, EngineVersion, Seed, InputLog, SpellEvents, MatchResult, MatchVerification, ProfileSnapshot and the Quickplay / chat types), the TypeScript reference for the account codes (`tools/contract/account.ts`), shared vectors `docs/vectors/account_v1.json` (Lua-made, 84/84 with the TypeScript reference), `docs/STACKRIVALS_WEB_INTEGRATION.md` and `docs/WEB_ADDON_INTEGRATION_HANDOFF.md` with the prompt for web Claude.
- **Battle.net transport**: Battle.net friends on realms a whisper can't reach can be found, challenged, matched by Quickplay and chatted with, over `C_BattleNet.SendGameData` (or `BNSendGameData`) / `BN_CHAT_MSG_ADDON`, documented APIs only. Same message queue, limits and duel rules. Temporary game account IDs are kept in memory only (never saved, shown or used as identity); messages from anyone who isn't a current Battle.net friend on WoW are dropped. Text chat across factions only over Battle.net (as Battle.net whispers allow). Older clients without the API still show "other realm". Simulated only.
- Protocol additions `QS`, `PRF`, `CH`, `QM` and the `INV` flag `q`: ignored by 0.6.0 and older, which still duel normally.
- Handoff for the web project: `docs/WOW_QUICKPLAY_HANDOFF.md`. Includes everything from 0.6.0 and 0.5.1.
- All SIMULATED: nothing of 0.6.1 has run in a real WoW client yet.

## 0.6.0 — Challenge Friends (branch `multiplayer`, development, not released)

- **Challenge** card on the menu opens **Challenge Friends**: pick Blitz 2:00, 3:00 or Spell Battle, then a list — Guild, WoW Friends, Battle.net friends on WoW, Group, Recent rivals — or type a name. Uses the 0.5 duel protocol unchanged.
- A player is "ready" only after their own StackRivals answered; nothing is sent until you press Refresh (each player asked at most once a minute, max 20 per click; guild / group: one broadcast). Invites only by your click. Ignored players are never listed, asked, answered or allowed to pop up an invite.
- Battle.net friends are challengeable when they play the same WoW version on your realm or a connected one; others are listed with the reason ("other realm", "other WoW version"). A Battle.net transport for other realms is planned, not built (`docs/CHALLENGE_FRIENDS.md`). Game account IDs are never stored.
- Includes everything from 0.5.1.

## 0.5.1 — vs Bot survival rule (branch `spellbattle`, not released)

- **Spell Battle vs Bot follows the web's new rule** (stackrivals.io `ef71158`, checked at `8ddaad7`): whoever tops out first loses, whatever the score. The bot topping out while you play is a VICTORY at once; your top-out is a DEFEAT at once and the bot stops there (shown as the server shows it); the same tick or 3:00 → higher score. Ported line by line, with fixtures from the web's real code (every rule case + 40 full matches at all 5 levels) and live matches checked against the server's result at all 5 levels.
- Guild duels unchanged (the web keeps "higher score wins" for 1v1).
- Saved W/L/D now count under the new rule; 0.5.0 results kept apart (`statsV1`), best scores kept.
- Pick Spells and the result screen say the rule ("First to top out loses. At 3:00 the higher score wins."); "beat N to win" and "the bot is finishing its run" are gone.

## 0.5.0 — Spell Battle preview (branch `spellbattle`, not released)

- **Spell Battle** from stackrivals.io Play 2.0 (web `48fdf46`): the same 9 spells (Bomb, Line
  Blast, Freeze, Swap, Clear Board on your board; Garbage, Speed Up, Blackout, Scramble on your
  rival's), mana from line clears, 3 s cooldown, spells land 1.5 s after the cast, 2 + 2 loadout.
  StackRivals spells on StackRivals boards only: nothing touches WoW abilities or gameplay.
- **Spell Battle vs Bot**: the web's bot at 5 levels (same placement AI, same casting rules, same
  tuning versions), 3:00. The match ends the moment it's decided (bot topped out while you lead:
  Victory at once, no more input or casts); behind, you play on ("beat N to win"); after your
  top-out the bot plays on to 3:00 like on the web (spread over a few frames). Local W/L/D per
  level. /reload restores a match exactly.
- **Pick Spells** sheet (the web's icons), spell tiles with keys, mana progress and cooldown,
  bomb target on your board, FROZEN / SPEED UP / BLACKOUT chips, hit flashes, the rival's live
  mini board and mana, Victory / Defeat. Spell keys Q / E / R / F (web) and 1-4, rebindable
  ("Spells 1-4"), only read during a live Spell Battle.
- **Spell Battle duels** with guild / group members (ruleset `s180`, 0.5+ on both sides): spells
  chosen in the lobby and locked at Ready, casts sent at once (SP, repeated), the result = both
  logs replayed together on both PCs (the web's `verifySpellMatch`), peer-checked. Forged spells,
  impossible casts, a changed loadout are caught; lag-only differences are not held against anyone.
  Score-race duels are unchanged and still work with 0.4 clients.
- Menu: a VERSUS row with Spell Battle and Duel; Settings: spell keys.
- Parity: `tools/parity/gen-spell-fixtures.ts` generates fixtures from the web's real code;
  `check_web.sh` runs them. Two web findings reported in `docs/WEB_SPELL_REPORT.md` (final tick,
  input after an incoming top-out); the addon follows the web server's verification.
- Independent review applied: in Spell Battle duels each player's client records where the
  rival's spells actually landed and sends it with the log; the replay lands spells exactly there,
  so a replay is always the player's live game (lag, pauses, withheld sends can't change it).
  Forged, unpaid and ignored spells are caught (tests for each). At most 4 inputs per tick (also
  classic), so a frame hitch never looks "inhuman". A vs Bot result is never lost when the window
  closes during the bot's finish. Fewer allocations per frame in the spell HUD.
- Quality pass:
  - **Duel fairness (0.5 on both sides).** A pause (combat, chat, Esc, loading) pauses both runs, and both resume together. Each player has a 60 s pause budget per duel; past it the duel is forfeited, never voided. A clock check catches a client that pauses silently. A rival who never sends their log, while their own claim is lower, loses (`rival_no_log`).
  - **Results.** Both PCs confirm the result (`VER`); a disagreement is "disputed" and not counted. A spell held back more than 8 s is caught (`late_landing`).
  - **Spell edge cases.** 15 scripted scenarios, compared with the web step by step.
  - **Web bugs.** The two web live-loop findings are reproducible with only the web's code (`tools/parity/web-live-loop-repro.ts`).
  - **SR1** never carries a Spell Battle log.
  - **Spell HUD.** Bigger mana value and taller bar; cost on a plate; cooldown seconds on the tiles; castable spells get a 2-unit edge; an incoming-spell chip and a bar beside the board; your spells flash red, the rival's steel.
  - **Docs.** What peer-checking proves and doesn't; test procedures A and B (`docs/SPELL_BATTLE_TEST.md`).
- Hardening (no new features):
  - **Result classes.** Every duel result has a basis: replay, rejected, forfeit, lost contact, or no result. Only a played-out, replay-checked duel is a VICTORY / DEFEAT and counts as won / lost; the rest are WALKOVER / FORFEIT and counted apart ("Forfeits: N won, M lost"). The verdict exchange carries the basis and compares scores only when both PCs replayed.
  - **Withheld log.** A rival who keeps talking but never sends the log forfeits (a WALKOVER, not a verified win); a rival who goes silent after a high claim gives no result for both.
  - **Pauses.** Every pause costs at least 3 s of the budget; a rival that stays paused past it is no longer waited for (forfeit); a lost resume message no longer stalls the waiting player (the score heartbeat shows the clock moving); the rival's pause is measured after your own run too.
  - **Clock check** on the pauses both PCs actually saw (no blanket 60 s): catches hidden pauses and a slowed-down game. Duels now step the game in real time at very low FPS, so a slow PC is never slowed down or rejected.
  - **Verdicts** are awaited while the rival still plays (e.g. after your forfeit), so both PCs end up agreed or disputed.
  - **Spell HUD.** One message lane under the board for spell toasts and the status line (INCOMING, FROZEN, SPEED UP, BLACKOUT): nothing spell-related covers the falling piece. Spell tiles are taller, with key and cost under the icon.
  - **Test builds.** `FLAVOR=vsbot` builds Spell Battle vs Bot with guild duels switched off; CI builds and keeps both builds.
  - **SR2 draft** (`docs/SR2_DRAFT.md`), nothing built; the two web bugs are listed as open dependencies.
  - **Independent review, fixed:** fake micro-pauses no longer buy clock allowance (the rival's PC charges the 3 s minimum too, budget enforced at all times); loading screens are measured from their start; a hang during play is announced as a pause; your pauses cost nothing after the rival left; "Leave duel" after your run keeps deciding (leaving never voids a loss), and /reload sends no verdict (no dispute); 0.5 clients announce themselves so score races get the clock check; verdicts carry an ack; "ready" repeats while waiting.
- Tests: 121 new (82 parity + rules + scenarios, 15 vs Bot in the WoW mock, 24 two-client duels, plus
  updated duel tests for the new pause and confirmation rules). All earlier tests and the 77 SR1 vectors pass.

## 0.4.0 — multiplayer preview (branch `multiplayer`, not released)

- **Duels**: challenge a guild or group member to a 1v1 score race on a shared seed — Blitz 2:00,
  or 3:00 with the web's 1v1 rules. Find players (one guild/group broadcast, answers by whisper),
  invite popup (works with the window closed), Accept / Decline, lobby with Ready, synced
  countdown, live rival score and lead, result with Rematch, `/sr duel Name [3]`, `/sr leave`.
- Seed made from both players' random nonces, so neither picks the pieces alone.
- Peer check: at the end each addon replays the rival's input log with the engine (port of the
  web's `verifyLog`): inflated scores, wrong seeds, over-time logs and inhuman input are caught.
  Results are labelled "peer-checked", never "verified".
- Compact protocol (≤ 255 bytes, ~3 bytes per input in the log), whispers only during a match,
  paced below Blizzard's limits (also inside instances), result codes handled (throttle,
  lockdown → retry; offline, not in guild → give up). Lost/duplicated/late messages recover.
- Disconnect, forfeit, timeouts, busy/version/combat declines. Combat pauses only your own run.
- Duel history and W/L/D in saved data (separate from solo records).
- Tests: two complete simulated clients over a fake network (loss, duplicates, reordering,
  instance throttling, lockdown, offline, tampering, spoofing).
- Fixes from an independent review of the duel code (15 findings, each with a regression test):
  - the player who finishes second now sends their log at once, and keeps serving it for 60 s
    even after going back to the menu (before, the rival had to ask chunk by chunk);
  - log chunks arriving before their END are kept; missing chunks are asked for only when the
    stream stalls, also while still playing; the log wait counts from when both runs ended;
  - challenging an offline player cancels the challenge (it recorded a win);
  - a "rival gone" mark clears when the rival is heard again, and a complete log always decides;
  - challenging each other at the same moment gives one duel instead of two "busy" refusals;
  - lobby race: the guest waits 15 s longer than the host, and a cancel crossing GO cancels cleanly;
  - leaving after your own run ended is "no result" for you, not a forfeit loss; both forfeiting is
    a draw;
  - security: a withheld log is "no result" (it decided by the claimed score); a failed replay
    check rejects the cheater's result (a loser could escape by sending a bad log); seed
    commit-reveal so nobody can pick or grind the seed; results faster than the clock are rejected;
  - spam: unsolicited replies are rate-limited per player and low priority; re-sent messages
    replace each other in the queue; realm names with hyphens/spaces now match;
  - UI: declining an invite no longer hides a running solo run; "Quit to menu" in a duel is a
    labelled "Forfeit duel" (it left the duel stuck); a duel that starts in combat starts paused;
    the window no longer pops up in combat with "hide in combat" on.
  - Comm: prefix registration result checked; the server's "No player named ..." line is hidden
    for players we just whispered and treats them as offline (API from memory, guarded).

### 0.4.0 round 2 (multiplayer hardening + web integration)

- WoW API: result codes read from the last return value (warcraft.wiki.gg); prefix registration
  result checked and repeated on every login/reload; Trial/Veteran accounts detected.
- Delivery: an accepted send is never treated as delivered. FIN acknowledges results; closed
  matches keep answering with DEC (a lost DEC re-opened the invite popup); other protocol versions
  get a decline in their own version.
- UX: duel starts paused while typing in chat; "Forfeit duel" asks for a second click.
- Diagnostics: last 5 duels in SavedVariables (`duelDiag`), `/sr duel debug`.
- SR1 cross-platform codes (challenge/result), shared test vectors, TypeScript reference checked
  against the web's real `verifyLog` (57/57). Verify.lua: engine_mismatch, faster_than_clock, level claim.
- Fixtures re-based on web commit 29afe52 (no gameplay change); match rules in the fingerprint.
- Docs: MULTIPLAYER_TEST.md (Danish two-client test guide), rewritten CROSS_PLATFORM_MULTIPLAYER.md
  and WEB_INTEGRATION_PROMPT.md.
- Second independent review (14 findings, all fixed, regression tests added): late GO no longer
  makes an honest host look too fast (both sides could record a win); a BYE "left" that overtakes
  a lost END gives no result instead of a win; ignored DECs no longer keep a dead duel alive; offline
  lines match only the rival's exact name and need 6 s of silence; FIN kept on purge and re-acked;
  closed-match memory expires; Trial accounts stay silent; strangers can't flood the diagnostics.
  SR1: printable-ASCII rule (`chars`), real Daily dates, WoW name rules (no invisible/bidi
  characters, BOM kept and rejected), `expired` imports, run key against re-wrapped runs, link codes
  consumed on first use, honest wording on Daily pre-computation.
- Tests: 220 Lua tests + 77 cross-implementation vector checks + a 4,000-code Lua/TS differential fuzz.

## Unreleased (main)
## 0.3.2 — design pass (branch `design`, not released)

- Brand matched to stackrivals.io: the exact "Versus" mark (blades, cuts, steel diamond) from the
  site's SVG, the STACKRIVALS wordmark and display type in Chakra Petch (bundled, SIL OFL), the
  site's colour tokens (navy, card surfaces, brand red/steel/gold, muted text #A3ABBA).
- Readable at any resolution: the window is fitted to ~58% of the screen height at every
  resolution and UI scale, never below 1:1 (Settings: 70-140% of that); larger type, nothing
  under 11 units. Board cells snap to whole physical pixels; the simplified mark is used when the
  header mark would be under 32 px. The window opens right of centre (your character stays
  visible) and its centre is remembered, so resizing never moves it (0.3.1 positions still load).
- Mode menu uses the whole window: three big cards with the best score, one click to play. How
  to play is offered ("New? How to play"), no longer forced on first open; the first runs show the
  controls on the board during the countdown.
- How to play: goal, points table and keycaps for your own key bindings, "Play Blitz 2:00" button.
  Records: a card per mode with the best score, top 5 and stats. Settings: grouped sections.
- Game feel: callouts pop in (Chakra Petch italic), the points you scored float up, the score
  pulses, countdown numbers pulse, "GO!", hard drops flash the board rim, pause/game over fade in,
  a new best pops. All AnimationGroups (run by the client, no Lua per frame).
- Independent design review applied: callouts in tiers (single small and quiet, double/triple
  big, quad biggest in gold with the rim, BACK-TO-BACK above, COMBO ×n counted like the site),
  hard drop gives a 2 px board thump, the last 5 seconds of Blitz pulse, Classic's elapsed time is
  quieter than Blitz's countdown, the ghost piece is an outline with a faint fill, a soft red halo
  behind the window, the controls strip leaves the board at GO, "Start here" on Blitz for a new
  player, "Continue your <mode> run", in-combat notes in the menu and on the pause screen, share
  buttons centred, zero quads not mentioned, Settings hides its own button. After game over Space
  plays again only for 6 s and only with the cursor on the window; then it's WoW's again.
- Chat prefix and AddOn list title now read Stack (white) Rivals (red), like the wordmark.
- Gameplay rules unchanged (engine untouched; parity tests identical).
- Tests: fuzz RNG uses high bits (ported from the multiplayer branch: full state coverage again).

## Unreleased

- Web sync: fixtures now record the web commit they came from (5d2a9fd) and a full rules
  fingerprint; `tools/parity/check_web.sh` compares any newer web version and names each differing
  rule. Records are tagged with the ruleset and archived (never deleted) if the rules change.

## 0.3.1 — prelaunch candidate (not released yet)

Fixes from an independent code review of 0.3.0:
- Game over: Space restarts only for 15 s after the result, never after closing/reopening the window
  and never while Settings is open (so Space is a jump again when you walk away).
- The BEST value no longer keeps an old score after "Quit to menu".
- The "or press <key>" hint follows a rebound hard-drop key.
- Daily countdown on the menu updates while the menu stays open.
- Rescale after UI-scale/resolution change waits one frame for the new screen size.
- Backdrop strips are whole pixels (no seams).

## 0.3.0 — prelaunch candidate (not released yet)

Gameplay & feel
- Game over: press the hard-drop key (Space) to play again, after a 1 s grace period.
- Daily Blitz card shows when the pieces change (00:00 UTC) and your score today.
- Smoother red/steel window backdrop; clearer mode cards; settings show the version.

Stability & performance
- No per-tick table garbage in the game loop, input or rendering; HUD text only updates on change.
- Window re-fits after UI-scale or resolution changes.
- Very long Classic runs (hours) still restore after /reload.
- Saved data records which client build/interface loaded the addon (helps bug reports).

Quality
- Automated layout checks and developer previews of every screen; fixed several overlaps.
- Fuzzing (random keys, clicks, combat, reloads, frame times) on simulated Forever, Retail and
  Classic APIs; 60-minute memory test; 300 corrupted saved files; Daily golden sequences from the
  web engine.
- Reproducible build with validation, checksum and release metadata.

## 0.2.1 — compatibility pass (not released yet)

- Combat check ignores "secret" values on modern clients (Midnight/Forever) instead of risking an error.
- Tested fallbacks for older-client APIs (global `SendChatMessage` / `GetAddOnMetadata`).
- Verified frame-rate independence (same game speed at 30–240 FPS).
- Docs: client compatibility matrix, release plan with fallbacks, support/bug reporting.

## 0.2.0 — quality pass (not released yet)

- How to play screen on first open (and from the menu).
- Records screen: top 5 per mode with dates, lifetime runs/lines/quads/time; labelled local & unverified.
- Game over shows your rank in the top 5.
- Pause key also resumes; while paused every other key (incl. Esc) goes to WoW. Resume countdown 2 s.
- Window always fits the screen at any resolution / UI scale (saved size is kept).
- A Daily Blitz that ends after midnight UTC counts for the day its pieces belong to.
- Fixes from code review: key auto-repeat ignored, key releases we never took go to WoW (no stuck
  running), Enter opens chat on the first press, no chat share during chat lockdown, settings layout.
- TOC lists Retail and the Classic flavors so they can be tested (Forever stays the release target).

## 0.1.0 — WoW Forever launch candidate (not released yet)

- Falling-block puzzle game with the exact stackrivals.io rules (engine v1): 7-bag, hold, 5 next
  pieces, ghost piece, wall kicks, lock delay, combos, back-to-back quads, levels.
- Modes: Classic, Blitz 2:00, Daily Blitz (same pieces for every player each UTC day).
- Combat-safe: auto-pause, keys released, window hidden in combat and restored afterwards.
- Unfinished runs survive `/reload` and logout ("Continue last run").
- Records and lifetime stats per mode, today's Daily best, Share to guild/group.
- Rebindable keys, window size, sound, ghost and minimap options. Minimap button and
  addon-compartment entry. `/sr` and `/stackrivals`.
- Interface 16001 (WoW Forever beta).
