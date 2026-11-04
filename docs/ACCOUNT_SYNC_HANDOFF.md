# One StackRivals account for the website and WoW: account sync handoff (DRAFT v1)

> **Entry point:** `docs/WEB_HANDOFF.md` (0.7.0) is the one handoff file for the website. This document holds the details it links to.

Addon 0.6.1+ (built on `feature/connected`; current: 0.7.0 on `feature/loot-duel`). **Status: SIMULATED.** The addon side is built and tested
in the test suite (`tests/test_account.lua`). Nothing has been tested in a real WoW client, and
nothing has been tested against stackrivals.io: the website side doesn't exist yet. The formats
are a **draft until the web project agrees**. Nothing here is final.

## 1. Principles

* **One account.** The player's StackRivals account lives on stackrivals.io. There is no WoW
  account database, no new backend and no second login.
* **The website is the authority** for the account, profile, XP, level, rank, seasons, cosmetics,
  achievements, match history and results. The addon only shows what the website gave it.
* **No secrets in WoW.**
  * The addon never asks for an e-mail, a password, a Battle.net login or a token.
  * Login happens on the website only.
  * Every code the addon makes or reads is safe to show on screen.
* **No internet in WoW.** An addon can't make HTTP or WebSocket calls. The player carries short
  text codes between the two (copy and paste). This is **manual sync, not live sync**, and the UI
  says so.
* **A typed code proves nothing.** The addon shows **Linked** only after it has imported a profile
  snapshot made by the website for exactly this link request (same `linkId`) and this character.
* **No Shards.** Nothing in these formats is a currency, wallet or reward. Shards are built in the
  web project.

## 2. Link flow

```
stackrivals.io (logged in with e-mail)                 WoW addon (this character)
-----------------------------------------------        ----------------------------------------
1. Account > Link WoW character
   -> one-time code  A7K9-P2XJ  (valid ~10 min,
      single use, bound to the logged-in account)
                                                       2. Account > type A7K9-P2XJ > Link
                                                          state PENDING (not linked!)
                                                          shows the link request:
                                                          SRL1.A7K9P2XJ.wow-classic.<player>.<linkId>...
3. paste the SRL1 request
   web checks: code exists, not used, not expired,
   belongs to this account; stores
   { accountId, player "Name-Realm", platform,
     linkId, linkedAt }, marks the code used
   -> shows the confirmation snapshot SRP1.<linkId>...
                                                       4. paste the SRP1 snapshot > Import
                                                          checks: format, checksum, this
                                                          character, same linkId as PENDING,
                                                          made after the request, not expired
                                                          state LINKED (profile shown)
Later: Account > WoW > Export snapshot (same linkId)   -> Import: newer replaces older; older or
                                                          duplicate refused (no rollback)
Unlink on the website (and in WoW: "Unlink")           -> WoW forgets link + profile on this PC
```

**States in the addon (per character):**

| State | Meaning |
|---|---|
| NOT LINKED | nothing, or the player unlinked here |
| PENDING | a web code was typed and a request shown; waiting for the web's snapshot. Expires after 15 min |
| LINKED | a valid snapshot for this link and character, younger than 7 days and not expired |
| NOT SYNCED | linked, but the snapshot is older than 7 days or past its `expires`. Shown with the date |

## 3. Formats (draft v1)

Every code ends in `.<check>`.

* `check` = 8 lowercase hex digits of FNV-1a 32 over everything before `.<check>`. It is the same
  checksum as SR1 (`docs/CROSS_PLATFORM_MULTIPLAYER.md`).
* It only catches typos. It is **not** security.
* `b36` = lowercase base 36 with no leading zeros (`0` for zero).
* `hex` = lowercase hex of UTF-8 bytes.

### 3.1 Web link code (website → player → addon)

* 8 symbols from Crockford base32: `0123456789ABCDEFGHJKMNPQRSTVWXYZ`. Shown as `XXXX-XXXX`.
* The 8th symbol is a check symbol: `(Σ value(sᵢ)·(2i−1) for i = 1..7) mod 32`.
  * The weights are odd, so every single wrong symbol is caught.
* The addon ignores case, spaces and `-`, and reads `O`→`0` and `I`/`L`→`1`.
* The website should make the 7 symbols with a CSPRNG and keep each code:
  * single use;
  * about 10 minutes valid;
  * bound to the logged-in account;
  * rate-limited (for example, 5 codes per hour).

### 3.2 Link request `SRL1` (addon → player → website)

```
SRL1.<code8>.<platform>.<playerHex>.<linkId>.<addon>.<engine>.<issued36>.<check>
```

| Field | Rule |
|---|---|
| code8 | the web code without the dash, check symbol valid |
| platform | `wow-forever` \| `wow-retail` \| `wow-classic` (as in SR1) |
| playerHex | hex of `Name-Realm` (SR1 name rules) |
| linkId | 12 `[a-z0-9]`, random per request (made by the addon, public) |
| addon | addon version with `-` (`0-6-1`) |
| engine | `ENGINE_VERSION` (decimal) |
| issued36 | WoW server time (unix s) when the code was typed |

### 3.3 Profile snapshot `SRP1` (website → player → addon)

```
SRP1.<linkId>.<playerHex>.<accountId>.<nameHex>.<issued36>.<expires36>.<level36>.<xp36>.<xpNext36>
    .<rankHex>.<seasonHex>.<seasonPct>.<w36>.<l36>.<d36>.<history>.<ach>.<cos>.<sig>.<check>
```

| Field | Rule |
|---|---|
| linkId | from the SRL1 request this link was made with (all later snapshots repeat it) |
| playerHex | the linked character (must be the character importing it) |
| accountId | 4–40 `[a-z0-9_-]`, the website's public account ref (never an e-mail, never secret) |
| nameHex | display name, 1–32 bytes UTF-8, no control characters (`\|` is shown escaped) |
| issued36 / expires36 | unix s; `expires > issued`, at most 30 days later |
| level / xp / xpNext | b36; level ≤ 9999, xp ≤ 10¹², xpNext `0` = unknown |
| rankHex / seasonHex | `-` or 1–24 bytes UTF-8 |
| seasonPct | 0–100 decimal |
| w / l / d | b36 ≤ 10⁹: the website's own win / loss / draw counts |
| history | `-` or ≤ 10 entries joined by `~`: `<mode>-<w\|l\|d>-<my36>-<their36>-<at36>`, mode `[a-z0-9]{1,12}` (b120, r180, s180, classic, blitz, daily, spellbot or web modes) |
| ach | `-` or `<unlocked36>-<total36>`, unlocked ≤ total ≤ 9999 |
| cos | `-` or `<owned36>-<equippedHex\|->` |
| sig | `-` or 16–128 `[A-Za-z0-9_-]`. Reserved for a web signature (for example Ed25519). **0.6.1 / 0.7.0 don't check it** |

The maximum code length is 4096 characters. Anything outside these rules is rejected with a clear
error.

### 3.4 Errors shown in WoW

The full text of each error is in `Account.ERRORS` in `StackRivals/Core/Account.lua`.

| Error | When |
|---|---|
| `empty` | nothing was pasted |
| `chars` | characters that don't belong in a code |
| `size` | the code is too long |
| `format` | not a StackRivals code |
| `wrong_kind` | another StackRivals code type (for example SR1C pasted as a profile) |
| `version` | a newer format: update StackRivals |
| `fields` / `check` | incomplete, or a typo |
| `player` | the snapshot is for another character |
| `not_pending` | a snapshot arrived but no link was started |
| `link_other` | the snapshot belongs to another link |
| `pending_expired` | the 15-minute request ran out |
| `too_old_for_link` | the snapshot was made before the request |
| `expired` | past `expires` (10 min clock tolerance) |
| `future` | dated more than 10 minutes ahead |
| `older` | older than the snapshot already imported (no rollback) |
| `duplicate` | this snapshot was already imported |
| `webcode_format` / `webcode_check` | the typed web code is malformed |

## 4. Test vectors (from the Lua reference encoder, `Net/AccountCodes.lua`)

```
web code   "A7K9P2X" + check            -> A7K9P2XJ   (shown A7K9-P2XJ)
web code   "0000000" -> 00000000          "ZZZZZZZ" -> ZZZZZZZF
SRL1  code A7K9P2XJ, wow-classic, Alice-Realm, linkId k3v9q2m7x1aa, 0.6.1, engine 1, issued 1793000000
  SRL1.A7K9P2XJ.wow-classic.416c6963652d5265616c6d.k3v9q2m7x1aa.0-6-1.1.tni7nk.f1b8a2c8
SRP1  full (Alice Stack, level 12, 1240/2000 XP, Gold II, Season 3 45 %, 12-8-1, one Duel 2:00 win,
      14/60 achievements, 5 cosmetics wearing "Neon Grid", issued 1793000060, expires +7 days)
  SRP1.k3v9q2m7x1aa.416c6963652d5265616c6d.acc_7f3k2.416c69636520537461636b.tni7p8.tnv6d8.c.yg.1jk.476f6c64204949.536561736f6e2033.45.c.8.1.b120-w-9ho-7k8-tni4vk.e-1o.5-4e656f6e2047726964.-.a06ade80
SRP1  minimal (Alice, everything unknown, expires +1 day)
  SRP1.k3v9q2m7x1aa.416c6963652d5265616c6d.acc_7f3k2.416c696365.tni7p8.tnk2d8.0.0.0.-.-.0.0.0.0.-.-.-.-.4146f9ee
```

* Negative cases (each must be rejected) are in `tests/test_account.lua`:
  * a wrong check;
  * a cut code;
  * `SRP2`;
  * an SR1 code;
  * a control character in the name;
  * level 10000;
  * `expires ≤ issued`;
  * `expires` more than 30 days later;
  * 11 history entries;
  * achievements unlocked > total;
  * a short `sig`;
  * a dot in `accountId`;
  * a bad player.
* A JSON vector file for the TypeScript side follows with the full data contract
  (`docs/STACKRIVALS_WEB_INTEGRATION.md`, text 3/4).

## 5. Sync conflicts, stale and manipulated data

* **Newest wins, by `issued`.** An older snapshot never replaces a newer one, and the same one is
  never imported twice.
* **Stale.** After 7 days, or past `expires`, the state is NOT SYNCED with the date. The profile
  is still shown, marked as out of date.
* **Manipulated snapshots.** Anyone can type a code, so a hand-made snapshot can fool only that
  player's own display.
  * It can't change local records, duel results, Quickplay cards or anything on the website.
    A test checks this.
  * The `sig` field is reserved so a later version can show "verified by stackrivals.io".
* **Manipulated SavedVariables** are cleaned on load:
  * types and ranges are checked;
  * at most 50 characters are kept, linked ones first;
  * a profile without a link is dropped.
* **Results from WoW to the website** (export) come in text 3/4 with SR1 / SR2 result codes. The
  website replays them. It never trusts a WoW summary.

## 6. One identity on every platform

* The website owns `accountId`. Each platform links to it:
  * **WoW:** a character (`Name-Realm` + platform) per link, through SRL1 / SRP1.
  * **Web, Windows, Chrome, Android, iPhone:** the website's normal login and session.
* Nothing in the addon stores a platform login.
* Battle.net `gameAccountID`s are never used as an identity. They are temporary.

## 7. Optional companion app: research only (NOT built, needs your approval first)

The goal is fewer copy and paste steps. This is a look at the options, not a plan to build.

| Option | How | Blizzard rules | Verdict |
|---|---|---|---|
| A. Read SavedVariables after logout / `/reload` | a desktop app reads `WTF\Account\<ACCOUNT>\SavedVariables\StackRivals.lua` (a file WoW writes on logout / reload) and uploads new result codes | it only reads a file on disk: no memory reading, no injection, no game input. This is the same pattern as WeakAuras Companion and other addon managers | **feasible**, needs your approval and a check of the current Blizzard terms |
| B. Write data for the addon to read at `/reload` | the app writes a data file (Lua) into the addon folder; the addon loads it at the next `/reload` or login | this is how WeakAuras Companion delivers updates; the addon must validate everything it reads | **feasible**, but adds trust questions (the file is as forgeable as a pasted code) |
| C. Live link while playing | would need memory reading, packet sniffing, screen scraping or simulated input | not allowed (automation, memory reading) | **no** |
| D. Clipboard helper | the app watches the clipboard for SRL1 / SRP1 codes and sends them for you | allowed, but privacy-sensitive (it reads everything you copy) | possible, but not recommended |

* Any companion must do the following:
  * log in on the website with the normal login, with its token kept by the OS key store and
    never put in WoW;
  * never touch the WoW process;
  * be optional.
* **Nothing is built.** This needs a decision from you and a current check of Blizzard's rules.

## 8. What the website needs to build (for web Claude)

1. **Link WoW character page** (logged in): make a one-time code (§3.1), with a text box to paste
   the SRL1 request.
2. **Check SRL1:**
   * format and check (§3.2);
   * the code exists, isn't used and isn't expired;
   * the code belongs to the logged-in account.

   Store `{accountId, platform, player, linkId, linkedAt}`. A character can link to one account
   at a time: re-linking moves it, after a confirmation.
3. **Make SRP1** (§3.3) for a link: on confirm, and from "Export snapshot" later. Use the website's
   own profile data and `expires` = now + 7 days. Optionally sign it (`sig`).
4. **Unlink:** remove the binding. Later snapshots for that `linkId` are no longer made.
5. **Rate limits and audit:**
   * code creation and SRL1 attempts are rate-limited per account and per IP;
   * links and unlinks are logged.
6. **Accept the vectors in §4 byte for byte** (FNV-1a check, b36, hex, field order).
7. Later (text 3/4): import WoW result codes (SR1 now, SR2 when agreed), replay them, and only
   then count them.

## 9. Prompt for web Claude

> You are working in the stackrivals.io project. The WoW addon (repository
> Youngmoody1-stackrivals-wow-addon, branch `feature/loot-duel`, file
> `docs/ACCOUNT_SYNC_HANDOFF.md`) now has an Account section. A WoW character can link to an
> existing StackRivals account by copy and paste of text codes, because WoW addons have no
> internet access. Please implement the website side of DRAFT v1, without changing the formats
> unless you write down why:
>
> 1. A logged-in "Link WoW character" page that makes a one-time code. It is 8 Crockford base32
>    symbols, the last one a check symbol with odd weights (§3.1), and it is single use, valid
>    about 10 minutes and rate-limited.
> 2. A text box that accepts the addon's `SRL1` link request (§3.2). Validate the format, the
>    FNV-1a check, the code (exists, not used, not expired, belongs to this account), the
>    platform and the player. Then store the binding
>    `{accountId, platform, player, linkId, linkedAt}` and mark the code used.
> 3. Make the `SRP1` profile snapshot (§3.3) from the website's own profile data: name, rank,
>    level, XP, season, W/L/D, the last 10 matches, achievements and cosmetics. No Shards and no
>    currencies. Show it for copy on confirm and through "Export snapshot" later, with
>    `expires` = now + 7 days. Leave `sig` as `-` for now, or propose a signature scheme.
> 4. Unlink, rate limits and an audit log.
> 5. Unit tests that reproduce the vectors in §4 exactly, and reject every negative case listed
>    there.
>
> The website stays the authority. Never accept a profile or result from WoW as truth: results
> come later as SR1 / SR2 replays. Don't ask WoW players for passwords or tokens, and don't put
> any secret in the codes. Report back on anything in the draft that doesn't fit the website's
> account model, before building around it.
