#!/usr/bin/env bash
# Reproducible release build: same commit -> byte-identical ZIP.
#
#   tools/build_release.sh            # validate, test, package, verify
#   LUA=/path/to/lua5.1 tools/build_release.sh
#
# Output in dist/:
#   StackRivals-<version>.zip          only the StackRivals/ addon folder (no tests/tools/docs)
#   StackRivals-<version>.zip.sha256   checksum
#   StackRivals-<version>.json         version, commit, checksum, interfaces, file list
set -euo pipefail
cd "$(dirname "$0")/.."
LUA="${LUA:-lua5.1}"
ADDON=StackRivals

VERSION=$(grep -E '^## Version:' "$ADDON/$ADDON.toc" | sed 's/## Version: *//' | tr -d '\r')
INTERFACES=$(grep -E '^## Interface:' "$ADDON/$ADDON.toc" | sed 's/## Interface: *//' | tr -d '\r')
COMMIT=$(git rev-parse HEAD 2>/dev/null || echo unknown)
DIRTY=$( [ -z "$(git status --porcelain -- "$ADDON" 2>/dev/null)" ] && echo false || echo true )
# All timestamps in the archive come from the commit, not from the build machine's clock.
EPOCH=$(git log -1 --format=%ct 2>/dev/null || echo 1793750400)

echo "== 1/5 validate addon folder"
python3 tools/validate_addon.py "$ADDON"

echo "== 2/5 run tests ($LUA)"
"$LUA" tests/run.lua | grep -E "passed|ALL TESTS|SOME TESTS"
"$LUA" tests/run.lua >/dev/null

echo "== 3/5 package"
mkdir -p dist
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -r "$ADDON" "$STAGE/"
find "$STAGE/$ADDON" -type f -exec chmod 0644 {} +
find "$STAGE/$ADDON" -type d -exec chmod 0755 {} +
find "$STAGE/$ADDON" -exec touch -h -d "@$EPOCH" {} +
OUT="dist/$ADDON-$VERSION.zip"
rm -f "$OUT"
( cd "$STAGE" && find "$ADDON" -type f | LC_ALL=C sort | TZ=UTC zip -q -X -D "$OLDPWD/$OUT" -@ )

echo "== 4/5 verify archive"
CHECK=$(mktemp -d)
( cd "$CHECK" && unzip -q "$OLDPWD/$OUT" )
diff -r "$ADDON" "$CHECK/$ADDON" >/dev/null || { echo "archive content differs from $ADDON/"; exit 1; }
EXTRA=$(cd "$CHECK" && find . -mindepth 1 -maxdepth 1 ! -name "$ADDON")
[ -z "$EXTRA" ] || { echo "unexpected top-level entries: $EXTRA"; exit 1; }
[ -f "$CHECK/$ADDON/$ADDON.toc" ] || { echo "TOC not at $ADDON/$ADDON.toc"; exit 1; }
if (cd "$CHECK" && find . -path "*/tests/*" -o -path "*/tools/*" -o -name "*.py" -o -name "*.ts" -o -name "*.md" | grep -q .); then
  echo "development files in archive"; exit 1
fi
rm -rf "$CHECK"

echo "== 5/5 checksum + metadata"
SHA=$(sha256sum "$OUT" | cut -d' ' -f1)
echo "$SHA  $(basename "$OUT")" > "$OUT.sha256"
FILES=$(cd "$STAGE" && find "$ADDON" -type f | LC_ALL=C sort | sed 's/.*/    "&"/' | paste -sd, -)
cat > "dist/$ADDON-$VERSION.json" <<JSON
{
  "name": "$ADDON",
  "version": "$VERSION",
  "commit": "$COMMIT",
  "addonFolderDirty": $DIRTY,
  "sourceDateEpoch": $EPOCH,
  "interfaces": "$INTERFACES",
  "sha256": "$SHA",
  "files": [
$FILES
  ]
}
JSON
echo "$OUT"
echo "sha256 $SHA"
[ "$DIRTY" = "false" ] || echo "WARNING: StackRivals/ has uncommitted changes; commit before a real release so the build is reproducible."
