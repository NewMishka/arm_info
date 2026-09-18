#!/usr/bin/env bash
# Bounded execution, shared network budget and controlled DC concurrency.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
ORIGINAL_PATH=$PATH
trap 'PATH=$ORIGINAL_PATH; rm -rf -- "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

bash "$ROOT/arm_info.sh" -c --help >"$TMP/help"
grep -q -- '--network-budget SEC' "$TMP/help" || fail 'network budget missing from help'
grep -q -- '--network-jobs N' "$TMP/help" || fail 'network concurrency missing from help'
if bash "$ROOT/arm_info.sh" --profile software --network-budget 0 >/dev/null 2>&1; then
    fail 'zero network budget accepted'
else
    [[ $? == 64 ]] || fail 'invalid network budget must be CLI error'
fi
if bash "$ROOT/arm_info.sh" --profile software --network-jobs=17 >/dev/null 2>&1; then
    fail 'excessive network concurrency accepted'
else
    [[ $? == 64 ]] || fail 'invalid network jobs must be CLI error'
fi

# Load the production common runner plus enterprise collectors without invoking CLI.
sed -n '/^_arm_run_limited() {/,/^}/p' "$ROOT/arm_info.sh" >"$TMP/runner.sh"
awk '/^have\(\)/{copy=1} /^check_software\(\)/{copy=0} copy' "$ROOT/arm_info.sh" >"$TMP/functions.sh"
# shellcheck disable=SC1091
source "$TMP/runner.sh"
# shellcheck disable=SC1091
source "$TMP/functions.sh"

# Missing timeout must yield UNKNOWN-compatible rc=125 and never run unbounded.
mkdir "$TMP/no-timeout"
cat >"$TMP/probe" <<EOF_PROBE
#!/bin/sh
touch '$TMP/unbounded-ran'
EOF_PROBE
chmod +x "$TMP/probe"
PATH="$TMP/no-timeout"; hash -r
rc=0; _arm_run_limited 1 "$TMP/probe" || rc=$?
PATH=$ORIGINAL_PATH; hash -r
[[ $rc == 125 && ! -e $TMP/unbounded-ran ]] || fail 'missing timeout ran command without a limit'

# GNU timeout result must be preserved.
SECONDS=0
rc=0; _arm_run_limited 1 sleep 5 || rc=$?
[[ $rc == 124 && $SECONDS -le 2 ]] || fail 'bounded runner did not stop a hung command'

reset_checks() {
    KEYS=(); LABELS=(); VALUES=(); SEVERITIES=(); SECTIONS=(); DETAILS=()
    WARN_COUNT=0; CRIT_COUNT=0; UNKNOWN_COUNT=0
}
PRIVACY=0
_dns_upstreams() { printf '192.0.2.53'; }
_srv_records() {
    case $1 in
        _ldap._tcp.example.test) printf '0 100 389 dc%s.example.test.\n' {1..8};;
    esac
}
mkdir "$TMP/active"
_tcp_ok() {
    local token="$TMP/active/$BASHPID-$1-$2"
    : >"$token"
    find "$TMP/active" -type f | wc -l >>"$TMP/concurrency"
    sleep 0.15
    rm -f -- "$token"
    [[ $1 != dc8.example.test ]]
}
ARM_INFO_DC_JOBS=3
ARM_INFO_DC_PROBE_TIMEOUT=2
ARM_INFO_NETWORK_BUDGET=10
NETWORK_PROBE_DEADLINE=0
reset_checks
check_dns_common 'DNS / DOMAIN' example.test
[[ $(wc -l <"$TMP/concurrency") == 16 ]] || fail 'not every DC port was scheduled'
peak=$(sort -nr "$TMP/concurrency" | head -n1)
[[ $peak -ge 2 && $peak -le 3 ]] || fail "DC concurrency escaped limit: $peak"
[[ ${LABELS[*]} == *'Контроллер #8'* ]] || fail 'parallel probe truncated controller list'
[[ ${VALUES[*]} == *'14 из 16 TCP-проверок'* ]] || fail 'parallel result merge changed statuses'

# A short common budget must leave all resources visible and mark the rest untested.
_srv_records() {
    case $1 in
        _ldap._tcp.example.test) printf '0 100 389 dc%s.example.test.\n' {1..20};;
    esac
}
_tcp_ok() { sleep "$3"; return 1; }
ARM_INFO_DC_JOBS=2
ARM_INFO_DC_PROBE_TIMEOUT=5
ARM_INFO_NETWORK_BUDGET=1
NETWORK_PROBE_DEADLINE=0
SECONDS=0
reset_checks
check_dns_common 'DNS / DOMAIN' example.test
[[ $SECONDS -le 3 ]] || fail 'global network budget was not enforced'
[[ ${LABELS[*]} == *'Контроллер #20'* ]] || fail 'budget removed discovered controllers'
[[ ${VALUES[*]} == *'не проверены: 38; лимит времени: 38'* ]] || fail 'budget exhaustion not reported'
[[ $UNKNOWN_COUNT -ge 20 ]] || fail 'budget exhaustion must be incomplete, not OK'

# The same deadline is shared with SMB/GIO active probes.
mkdir "$TMP/share"
_cifs_probe "$TMP/share"
[[ $CIFS_PROBE_STATE == BUDGET && $CIFS_PROBE_RC == 126 ]] || fail 'SMB did not inherit exhausted network budget'
[[ $(_cifs_state_text "$CIFS_PROBE_STATE") == 'не проверен (лимит времени)' ]] || fail 'budget reason hidden from report'

echo 'Stage 2 bounded network tests OK'
