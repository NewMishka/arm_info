#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/arm_info.sh"
EXPECTED_VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")

die() { echo "TEST FAIL: $*" >&2; exit 1; }

bash -n "$SCRIPT" || die "bash -n"
[[ $(bash "$SCRIPT" --version) == "arm_info $EXPECTED_VERSION" ]] || die "--version"
bash "$SCRIPT" --help | grep -q -- '--privacy' || die "--help"

grep -q 'print_wrapped "Причины:"' "$SCRIPT" || die "base recommendation causes"
grep -q 'print_wrapped "Проверить:"' "$SCRIPT" || die "base recommendation checks"
grep -q 'print_wrapped "Контроль:"' "$SCRIPT" || die "base recommendation verification"
grep -q 'base_command_description' "$SCRIPT" || die "base command descriptions"
grep -q 'print_wrapped "$REC_NUM. \[${REC_LEVELS\[$i\]}\]"' "$SCRIPT" || die "base recommendation aligned title"
grep -Fq 'Температура CPU|${CPU_TEMP}°C (медиана)' "$SCRIPT" || die "CPU median label"
! grep -Fq '(медиана; максимум ${CPU_TEMP_MAX}°C)' "$SCRIPT" || die "CPU maximum must not be shown with median"
grep -q '"possible_causes"' "$SCRIPT" || die "base recommendation JSON causes"
grep -q '"verification"' "$SCRIPT" || die "base recommendation JSON verification"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
set +e
bash "$SCRIPT" --json --privacy --no-save >"$TMP"
RC=$?
set -e
((RC>=0 && RC<=3)) || die "unexpected diagnostic exit code: $RC"

python3 - "$TMP" <<'PY' || die "JSON schema/privacy/recommendations"
import json,sys
with open(sys.argv[1], encoding='utf-8') as f:
    d=json.load(f)
assert d['schema_version']==1 and d['privacy'] is True
assert d['system']['hostname']=='ARM-REDACTED'
assert isinstance(d['summary']['score'], int)
assert isinstance(d.get('recommendations'), list)
for r in d['recommendations']:
    for k in ('level','title','possible_causes','impact','checks','action','command','verification'):
        assert k in r, (k,r)
PY

echo "OK: CLI, JSON, privacy and standard report contract tests passed"
