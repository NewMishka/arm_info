#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/arm_info.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Static contract for the production checker.
grep -Fq 'findmnt -n -l -t cifs -o TARGET 2>/dev/null' "$SCRIPT" || fail 'TARGET-only findmnt enumeration missing'
grep -Fq 'run_timeout 5 find "$mnt" -mindepth 1 -maxdepth 1 -print -quit' "$SCRIPT" || fail 'real directory-read CIFS probe missing'
! grep -Fq 'findmnt -n -l -t cifs -o TARGET,SOURCE 2>/dev/null | awk' "$SCRIPT" || fail 'whitespace-splitting CIFS parser remains'
! grep -Fq 'run_timeout 4 stat -f "$mnt"' "$SCRIPT" || fail 'metadata-only CIFS probe remains'

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
GOOD="$TMP/Проектный офис"
BAD="$TMP/Несуществующий ресурс"
mkdir -p "$GOOD"
touch "$GOOD/контроль.txt"

# Same minimal read primitive used by arm_info: must handle UTF-8 and spaces.
timeout 5 find "$GOOD" -mindepth 1 -maxdepth 1 -print -quit >/dev/null 2>&1 || fail 'UTF-8/space TARGET probe failed'
if timeout 2 find "$BAD" -mindepth 1 -maxdepth 1 -print -quit >/dev/null 2>&1; then
    fail 'missing TARGET unexpectedly passed directory-read probe'
fi

# Simulate the one-column findmnt stream: the path must arrive unchanged in read -r.
SEEN=''
while IFS= read -r m; do SEEN=$m; done < <(printf '%s\n' "$GOOD")
[[ $SEEN == "$GOOD" ]] || fail "TARGET changed while reading: '$SEEN'"

echo 'CIFS probe regression tests: OK'
