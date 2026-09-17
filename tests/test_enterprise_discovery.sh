#!/usr/bin/env bash
# Execute the production collectors with synthetic DNS and local GVFS fixtures.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
awk '/^have\(\)/{copy=1} /^check_print\(\)/{copy=0} copy' "$ROOT/arm_info.sh" >"$TMP/functions.sh"
# shellcheck disable=SC1091
source "$TMP/functions.sh"
PRIVACY=0
reset_checks() {
    KEYS=(); LABELS=(); VALUES=(); SEVERITIES=(); SECTIONS=(); DETAILS=()
    WARN_COUNT=0; CRIT_COUNT=0; UNKNOWN_COUNT=0
}
_dns_upstreams() { printf '192.0.2.53'; }
_srv_records() {
    case "$1" in
        _ldap._tcp.example.test) printf '0 100 389 dc%s.example.test.\n' 1 2 3 4 5 ;;
        _kerberos._tcp.example.test) printf '0 100 88 DC1.example.test.\n0 100 88 dc2.example.test.\n0 0 0 .\n' ;;
        _ldap._tcp.dc._msdcs.example.test) printf '0 100 389 dc6.example.test.\n' ;;
    esac
}
_tcp_ok() {
    printf '%s:%s\n' "$1" "$2" >>"$TMP/tcp-calls"
    [[ $1 != dc6.example.test ]]
}
check_dns_common 'DNS / DOMAIN' example.test
[[ $(wc -l <"$TMP/tcp-calls") == 12 ]] || fail 'must check both ports of all six DCs'
[[ $(sort -u "$TMP/tcp-calls" | wc -l) == 12 ]] || fail 'duplicate DC probes'
[[ ${VALUES[*]} == *'10 из 12 TCP-проверок'* ]] || fail 'DC total'
[[ ${LABELS[*]} == *'Контроллер #6'* ]] || fail 'DC list truncated'
[[ ${SEVERITIES[*]} == *crit* ]] || fail 'unavailable sixth DC lost'
reset_checks
_tcp_ok() { return 2; }
check_dns_common 'DNS / DOMAIN' example.test
for i in "${!KEYS[@]}"; do
    if [[ ${KEYS[i]} == domain.dc.node.* ]]; then
        [[ ${SEVERITIES[i]} == unknown && ${VALUES[i]} == *'не проверен'* ]] || fail 'missing TCP tools must be UNKNOWN'
    fi
done

# Two readable resources and a broken one, including UTF-8 and spaces.
RUNTIME="$TMP/$(id -u)"
mkdir -p "$RUNTIME/gvfs/smb-share:server=files.example.test,share=Отдел продаж" \
    "$RUNTIME/gvfs/smb-share:server=files.example.test,share=Archive"
touch "$RUNTIME/gvfs/smb-share:server=files.example.test,share=Отдел продаж/данные.txt"
ln -s "$TMP/absent" "$RUNTIME/gvfs/smb-share:server=files.example.test,share=Broken"
_gvfs_runtime_dirs() { printf '%s\n' "$RUNTIME"; }
reset_checks
check_gvfs 1
[[ ${LABELS[*]} == *'SMB-ресурс #4'* ]] || fail 'GVFS resources must continue CIFS numbering'
[[ ${VALUES[*]} == *'3; доступны: 2; проблемы: 1; не проверены: 0'* ]] || fail 'broken resource disappeared'
[[ ${VALUES[*]} == *'Отдел продаж'* && ${VALUES[*]} == *'Broken'* ]] || fail 'resource names lost'
[[ $WARN_COUNT == 1 ]] || fail 'broken GVFS should have its own warning'
reset_checks
PRIVACY=1
check_gvfs 0
[[ ${VALUES[*]} != *example.test* && ${DETAILS[*]} != *example.test* && ${DETAILS[*]} != *"$TMP"* ]] || fail 'GVFS privacy leak'
[[ ${VALUES[*]} == *'3; доступны: 2; проблемы: 1'* ]] || fail 'privacy changed checks'

# Own-user invocation must not require root-only runuser, even if installed.
own_uid=$(_cifs_exec_as "$(id -un)" id -u)
[[ $own_uid == "$(id -u)" ]] || fail 'own-user execution'
if ((EUID==0)) && command -v runuser >/dev/null && runuser -u nobody -- true 2>/dev/null; then
    [[ $(_cifs_exec_as nobody id -u) == "$(id -u nobody)" ]] || fail 'owner context'
    chmod 755 "$TMP"
    nobody_uid=$(id -u nobody)
    RUNTIME="$TMP/$nobody_uid"
    mkdir -p "$RUNTIME/gvfs/smb-share:server=files.example.test,share=Owner"
    chown -R nobody "$RUNTIME"
    chmod 700 "$RUNTIME"
    reset_checks
    check_gvfs 0
    [[ ${VALUES[*]} == *'1; доступны: 1; проблемы: 0'* ]] || fail 'root must enumerate as FUSE owner'
    mkdir "$RUNTIME/gvfs/smb-share:server=files.example.test,share=Denied"
    chmod 000 "$RUNTIME/gvfs/smb-share:server=files.example.test,share=Denied"
    reset_checks
    check_gvfs 0
    [[ ${VALUES[*]} == *'2; доступны: 1; проблемы: 1'* && ${VALUES[*]} == *'нет доступа'* ]] || fail 'access-denied resource disappeared'
    # Test the real helper inside an unprivileged shell as well.
    runuser -u nobody -- bash -c 'source "$1"; test "$(_cifs_exec_as "$(id -un)" id -u)" = "$(id -u)"' _ "$TMP/functions.sh" || fail 'non-root own-user execution'
fi

# Enumeration failure must never turn into the misleading "no mounts".
reset_checks
_cifs_exec_as() { return 125; }
check_gvfs 0
[[ $UNKNOWN_COUNT == 1 && ${VALUES[*]} == *'список не получен полностью'* ]] || fail 'failed discovery hidden'
[[ ${VALUES[*]} != *'нет'* ]] || fail 'failed discovery reported as absent'

# Validate the help columns as rendered, not as source-code strings.
bash "$ROOT/arm_info.sh" --help >"$TMP/help"
python3 - "$TMP/help" <<'PY' || exit 1
import re, sys
lines = open(sys.argv[1], encoding='utf-8').read().splitlines()
columns = [re.search('[а-яё]', line).start() for line in lines if re.match(r'  -(?:p|s|h|V|o|q),', line)]
assert len(columns) == 6 and len(set(columns)) == 1, columns
PY
echo 'Enterprise discovery regression tests: OK'
