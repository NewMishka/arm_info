#!/usr/bin/env bash
# Execute the production collectors with synthetic DNS and local GVFS fixtures.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
awk '/^have\(\)/{copy=1} /^check_software\(\)/{copy=0} copy' "$ROOT/arm_info.sh" >"$TMP/functions.sh"
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

# GIO-only mounts plus a duplicate FUSE view: enumerate all, probe each once.
source "$TMP/functions.sh"
PRIVACY=1
RUNTIME="$TMP/gio/$(id -u)"
mkdir -p "$RUNTIME/gvfs/smb-share:server=files.example.test,share=Sales Space"
_gvfs_runtime_dirs() { printf '%s\n' "$RUNTIME"; }
_gvfs_session_bus() { printf 'unix:path=/fixture/bus'; }
gio() {
    case "$1" in
        mount)
            printf '%s\n' '  Mount(0): Sales -> smb://files.example.test/Sales%20Space/' \
                '  Mount(1): Archive -> smb://files.example.test/Archive/' \
                '  Mount(2): Broken -> smb://files.example.test/Broken/'
            ;;
        list)
            printf '%s\n' "${@: -1}" >>"$TMP/gio-calls"
            if [[ ${@: -1} == */Broken/ ]]; then echo 'Host is down' >&2; return 1; fi
            printf 'data.txt\n'
            ;;
    esac
}
mkdir -p "$TMP/bin"
{ printf '#!/bin/bash\n'; declare -f gio; printf 'gio "$@"\n'; } >"$TMP/bin/gio"
chmod +x "$TMP/bin/gio"
export PATH="$TMP/bin:$PATH"
export TMP
reset_checks
check_gvfs 1
[[ ${VALUES[*]} == *'3; доступны: 2; проблемы: 1'* ]] || fail 'GIO/FUSE union or deduplication'
[[ $(wc -l <"$TMP/gio-calls") == 2 ]] || fail 'GIO should probe only resources absent from FUSE'
[[ ${LABELS[*]} == *'SMB-ресурс #4'* && $WARN_COUNT == 1 ]] || fail 'GIO report rows'
[[ ${VALUES[*]} != *example.test* && ${DETAILS[*]} != *example.test* ]] || fail 'GIO privacy'

# No FUSE directory at all: the session registry must still be consulted.
RUNTIME="$TMP/gio-only/$(id -u)"
mkdir -p "$RUNTIME"
reset_checks
check_gvfs 0
[[ ${VALUES[*]} == *'3; доступны: 2; проблемы: 1'* ]] || fail 'GIO without FUSE'
unset -f gio

# CUPS: count records, not journal headers; any real warning needs a recommendation.
source "$TMP/functions.sh"
PRIVACY=1
PROFILE=print
ARM_INFO_SELF_CMD=arm_info
have() { case "$1" in journalctl|lpstat) return 0;; *) return 1;; esac; }
lpstat() {
    case "$1" in
        -r) echo 'scheduler is running';;
        -d) echo 'no system default destination'; return 1;;
        -p) echo 'printer fixture is idle. enabled';;
    esac
}
journalctl() {
    case $JOURNAL_CASE in
        two) printf '%s\n' '{"MESSAGE":"backend error"}' '{"MESSAGE":"warning"}';;
        empty) : ;;
        banner) echo '-- No entries --';;
        denied) echo 'Permission denied' >&2; return 1;;
    esac
}
for JOURNAL_CASE in two empty banner denied; do
    reset_checks
    check_print
    for i in "${!KEYS[@]}"; do
        if [[ ${KEYS[i]} == print.journal ]]; then
            case $JOURNAL_CASE in
                two) [[ ${SEVERITIES[i]} == warn && ${VALUES[i]} == '2 за текущую загрузку' ]] || fail 'two CUPS errors must warn';;
                empty|banner) [[ ${SEVERITIES[i]} == ok && ${VALUES[i]} == '0 за текущую загрузку' ]] || fail 'journal noise counted';;
                denied) [[ ${SEVERITIES[i]} == unknown ]] || fail 'unreadable journal reported OK';;
            esac
        fi
        if [[ ${KEYS[i]} == print.default ]]; then
            [[ ${SEVERITIES[i]} == info && ${VALUES[i]} == 'не задан' ]] || fail 'missing default printer reported OK'
        fi
    done
    build_recommendations
    if [[ $JOURNAL_CASE == two ]]; then
        [[ ${REC_KEYS[*]} == *print.journal* && ${REC_COMMANDS[*]} == *'cancel -a'* ]] || fail 'CUPS recommendation missing'
    fi
done
[[ $(command_description 'cancel -a') == *'ИЗМЕНЯЕТ СОСТОЯНИЕ'* ]] || fail 'cancel -a needs destructive-action description'

echo 'Enterprise discovery regression tests: OK'
