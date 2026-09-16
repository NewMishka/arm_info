#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/arm_info.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

grep -Fq 'findmnt -n -l -t cifs -o TARGET 2>/dev/null' "$SCRIPT" || fail 'TARGET-only findmnt enumeration missing'
grep -Fq '_cifs_desktop_user()' "$SCRIPT" || fail 'user-aware CIFS context helper missing'
grep -Fq 'timeout 6 ls -U -A -1 -- "$mnt"' "$SCRIPT" || fail 'full directory enumeration CIFS probe missing'
grep -Fq 'timeout 6 stat -L -- "$sample"' "$SCRIPT" || fail 'metadata lookup CIFS probe missing'
grep -Fq 'network.cifs.mount.$cifs_count' "$SCRIPT" || fail 'per-share report rows missing'
! grep -Fq 'run_timeout 5 find "$mnt" -mindepth 1 -maxdepth 1 -print -quit' "$SCRIPT" || fail 'old first-entry-only probe remains'
! grep -Fq 'findmnt -n -l -t cifs -o TARGET,SOURCE 2>/dev/null | awk' "$SCRIPT" || fail 'whitespace-splitting CIFS parser remains'

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
GOOD="$TMP/Проектный офис"
BAD="$TMP/Несуществующий ресурс"
mkdir -p "$GOOD"
touch "$GOOD/контроль.txt"

timeout 2 ls -U -A -1 -- "$GOOD" >/dev/null 2>&1 || fail 'UTF-8/space full-directory read failed'
SAMPLE=$(timeout 2 find "$GOOD" -mindepth 1 -maxdepth 1 -print -quit)
[[ -n $SAMPLE ]] || fail 'sample entry missing'
timeout 2 stat -L -- "$SAMPLE" >/dev/null 2>&1 || fail 'sample metadata lookup failed'
if timeout 2 ls -U -A -1 -- "$BAD" >/dev/null 2>&1; then fail 'missing TARGET unexpectedly passed readdir probe'; fi

SEEN=''
while IFS= read -r m; do SEEN=$m; done < <(printf '%s\n' "$GOOD")
[[ $SEEN == "$GOOD" ]] || fail "TARGET changed while reading: '$SEEN'"

echo 'CIFS probe regression tests: OK'
