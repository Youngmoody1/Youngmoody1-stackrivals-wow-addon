#!/usr/bin/env bash
# Compare the WoW addon's Lua engine with a (newer) StackRivals web checkout. READ-ONLY on the web repo.
#
#   tools/parity/check_web.sh ../stackrivals-practice-arena [LUA=lua5.1]
#
# 1. Shows which web commit the addon is based on (tests/fixtures/parity.lua) and the web HEAD.
# 2. Lists web commits since the base that touch gameplay code (engine, controls, bot, match rules).
# 3. Generates fresh fixtures from the web checkout into a temp file and runs the Lua engine tests
#    against them: rules fingerprint (every constant) + 66 replayed games + Daily sequences.
# 4. Generates Spell Battle + bot fixtures (tools/parity/gen-spell-fixtures.ts) and runs tests/test_spells.lua.
# PASS = the web and WoW engines still play identically. FAIL lists exactly what differs.
# Nothing is copied automatically: a FAIL is reviewed and ported by hand (docs/WEB_SYNC.md).
set -euo pipefail
WEB="${1:?usage: check_web.sh <path to stackrivals web repo>}"
LUA="${LUA:-lua5.1}"
cd "$(dirname "$0")/../.."

BASE=$(grep -o 'webCommit"\]="[0-9a-f]*' tests/fixtures/parity.lua | head -1 | sed 's/.*="//')
HEAD=$(git -C "$WEB" rev-parse HEAD)
echo "addon based on web commit: ${BASE:-unknown}"
echo "web checkout HEAD:         $HEAD"

GAMEPLAY_PATHS=(src/game/engine src/game/controls.ts src/game/bot src/lib/match/rules.ts)
if [ -n "$BASE" ] && git -C "$WEB" cat-file -e "$BASE^{commit}" 2>/dev/null; then
  echo
  echo "== gameplay commits since the base =="
  git -C "$WEB" log --oneline "$BASE..$HEAD" -- "${GAMEPLAY_PATHS[@]}" || true
  echo "== files changed =="
  git -C "$WEB" diff --stat "$BASE" "$HEAD" -- "${GAMEPLAY_PATHS[@]}" | tail -20 || true
  echo "== ENGINE_VERSION =="
  git -C "$WEB" diff "$BASE" "$HEAD" -- src/game/engine/types.ts | grep -E '^[+-]export const ENGINE_VERSION' || echo "unchanged"
else
  echo "(base commit not in this checkout's history; fetch more history to list commits)"
fi

# SR1 cross-platform codes: the TS reference + the web's real verifyLog must reproduce every vector
echo
echo "== SR1 code vectors vs web @ ${HEAD:0:7} =="
bun tools/sr1/check_vectors.ts "$WEB" docs/vectors/sr1.json || SR1_FAIL=1

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
bun tools/parity/gen-fixtures.ts "$WEB" > "$TMP"
echo
echo "== Lua engine vs web @ ${HEAD:0:7} =="
if SR_FIXTURES="$TMP" "$LUA" -e 'local H=assert(loadfile("tests/test_engine.lua"))("StackRivals","tests"); if not H.report("engine") then os.exit(1) end'; then
  echo "PASS: web and WoW engines are identical for every rule and every recorded game."
  echo "To move the base forward: bun tools/parity/gen-fixtures.ts \"$WEB\" > tests/fixtures/parity.lua"
else
  echo "FAIL: gameplay differs. Review the lines above, port the change (docs/WEB_SYNC.md), bump"
  echo "ENGINE_VERSION in Lua if the web bumped it, then regenerate the fixtures."
  exit 1
fi
# Spell Battle + bots: spells, mana, cooldowns, effects, bot decisions (v1 + v2), lockstep battles,
# verifySpellMatch verdicts - all from the web's real code
TMP2=$(mktemp)
trap 'rm -f "$TMP" "$TMP2"' EXIT
bun tools/parity/gen-spell-fixtures.ts "$WEB" > "$TMP2"
TMP3=$(mktemp)
trap 'rm -f "$TMP" "$TMP2" "$TMP3"' EXIT
bun tools/parity/gen-spell-scenarios.ts "$WEB" > "$TMP3"
echo
echo "== Spell Battle + bots: Lua vs web @ ${HEAD:0:7} =="
if SR_SPELL_FIXTURES="$TMP2" SR_SPELL_SCENARIOS="$TMP3" "$LUA" -e 'local H=assert(loadfile("tests/test_spells.lua"))("StackRivals","tests"); if not H.report("spells") then os.exit(1) end'; then
  echo "PASS: spells and bots play identically."
  echo "To move the base forward: bun tools/parity/gen-spell-fixtures.ts \"$WEB\" > tests/fixtures/spells.lua"
  echo "                           bun tools/parity/gen-spell-scenarios.ts \"$WEB\" > tests/fixtures/spell_scenarios.lua"
else
  echo "FAIL: Spell Battle or the bot differs. Port the change (docs/SPELL_BATTLE.md), then regenerate."
  exit 1
fi
if [ -n "${SR1_FAIL:-}" ]; then
  echo "FAIL: SR1 code vectors differ between the addon and the web (see above)."
  exit 1
fi
