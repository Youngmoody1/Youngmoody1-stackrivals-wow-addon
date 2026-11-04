# Account linking and profile data: security analysis (addon side, 4 Nov 2026)

Scope:
* the formats: web link code, `SRL1`, `SRP1` (draft v1), the planned `SRP2` (proposal only), and
  `SR1R` result codes;
* the addon code: `Core/Account.lua`, `Net/AccountCodes.lua`, `Core/Sync.lua`.

**No new format is introduced here.**

The test vectors are:
* `docs/vectors/account_v1.json`, for decoding;
* `docs/vectors/account_flow_v1.json`, for import decisions and website checks. This file is new
  and **negative-first**.

## The one thing to understand first

**Every code is plain text that anyone can write.** Each code ends with an 8-hex check value, which
only catches typos: anyone can recompute it. Without a signature from the website:

* a pasted snapshot proves nothing about who owns the website account;
* the numbers in it (XP, level, rank, Shards, cosmetics) are claims, not facts.

The vector `forged_but_rechecked` shows this. A snapshot with a raised XP and a recomputed check is
accepted. The addon therefore treats every snapshot as **display data**:

* The Account tab says **LINKED - UNVERIFIED**, never a plain green LINKED.
* The Profile tab carries an **UNVERIFIED** tag.
* **Nothing unlocks** from a snapshot: no cosmetics are applied, and no reward or currency exists
  in WoW.
* **VERIFIED** (green) appears only after a signature check passes. No such scheme exists yet
  (C4).

## Display states (Account tab, Profile tag)

| State | When | Meaning shown to the player |
|---|---|---|
| NOT LINKED | no link on this character | everything works without an account, Loot Duel included |
| PENDING CONFIRMATION | web code typed, waiting for the website's snapshot (15 min) | nothing is linked until step 3 |
| LINKED - UNVERIFIED | a snapshot with the right link was imported | linked on this PC from a pasted snapshot; not checked |
| VERIFIED | (future) a website signature on the snapshot checked out | – |
| OUT OF DATE | the snapshot is older than 7 days, or past its `expires` | paste a new snapshot |
| REJECTED | the last paste was refused (red note, with the reason) | the profile you had is unchanged |

## Threats

| # | Threat | Addon today | Website must | Residual risk | Tests and vectors |
|---|---|---|---|---|---|
| T1 | **Forged profile snapshot** (edited XP, rank, Shards, cosmetics, recomputed check) | Accepted as display data only, marked UNVERIFIED; unlocks nothing; HTML/escape codes shown as text | **Sign snapshots** (C4) | A player can make their own WoW screen show fake numbers. It affects only their own PC | `forged_but_rechecked`; escape-code test |
| T2 | **Replay of an old confirmation** to finish a new link request | Refused if issued before the request (`too_old_for_link`); the request lives 15 min (`pending_expired`); refused if dated in the future | Make each snapshot for the current binding only | none known | `made_before_request`, `request_expired`, `future_dated` |
| T3 | **Re-using a one-time web code** | The addon can't know (no connection) | **Single use**, about 10 min lifetime, rate limit, bound to the logged-in account that created it | brute force, if the rate limit is missing | websiteChecks `code_reused`, `code_expired`, `code_brute_force`, `code_other_account` |
| T4 | **Import on the wrong character** | Refused: the snapshot's `player` must be this character (`player`) | Export only for the binding's `Name-Realm` + platform | none | `wrong_character` |
| T5 | **Binding to another player's account** (an SRL1 crafted with someone else's code) | The SRL1 carries the web code; the addon can't check it | Accept an SRL1 only if its code was issued to **the same logged-in account**; otherwise answer `code_unknown` | none, if the website checks this | `code_other_account` |
| T6 | **Claiming someone else's character name** | – | Store bindings as **CLAIMED**: `Name-Realm` in a code is not proof (only Battle.net OAuth would be); policy for two accounts claiming one character (**C10**) | Two accounts can claim one character until a policy exists | `character_claimed_twice`, `character_not_proven` |
| T7 | **Old or stale Shards / XP shown** | `asOf` shown; OUT OF DATE after 7 days or `expires`; an older snapshot never replaces a newer one; the same one twice changes nothing | Put `asOf` in `SRP2` (C3) | The balance can be up to 7 days old (said on screen) | `older_than_current`, `same_twice`, `expired` |
| T8 | **Manipulated cosmetics** | Only **named**, never applied (nothing to apply yet) | Signature (C4) + cosmetic ids (C8) before any "apply" | none today | `forged_but_rechecked` |
| T9 | **A snapshot from another link or account** | Refused (`link_other`) | – | none | `other_link_while_pending`, `other_link_when_linked` |
| T10 | **Result codes claiming another player** (SR1R `player` or `link` edited) | The addon puts this character and its link into the code; it can't stop an edit | Credit only the account whose binding owns the **link code**; **reject a mismatch**; link code single-use; `runKey` unique; replay | Unlinked results show as `(unlinked)` and earn nothing | websiteChecks `result_other_account`, `result_link_reused`, `result_player_mismatch`, `result_duplicate_run`, `result_unlinked` |
| T11 | **Manipulated result scores** | – | Replay (`importResult`) | A bot playing in real time passes replay; covered by caps (WOW_PROGRESSION_SPEC.md §4) | sr1.json (77 vectors) |
| T12 | **Secrets in the addon** | None exist: no password, e-mail, session token or API key is ever asked for, sent or stored | Never put a secret in a code | – | test "link request carries nothing secret" |
| T13 | **Loot Duel / WoW duel results as rewards** | No export exists; Loot Duel never calls Account or Sync | Never reward `peer_checked` | – | `test_lootduel.lua` "works without any stackrivals.io account" |
| T14 | **A newer format guessed wrongly** | Refused with "update StackRivals" | Never change an existing version's fields | – | `newer_format` |
| T15 | **Wrong code in the wrong box** | Says where it belongs (`is_request`, `is_result`, `is_challenge`) | – | – | `link_request_pasted` |

## What only the website can do (summary for web Claude)

1. Issue web codes:
   * single use, about 10 minutes;
   * bound to the logged-in account;
   * rate limited;
   * an unknown code and another account's code get the same answer.
2. Store a WoW binding as a **claim** (Name-Realm + platform + linkId). Decide the policy for two
   accounts claiming one character (C10).
3. Export snapshots only for that binding, with `asOf`, and **signed** (C4).
4. On result import:
   1. replay;
   2. credit only the binding that owns the link code;
   3. treat the link code as single-use;
   4. keep `runKey` unique;
   5. then apply the reward limits.

## What the addon does (and keeps doing)

| Check | Where it happens |
|---|---|
| Format, version, size, characters, check value | `Net/AccountCodes.lua` |
| This character only | `Acc.import` |
| Same link only | `Acc.import` |
| Not before the request | `Acc.import` |
| Not future-dated, not expired | `Acc.import` |
| Never older, never twice | `Acc.import` |
| Bounded, typed data on load; unknown fields dropped | `Acc.sanitize` |
| Website text shown as text (no WoW escape codes) | UI |
| UNVERIFIED until a signature scheme exists; nothing unlocks | UI |

The addon never stores a secret.
