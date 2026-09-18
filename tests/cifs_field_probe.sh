#!/usr/bin/env bash
set -u
set -o pipefail

# Полевой read-only probe CIFS для актуальной версии arm_info.
# Ничего не монтирует/размонтирует и не меняет Kerberos/CIFS credentials.
# Цель: отличить реальный timeout/metadata failure ресурса от ошибки пользовательского контекста
# на sec=krb5,multiuser и зафиксировать причину без ложного «зависла».

TIMEOUT_SEC=${CIFS_PROBE_TIMEOUT:-5}

have() { command -v "$1" >/dev/null 2>&1; }

find_desktop_user() {
    local sid uid user active remote stype

    if have loginctl; then
        while read -r sid uid user _; do
            [[ -n ${sid:-} && ${uid:-} =~ ^[0-9]+$ && -n ${user:-} ]] || continue
            ((uid > 0)) || continue
            case "$user" in root|gdm|lightdm|sddm) continue ;; esac

            active=$(loginctl show-session "$sid" -p Active --value 2>/dev/null || true)
            remote=$(loginctl show-session "$sid" -p Remote --value 2>/dev/null || true)
            stype=$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)

            if [[ $active == yes && $remote != yes && ($stype == x11 || $stype == wayland) ]]; then
                printf '%s\n' "$user"
                return 0
            fi
        done < <(loginctl list-sessions --no-legend 2>/dev/null)
    fi

    if have who; then
        user=$(who 2>/dev/null | awk '$0 ~ /\(:[0-9]+\)/ {print $1; exit}')
        if [[ -n ${user:-} ]]; then
            printf '%s\n' "$user"
            return 0
        fi
    fi

    return 1
}

PROBE_RC=125
PROBE_ERR=''

run_probe() {
    local mnt=$1 as_user=${2:-} errfile

    PROBE_RC=125
    PROBE_ERR=''

    if ! have timeout || ! have ls || ! have find || ! have stat; then
        PROBE_ERR='timeout/ls/find/stat отсутствует — безопасная проверка не выполнена'
        return 0
    fi

    errfile=$(mktemp) || {
        PROBE_ERR='не удалось создать временный файл для stderr'
        return 0
    }

    local -a prefix=()
    local samplefile sample
    if [[ -n $as_user ]]; then
        if have runuser; then prefix=(runuser -u "$as_user" --)
        elif have sudo; then prefix=(sudo -n -u "$as_user" --)
        else
            PROBE_RC=125
            printf '%s\n' 'runuser/sudo отсутствует — нет безопасного способа сменить UID' >"$errfile"
            PROBE_ERR=$(cat "$errfile")
            rm -f -- "$errfile"
            return 0
        fi
    fi

    "${prefix[@]}" env LC_ALL=C timeout "$TIMEOUT_SEC" ls -U -A -1 -- "$mnt" >/dev/null 2>"$errfile"
    PROBE_RC=$?
    if ((PROBE_RC == 0)); then
        samplefile=$(mktemp)
        : >"$errfile"
        "${prefix[@]}" env LC_ALL=C timeout "$TIMEOUT_SEC" find "$mnt" -mindepth 1 -maxdepth 1 -print -quit >"$samplefile" 2>"$errfile"
        PROBE_RC=$?
        IFS= read -r sample <"$samplefile" || sample=''
        rm -f -- "$samplefile"
        if ((PROBE_RC == 0)) && [[ -n $sample ]]; then
            : >"$errfile"
            "${prefix[@]}" env LC_ALL=C timeout "$TIMEOUT_SEC" stat -L -- "$sample" >/dev/null 2>"$errfile"
            PROBE_RC=$?
        fi
    fi

    PROBE_ERR=$(tr '\n' ' ' <"$errfile" | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//' | cut -c1-240)
    rm -f -- "$errfile"
    return 0
}

classify_probe() {
    local rc=$1 err=${2:-}

    case "$rc" in
        0)   printf 'OK' ; return ;;
        124|137) printf 'TIMEOUT' ; return ;;
        125) printf 'INCONCLUSIVE' ; return ;;
    esac

    case "$err" in
        *'Permission denied'*|*'Operation not permitted'*) printf 'DENIED' ;;
        *'Required key not available'*|*'Key has expired'*|*'No credentials'*) printf 'AUTH' ;;
        *'Host is down'*|*'Network is unreachable'*|*'No route to host'*|*'Connection timed out'*) printf 'NETWORK' ;;
        *'Stale file handle'*|*'Input/output error'*) printf 'IO' ;;
        *'No such file or directory'*) printf 'MISSING' ;;
        *) printf 'ERROR' ;;
    esac
}

print_probe_line() {
    local label=$1 state=$2 rc=$3 err=${4:-}
    printf '  %-24s %s (rc=%s)' "$label" "$state" "$rc"
    [[ -n $err ]] && printf ' — %s' "$err"
    printf '\n'
}

if ! have findmnt; then
    echo 'ОШИБКА: findmnt отсутствует.' >&2
    exit 3
fi

DESKTOP_USER=$(find_desktop_user 2>/dev/null || true)
CURRENT_USER=$(id -un 2>/dev/null || printf 'uid=%s' "$(id -u)")

printf 'CIFS field probe — arm_info\n'
printf 'Текущий контекст : %s (uid=%s)\n' "$CURRENT_USER" "$(id -u)"
printf 'GUI-пользователь  : %s\n' "${DESKTOP_USER:-не определён}"
printf 'Timeout           : %s сек.\n' "$TIMEOUT_SEC"

TOTAL=0
OK_COUNT=0
WARN_COUNT=0
UNKNOWN_COUNT=0

while IFS= read -r mnt; do
    [[ -n $mnt ]] || continue
    TOTAL=$((TOTAL+1))

    source=$(findmnt -n -T "$mnt" -o SOURCE 2>/dev/null | head -n1)
    options=$(findmnt -n -T "$mnt" -o OPTIONS 2>/dev/null | head -n1)
    multiuser=no
    [[ ,$options, == *,multiuser,* ]] && multiuser=yes

    printf '\n[%d] %s\n' "$TOTAL" "$mnt"
    printf '  SOURCE                  %s\n' "${source:-не определён}"
    printf '  multiuser               %s\n' "$multiuser"

    run_probe "$mnt" ''
    direct_rc=$PROBE_RC
    direct_err=$PROBE_ERR
    direct_state=$(classify_probe "$direct_rc" "$direct_err")
    print_probe_line "контекст $CURRENT_USER" "$direct_state" "$direct_rc" "$direct_err"

    final_state=$direct_state
    final_rc=$direct_rc
    final_err=$direct_err
    final_context=$CURRENT_USER

    if [[ $multiuser == yes && $(id -u) -eq 0 ]]; then
        if [[ -n $DESKTOP_USER ]]; then
            run_probe "$mnt" "$DESKTOP_USER"
            user_rc=$PROBE_RC
            user_err=$PROBE_ERR
            user_state=$(classify_probe "$user_rc" "$user_err")
            print_probe_line "контекст $DESKTOP_USER" "$user_state" "$user_rc" "$user_err"

            # Для sec=krb5,multiuser доступ пользователя важнее результата root:
            # root может не иметь CIFS credentials, хотя GUI-пользователь работает штатно.
            final_state=$user_state
            final_rc=$user_rc
            final_err=$user_err
            final_context=$DESKTOP_USER
        else
            final_state=INCONCLUSIVE
            final_rc=125
            final_err='multiuser mount запущен из root, но активный локальный GUI-пользователь не определён'
            final_context='не определён'
        fi
    fi

    printf '  ИТОГ                   %s — контекст: %s' "$final_state" "$final_context"
    [[ -n $final_err && $final_state != OK ]] && printf ' — %s' "$final_err"
    printf '\n'

    case "$final_state" in
        OK) OK_COUNT=$((OK_COUNT+1)) ;;
        INCONCLUSIVE) UNKNOWN_COUNT=$((UNKNOWN_COUNT+1)) ;;
        *) WARN_COUNT=$((WARN_COUNT+1)) ;;
    esac
done < <(findmnt -n -l -t cifs -o TARGET 2>/dev/null)

printf '\nСводка: CIFS=%d; OK=%d; проблемы=%d; неполная проверка=%d\n' \
    "$TOTAL" "$OK_COUNT" "$WARN_COUNT" "$UNKNOWN_COUNT"

if ((TOTAL == 0)); then
    echo 'CIFS mount не обнаружены.'
    exit 0
fi

if ((WARN_COUNT > 0)); then
    exit 1
elif ((UNKNOWN_COUNT > 0)); then
    exit 3
else
    exit 0
fi
