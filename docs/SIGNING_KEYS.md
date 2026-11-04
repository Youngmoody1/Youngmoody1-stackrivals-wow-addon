# Signed profile codes: key registry and limits (addon 0.9.1)

The website signs the profile codes it exports (SRP1-SIG v1 and SRP2-SIG v1, Ed25519). The addon checks them
and shows the result:
* **VERIFIED**: the website's signature checked out.
* **LINKED - UNVERIFIED**: the code is unsigned, or signed with a key this version doesn't know.
* **REJECTED**: the code was changed after it was signed.

The contract lives in the website's docs and is reproduced here by the vectors:

| Website file | What it holds |
|---|---|
| `docs/WOW_ADDON_BRIDGE.md` §3 | SRP1-SIG v1 |
| `docs/WOW_SRP2.md` | SRP2-SIG v1 |
| `docs/vectors/srp1_sig_v1.json` | SRP1 signature vectors |
| `docs/vectors/srp2_v1.json` | SRP2 vectors (16 parse + 9 signature cases) |

## Where the keys are

| What | Where | Who sees it |
|---|---|---|
| Private key (32-byte seed) | stackrivals.io server secrets only: `WOW_SNAPSHOT_SIGNING_KEY`, with the kid in `WOW_SNAPSHOT_KEY_ID` | **No one**: not in a chat, not on GitHub, not shown to the owner. It is created where it lives |
| Public key (32 bytes = 64 hex) + kid (2 × `[a-z0-9]`) | `StackRivals/Net/SnapshotKeys.lua` | Everyone. It's public by design |
| RFC 8032 test key, kid `t1` | the tests only (`tests/test_ed25519.lua`, `tests/test_signed_import.lua`) | Everyone. It's public, **so it is never trusted by the addon** |

## Adding the production key (0.9.1)

1. The website side creates the key pair in its server secrets. That is web-Claude's task, with the owner's
   separate GO.
2. Only the kid and the 64-hex public key come here. Add them with the tool:
   ```
   python3 tools/add_public_key.py --kid k1 --public <64 hex characters>
   ```
   The tool refuses:
   * the kid `t1`;
   * the RFC 8032 test keys;
   * anything that isn't 64 hex characters;
   * bytes that aren't an Ed25519 public key.
3. Run the tests. `tests/test_ed25519.lua` ("shipped keys") fails if a test key were ever in the table.
4. Get a real signed code from stackrivals.io/wow and check it in WoW. It must show VERIFIED, and an edited copy
   must be REJECTED. This is `docs/TEST_PLAN_0.9.1.md`, part B.

## Rotation

* **A new key:** add its kid with the tool and ship an addon update. The website switches to the new kid once
  players have that update.
* **Retiring a key:** `python3 tools/add_public_key.py --remove <kid>` in a later update. Codes signed with it then
  show UNVERIFIED, never an error.
* A saved VERIFIED profile stays VERIFIED after a reload only while its kid is still shipped.

## What VERIFIED does and does not mean (limits)

* **It means:** stackrivals.io made exactly this code, and nobody changed it afterwards. That covers every
  value in it:
  * the character, link id and account;
  * the name, level, XP and rank;
  * Shards, owned and equipped items, and events;
  * issued and expires.
* **It does not mean:**
  * **That the player owns that WoW character.** A binding is a claim (C10), and only Battle.net could prove
    ownership.
  * **That the code is new.** An old signed code stays valid until `expires`. Newest-wins and the 7-day OUT OF
    DATE rule still apply.
* **Local only:** the VERIFIED flag in SavedVariables is the player's own file. Editing it could only fool that
  player's own screen. It is also dropped when its kid isn't shipped. The website never trusts anything from
  WoW because of it.
* **If the website's private key leaked,** whoever had it could make VERIFIED codes until the kid is retired in an
  addon update.
* **The cryptography is verify-only.** There is no signing and no secret in the addon.
  * Ed25519 (RFC 8032) with SHA-512, in pure Lua 5.1 (`Net/Ed25519.lua`): TweetNaCl's field arithmetic and a
    one-pass double scalar multiplication.
  * It refuses S ≥ L and public keys that aren't curve points.
  * It is not constant-time. That doesn't matter for verification, because every input is public.
  * It passes RFC 8032 TEST 1–3, every SRP1-SIG and SRP2-SIG vector from the website, and its own
    edited-code tests.
* **Speed:**
  * One check is about 80–150 ms of pure Lua here; CI notes print the Lua 5.1 time.
  * In WoW it runs in a coroutine, at most about 5 ms per frame (`Account.ASYNC_BUDGET_MS`). About 0.4 s at
    60 FPS, longer at low FPS, but **never a freeze**.
  * Import is disabled while it runs, and the screen says "Checking the website's signature...".
  * The same code pasted again is "already imported" at once, with no second check.
