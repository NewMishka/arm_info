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
bash "$SCRIPT" --corp --help | grep -q -- '--no-save' || die "--corp no-save help"
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

# v1.2.2 text-report and saving contract.
grep -q "print_check_row 'Параметр' 'Статус' 'Значение'" "$SCRIPT" || die "enterprise column header"
grep -q 'openssl x509 -in' "$SCRIPT" || die "802.1X certificate date command"
grep -q 'покажет даты начала и окончания действия сертификата' "$SCRIPT" || die "command explanations"
grep -q 'JSON_MODE==0' "$SCRIPT" || die "interactive clear guard"
grep -q 'SAVE_REPORT=1' "$SCRIPT" || die "corporate save default"
grep -q -- '--no-save) SAVE_REPORT=0' "$SCRIPT" || die "corporate no-save switch"
grep -q 'ARM_INFO_CORP_' "$SCRIPT" || die "corporate automatic report name"
grep -q 'split_rec_commands' "$SCRIPT" || die "corporate command splitter"
grep -Fq 'nmcli -t -f UUID,TYPE connection show 2>/dev/null' "$SCRIPT" || die "802.1X must inspect all configured NM profiles"
grep -q 'Сертификат АРМ (кандидат 802.1X)' "$SCRIPT" || die "802.1X host certificate fallback"
grep -q 'Профили 802.1X' "$SCRIPT" || die "802.1X configured/active summary"
grep -Fq 'done < <(split_rec_commands "$text")' "$SCRIPT" || die "corporate text commands must preserve pipelines"
grep -q 'print_rec_command_line' "$SCRIPT" || die "corporate commands must use copy-safe renderer"
grep -Fq 'done < <(split_rec_commands "${REC_COMMANDS[i]}")' "$SCRIPT" || die "corporate JSON commands must preserve pipelines"

# v1.2.3 corporate header and 802.1X certificate contract.
grep -q "ARM_INFO КОРПОРАТИВНЫЙ" "$SCRIPT" || die "corporate Russian header"
grep -q "Профиль: корпоративный" "$SCRIPT" || die "corporate profile label"
grep -q 'nmcli -e no -g' "$SCRIPT" || die "802.1X nmcli unescaped certificate path"
grep -q '802-1x.phase2-client-cert' "$SCRIPT" || die "802.1X phase2 client certificate"
grep -q 'Начало действия —' "$SCRIPT" || die "802.1X notBefore output"
grep -q 'Окончание действия —' "$SCRIPT" || die "802.1X notAfter output"
grep -q 'openssl x509 -inform DER' "$SCRIPT" || die "802.1X DER certificate support"
