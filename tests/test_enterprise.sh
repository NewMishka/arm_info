#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/arm_info-enterprise.sh"
die() { echo "TEST FAIL: $*" >&2; exit 1; }

bash -n "$SCRIPT" || die "bash -n enterprise"
[[ $(bash "$SCRIPT" --version) == "arm_info enterprise 1.2.0" ]] || die "--version"
bash "$SCRIPT" --help | grep -q -- '--profile enterprise' || die "--help profiles"

TMP1=$(mktemp); TMP2=$(mktemp); DIFF=$(mktemp)
trap 'rm -f "$TMP1" "$TMP2" "$DIFF"' EXIT

set +e
bash "$SCRIPT" --profile domain --json --privacy >"$TMP1"
RC=$?
set -e
((RC>=0 && RC<=3)) || die "domain exit code $RC"

python3 - "$TMP1" <<'PY' || die "enterprise JSON schema/privacy"
import json,sys
with open(sys.argv[1], encoding='utf-8') as f: d=json.load(f)
assert d['schema_version']==2
assert d['version']=='1.2.0'
assert d['profile']=='domain'
assert d['privacy'] is True
assert isinstance(d['checks'], list) and d['checks']
PY

set +e
bash "$SCRIPT" --profile software --json --privacy >"$TMP2"
RC=$?
set -e
((RC>=0 && RC<=3)) || die "software exit code $RC"

bash "$SCRIPT" --compare "$TMP1" "$TMP1" >"$DIFF" || die "compare identical"
set +e
bash "$SCRIPT" --compare "$TMP1" "$TMP2" --json >"$DIFF"
RC=$?
set -e
[[ $RC -eq 1 ]] || die "compare different exit code $RC"
python3 - "$DIFF" <<'PY' || die "compare JSON"
import json,sys
with open(sys.argv[1], encoding='utf-8') as f: d=json.load(f)
assert d['count'] > 0 and isinstance(d['differences'], list)
PY

echo "OK: enterprise profiles, privacy JSON and compare tests passed"
