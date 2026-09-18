#!/usr/bin/env bash
# Stage 3: collectors -> normalized inventory -> probes -> report checks.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

awk '/^have\(\)/{copy=1} /^check_software\(\)/{copy=0} copy' "$ROOT/arm_info.sh" >"$TMP/functions.sh"
# shellcheck disable=SC1091
source "$TMP/functions.sh"

# Architectural contract: collectors and probes must not create report rows.
for fn in collect_domain_controller_inventory collect_cifs_resources collect_autofs_resources collect_gvfs_resources probe_network_resources; do
    declare -F "$fn" >/dev/null || fail "$fn missing"
    ! declare -f "$fn" | grep -Fq 'add_check ' || fail "$fn mixes collection with report checks"
done
declare -f emit_domain_controller_checks | grep -Fq 'add_check ' || fail 'DC emitter does not create checks'
declare -f emit_network_resource_checks | grep -Fq 'add_check ' || fail 'resource emitter does not create checks'
declare -f check_network | grep -Fq 'check_network_resources' || fail 'network profile bypasses stage 3 pipeline'
! declare -f check_network | grep -Fq '_cifs_probe ' || fail 'network profile probes resources while collecting'

reset_checks() {
    KEYS=(); LABELS=(); VALUES=(); SEVERITIES=(); SECTIONS=(); DETAILS=()
    WARN_COUNT=0; CRIT_COUNT=0; UNKNOWN_COUNT=0
}
PRIVACY=0
PROBE_AUTOFS=0
ARM_INFO_NETWORK_BUDGET=30
NETWORK_PROBE_DEADLINE=0

RUNTIME="$TMP/runtime/$(id -u)"
mkdir -p "$RUNTIME/gvfs/smb-share:server=files.example.test,share=Sales" \
    "$RUNTIME/gvfs/Документы" "$RUNTIME/gvfs/Проекты" "$TMP/bin"
touch "$RUNTIME/gvfs/smb-share:server=files.example.test,share=Sales/data.txt"
touch "$RUNTIME/gvfs/Документы/вложенный-файл.txt"
cat >"$TMP/bin/gio" <<'GIO'
#!/usr/bin/env bash
case "$1" in
    mount)
        printf '%s\n' \
          '  Mount(0): Sales -> smb://files.example.test/Sales/' \
          '  Mount(1): Broken -> smb://files.example.test/Broken/'
        ;;
    list) printf 'data.txt\n' ;;
esac
GIO
chmod +x "$TMP/bin/gio"
PATH="$TMP/bin:$PATH"

have() { command -v "$1" >/dev/null 2>&1; }
_cifs_desktop_user() { id -un; }
_gvfs_runtime_dirs() { printf '%s\n' "$RUNTIME"; }
_gvfs_session_bus() { printf 'unix:path=/fixture/bus'; }
_autofs_map_targets() { printf '%s\n' '/mnt/Общий_(X)' '/mnt/Internet_(N)'; }
findmnt() {
    case "$*" in
        '-n -l -t cifs -o TARGET') printf '%s\n' \
            '/mnt/Общий_(X)' \
            '/mnt/Общий_(X)/DFS/Отдел' \
            '/mnt/Общий_(X)/DFS/Архив документов' \
            '/mnt/Home Folder_(Z)' ;;
        '-n -T /mnt/Общий_(X) -o SOURCE') echo '//files.example.test/common' ;;
        '-n -T /mnt/Home Folder_(Z) -o SOURCE') echo '//files.example.test/home' ;;
        '-n -T /mnt/Общий_(X) -o OPTIONS'|'-n -T /mnt/Home Folder_(Z) -o OPTIONS') echo 'rw,multiuser,sec=krb5' ;;
        '-n -l -t autofs -o TARGET') echo /mnt ;;
        '-C -n -M /mnt -t autofs -o SOURCE') echo /etc/auto.samba ;;
        '-C -n -M /mnt/Общий_(X) -t cifs -o TARGET') echo '/mnt/Общий_(X)' ;;
    esac
}
_cifs_probe() {
    printf 'path:%s\n' "$1" >>"$TMP/probe-calls"
    CIFS_PROBE_RC=0; CIFS_PROBE_ERR=''; CIFS_PROBE_STATE=OK
    [[ $1 == '/mnt/Home Folder_(Z)' ]] && { CIFS_PROBE_RC=1; CIFS_PROBE_ERR='Host is down'; CIFS_PROBE_STATE=NETWORK; }
    return 0
}
_gio_probe() {
    printf 'gio:%s\n' "$1" >>"$TMP/probe-calls"
    CIFS_PROBE_RC=0; CIFS_PROBE_ERR=''; CIFS_PROBE_STATE=OK
    [[ $1 == */Broken/ ]] && { CIFS_PROBE_RC=1; CIFS_PROBE_ERR='Host is down'; CIFS_PROBE_STATE=NETWORK; }
    return 0
}

network_resource_inventory_reset
collect_cifs_resources
collect_autofs_resources
collect_gvfs_resources
[[ ${#NETRES_KEYS[@]} == 5 ]] || fail "normalized inventory has ${#NETRES_KEYS[@]} resources, expected 5"
[[ ${NETRES_KEYS[*]} != *Документы* && ${NETRES_KEYS[*]} != *Проекты* ]] || fail 'share subdirectories were reported as GVFS mounts'
[[ ${NETRES_KEYS[*]} != *'/DFS/'* ]] || fail 'nested CIFS/DFS mounts were reported as separate shares'
[[ ${NETRES_ORIGINS[${NETRES_INDEX['path:/mnt/Общий_(X)']}-1]} == 'cifs,autofs' ]] || fail 'CIFS/autofs resource was not merged'
[[ ${NETRES_DETAILS[${NETRES_INDEX['path:/mnt/Общий_(X)']}-1]} == *'вложенных CIFS/DFS mounts: 2'* ]] || fail 'nested CIFS/DFS mount count was not retained'
[[ ${NETRES_CONFIGURED[${NETRES_INDEX['path:/mnt/Internet_(N)']}-1]} == yes ]] || fail 'configured flag lost'
[[ ${NETRES_MOUNTED[${NETRES_INDEX['path:/mnt/Internet_(N)']}-1]} == no ]] || fail 'inactive autofs resource reported mounted'

probe_network_resources
[[ ${NETRES_STATES[${NETRES_INDEX['path:/mnt/Internet_(N)']}-1]} == NOT_MOUNTED ]] || fail 'inactive autofs resource did not stay visible'
! grep -Fq '/mnt/Internet_(N)' "$TMP/probe-calls" || fail 'passive inventory triggered autofs mount'
! grep -Fq '/DFS/' "$TMP/probe-calls" || fail 'nested CIFS/DFS mount was probed as a separate share'
[[ $(grep -c '^gio:' "$TMP/probe-calls") == 1 ]] || fail 'FUSE/GIO duplicate was probed twice'

reset_checks
emit_network_resource_checks 0 all
[[ ${VALUES[*]} == *'2; доступны: 1; проблемы: 1; не проверены: 0'* ]] || fail 'CIFS summary changed'
[[ ${VALUES[*]} == *'2; уже смонтированные показаны в CIFS'* ]] || fail 'autofs summary changed'
[[ ${VALUES[*]} == *'2; доступны: 1; проблемы: 1; не проверены: 0'* ]] || fail 'GVFS/GIO union summary changed'
[[ ${LABELS[*]} == *'SMB-ресурс #5'* ]] || fail 'per-resource numbering is incomplete'
[[ $WARN_COUNT == 2 ]] || fail "expected two broken resources, got $WARN_COUNT warnings"

PRIVACY=1
reset_checks
emit_network_resource_checks 0 all
[[ ${VALUES[*]} != *example.test* && ${VALUES[*]} != *'/mnt/'* && ${VALUES[*]} != *"$TMP"* ]] || fail 'resource privacy leak in values'
[[ ${DETAILS[*]} != *example.test* && ${DETAILS[*]} != *'/mnt/'* && ${DETAILS[*]} != *"$TMP"* ]] || fail 'resource privacy leak in details'

echo 'Stage 3 collector/check architecture tests OK'
