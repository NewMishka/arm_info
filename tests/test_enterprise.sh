#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/arm_info.sh"
EXPECTED_VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")
die() { echo "TEST FAIL: $*" >&2; exit 1; }

bash -n "$SCRIPT" || die "bash -n enterprise"
[[ $(bash "$SCRIPT" --profile domain --version) == "arm_info enterprise $EXPECTED_VERSION" ]] || die "--version"
[[ $(bash "$SCRIPT" --corp --version) == "arm_info enterprise $EXPECTED_VERSION" ]] || die "--corp version"
bash "$SCRIPT" --profile domain --help | grep -q -- '--profile enterprise' || die "--help profiles"
bash "$SCRIPT" --corp --help | grep -q -- '--corp' || die "--corp help"
grep -q 'enterprise) check_domain; check_network; check_print ;;' "$SCRIPT" || die "enterprise profile must exclude software inventory"

# No hard-coded application/vendor inventory and no hard-coded Kerberos error-code list.
if grep -Eiq '(r7|remmina|freerdp|icaclient|citrix|basis|workplace|bsscrypto|cryptopro|cprocsp|jacarta|snx)' "$SCRIPT"; then
  die "hard-coded software names found"
fi
if grep -Eq 'Kerberos 6/7/15|c6=|c7=|c15=' "$SCRIPT"; then
  die "hard-coded Kerberos error codes found"
fi

TMP1=$(mktemp); TMP2=$(mktemp); DIFF=$(mktemp)
trap 'rm -f "$TMP1" "$TMP2" "$DIFF"' EXIT

set +e
bash "$SCRIPT" --profile domain --json --privacy >"$TMP1"
RC=$?
set -e
((RC>=0 && RC<=3)) || die "domain exit code $RC"

python3 - "$TMP1" "$EXPECTED_VERSION" <<'PY' || die "enterprise JSON schema/privacy"
import json,sys
with open(sys.argv[1], encoding='utf-8') as f: d=json.load(f)
assert d['schema_version']==2
assert d['version']==sys.argv[2]
assert d['profile']=='domain'
assert d['privacy'] is True
assert isinstance(d['checks'], list) and d['checks']
assert isinstance(d.get('recommendations'), list)
for r in d['recommendations']:
    for k in ('key','level','title','source','possible_causes','impact','checks','action','commands','verification'):
        assert k in r, (k,r)
    assert isinstance(r['commands'], list)
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

# Recommendations must be present in text output when diagnostics are incomplete/warn/crit.
TXT=$(mktemp)
trap 'rm -f "$TMP1" "$TMP2" "$DIFF" "$TXT"' EXIT
set +e
bash "$SCRIPT" --profile domain --privacy >"$TXT"
RC=$?
set -e
((RC>=0 && RC<=3)) || die "domain text exit code $RC"
grep -q '^РЕКОМЕНДАЦИИ$' "$TXT" || die "recommendations structure"
grep -Eq 'Возможные причины:|Дополнительных действий' "$TXT" || die "recommendations detail"

# v1.2.2 text-report contract.
grep -q "print_check_row 'Параметр' 'Статус' 'Значение'" "$SCRIPT" || die "enterprise column header"
grep -q 'openssl x509 -in' "$SCRIPT" || die "802.1X certificate date command"
grep -q 'покажет даты начала и окончания действия сертификата' "$SCRIPT" || die "command explanations"
grep -q 'JSON_MODE==0' "$SCRIPT" || die "interactive clear guard"
