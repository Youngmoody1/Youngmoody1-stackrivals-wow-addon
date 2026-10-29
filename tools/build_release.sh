#!/usr/bin/env bash
# Builds the installable ZIP: only the StackRivals/ addon folder (no tests, tools or docs).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep -E '^## Version:' StackRivals/StackRivals.toc | sed 's/## Version: *//' | tr -d '\r')
mkdir -p dist
OUT="dist/StackRivals-${VERSION}.zip"
rm -f "$OUT"
# deterministic-ish archive: sorted file list, no extra attributes
find StackRivals -type f | LC_ALL=C sort | zip -q -X "$OUT" -@
echo "$OUT"
unzip -l "$OUT"
