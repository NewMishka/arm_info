#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
arm = root / "arm_info.sh"
text = arm.read_text(encoding="utf-8")

helper = r'''
_cifs_desktop_user() {
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
        if [[ -n ${user:-} ]]; then printf '%s\n' "$user"; return 0; fi
    fi
    return 1
}

_cifs_exec_as() {
    local as_user=${1:-}; shift
    if [[ -n $as_user ]]; then
        if have runuser; then runuser -u "$as_user" -- "$@"
        elif have sudo; then sudo -n -u "$as_user" -- "$@"
        else return 125
        fi
    else
        "$@"
    fi
}

_cifs_classify() {
    local rc=$1 err=${2:-}
    case "$rc" in
        0) printf 'OK'; return ;;
        124|137) printf 'TIMEOUT'; return ;;
        125) printf 'INCONCLUSIVE'; return ;;
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

CIFS_PROBE_STATE=INCONCLUSIVE
CIFS_PROBE_RC=125
CIFS_PROBE_ERR=''
_cifs_probe() {
    local mnt=$1 as_user=${2:-} errfile samplefile sample rc
    CIFS_PROBE_STATE=INCONCLUSIVE; CIFS_PROBE_RC=125; CIFS_PROBE_ERR=''
    if ! have timeout || ! have ls || ! have find || ! have stat; then
        CIFS_PROBE_ERR='для надёжной проверки нужны timeout, ls, find и stat'
        return 0
    fi
    errfile=$(mktemp) || { CIFS_PROBE_ERR='не удалось создать временный stderr'; return 0; }
    samplefile=$(mktemp) || { rm -f -- "$errfile"; CIFS_PROBE_ERR='не удалось создать временный sample'; return 0; }

    # Этап 1: полностью прочитать список имён в каталоге. В отличие от
    # find -print -quit это не завершается после первого cached dentry.
    _cifs_exec_as "$as_user" env LC_ALL=C timeout 6 ls -U -A -1 -- "$mnt" >/dev/null 2>"$errfile"
    rc=$?
    if ((rc != 0)); then
        CIFS_PROBE_RC=$rc
        CIFS_PROBE_ERR=$(tr '\n' ' ' <"$errfile" | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//' | cut -c1-240)
        CIFS_PROBE_STATE=$(_cifs_classify "$rc" "$CIFS_PROBE_ERR")
        rm -f -- "$errfile" "$samplefile"
        return 0
    fi

    # Этап 2: если каталог не пустой, получить метаданные одного элемента.
    # Caja/приложения делают metadata lookup, поэтому простой readdir недостаточен.
    : >"$errfile"
    _cifs_exec_as "$as_user" env LC_ALL=C timeout 6 find "$mnt" -mindepth 1 -maxdepth 1 -print -quit >"$samplefile" 2>"$errfile"
    rc=$?
    if ((rc != 0)); then
        CIFS_PROBE_RC=$rc
        CIFS_PROBE_ERR=$(tr '\n' ' ' <"$errfile" | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//' | cut -c1-240)
        CIFS_PROBE_STATE=$(_cifs_classify "$rc" "$CIFS_PROBE_ERR")
        rm -f -- "$errfile" "$samplefile"
        return 0
    fi
    IFS= read -r sample <"$samplefile" || sample=''
    if [[ -n $sample ]]; then
        : >"$errfile"
        _cifs_exec_as "$as_user" env LC_ALL=C timeout 6 stat -L -- "$sample" >/dev/null 2>"$errfile"
        rc=$?
        if ((rc != 0)); then
            CIFS_PROBE_RC=$rc
            CIFS_PROBE_ERR=$(tr '\n' ' ' <"$errfile" | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//' | cut -c1-240)
            CIFS_PROBE_STATE=$(_cifs_classify "$rc" "$CIFS_PROBE_ERR")
            rm -f -- "$errfile" "$samplefile"
            return 0
        fi
    fi

    CIFS_PROBE_STATE=OK; CIFS_PROBE_RC=0; CIFS_PROBE_ERR=''
    rm -f -- "$errfile" "$samplefile"
}

_cifs_state_text() {
    case "$1" in
        OK) printf 'доступен' ;;
        TIMEOUT) printf 'тайм-аут' ;;
        DENIED) printf 'нет доступа' ;;
        AUTH) printf 'ошибка аутентификации' ;;
        NETWORK) printf 'сеть недоступна' ;;
        IO) printf 'ошибка I/O' ;;
        MISSING) printf 'точка недоступна' ;;
        INCONCLUSIVE) printf 'не проверен' ;;
        *) printf 'ошибка' ;;
    esac
}
'''

if '_cifs_desktop_user() {' not in text:
    text = text.replace('\ncheck_network() {\n', '\n' + helper + '\ncheck_network() {\n', 1)

old_decl = '    local gw ifaces idx=0 row iface ip mac speed duplex link dns_domain cifs_count=0 cifs_bad=0 mnt cifs_bad_value gvfs_count=0 gvfs_bad=0 g dir\n    local -a cifs_bad_targets=()\n'
new_decl = '    local gw ifaces idx=0 row iface ip mac speed duplex link dns_domain cifs_count=0 cifs_ok=0 cifs_bad=0 cifs_unknown=0 mnt gvfs_count=0 gvfs_bad=0 g dir\n    local cifs_source cifs_options cifs_multiuser cifs_user cifs_context cifs_state cifs_text cifs_detail cifs_sev cifs_source_display cifs_target_display\n'
if old_decl not in text:
    raise SystemExit('old CIFS local declaration not found')
text = text.replace(old_decl, new_decl, 1)

pattern = re.compile(r'''    if have findmnt; then\n        # Читаем только TARGET одной колонкой.*?    else add_check "SMB / GVFS" "network\.cifs" "CIFS mounts" "findmnt отсутствует" unknown; fi\n\n''', re.S)
replacement = r'''    if have findmnt; then
        cifs_user=$(_cifs_desktop_user 2>/dev/null || true)
        while IFS= read -r mnt; do
            [[ -n $mnt ]] || continue
            cifs_count=$((cifs_count+1))
            cifs_source=$(findmnt -n -T "$mnt" -o SOURCE 2>/dev/null | head -n1)
            cifs_options=$(findmnt -n -T "$mnt" -o OPTIONS 2>/dev/null | head -n1)
            cifs_multiuser=no
            [[ ,$cifs_options, == *,multiuser,* ]] && cifs_multiuser=yes
            cifs_context=$(id -un 2>/dev/null || printf 'uid=%s' "$(id -u)")

            if [[ $cifs_multiuser == yes && $(id -u) -eq 0 ]]; then
                if [[ -n $cifs_user ]]; then
                    cifs_context=$cifs_user
                    _cifs_probe "$mnt" "$cifs_user"
                else
                    CIFS_PROBE_STATE=INCONCLUSIVE
                    CIFS_PROBE_RC=125
                    CIFS_PROBE_ERR='multiuser mount: активный локальный GUI-пользователь не определён'
                fi
            else
                _cifs_probe "$mnt" ''
            fi

            cifs_state=$CIFS_PROBE_STATE
            cifs_text=$(_cifs_state_text "$cifs_state")
            cifs_detail="контекст: $cifs_context; multiuser: $cifs_multiuser"
            [[ -n $CIFS_PROBE_ERR ]] && cifs_detail="$cifs_detail; $CIFS_PROBE_ERR"
            case "$cifs_state" in
                OK) cifs_ok=$((cifs_ok+1)); cifs_sev=ok ;;
                INCONCLUSIVE) cifs_unknown=$((cifs_unknown+1)); cifs_sev=unknown ;;
                *) cifs_bad=$((cifs_bad+1)); cifs_sev=warn ;;
            esac

            if ((PRIVACY)); then
                cifs_source_display='источник скрыт'
                cifs_target_display='TARGET скрыт'
            else
                cifs_source_display=${cifs_source:-не определён}
                cifs_target_display=$mnt
            fi
            add_check "SMB / GVFS" "network.cifs.mount.$cifs_count" "SMB-ресурс #$cifs_count" "$cifs_source_display → $cifs_target_display; $cifs_text" "$cifs_sev" "$cifs_detail"
        done < <(findmnt -n -l -t cifs -o TARGET 2>/dev/null)

        if ((cifs_count==0)); then
            add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "нет" info
        else
            add_check "SMB / GVFS" "network.cifs" "CIFS итого" "$cifs_count; доступны: $cifs_ok; проблемы: $cifs_bad; не проверены: $cifs_unknown" info
        fi
    else
        add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "findmnt отсутствует" unknown
    fi

'''
text, n = pattern.subn(replacement, text, count=1)
if n != 1:
    raise SystemExit(f'CIFS production block replacement count={n}')

text = text.replace('        network.cifs)\n', '        network.cifs|network.cifs.mount.*)\n', 1)
text = text.replace(
    '            REC_CAUSE="Один или несколько CIFS mount не отвечают в короткий timeout. Возможны недоступная шара, сеть, Kerberos/учётные данные или зависший mount."\n'
    '            REC_IMPACT="Caja/приложения могут зависать при открытии, сохранении, удалении и обходе каталогов."\n'
    '            REC_CHECK="Определить локальные TARGET всех CIFS mount без raw-режима findmnt, затем выполнить минимальное фактическое чтение каждого каталога с timeout. Это выявляет ресурс, который смонтирован, но не открывается. SOURCE вида //server/share как локальный путь не использовать."\n'
    '            REC_ACTION="Устранить сетевую/аутентификационную причину; зависший mount размонтировать только после проверки открытых файлов и процессов."\n'
    '            REC_COMMAND="findmnt -t cifs -o TARGET,SOURCE,OPTIONS|findmnt -n -l -t cifs -o TARGET | while IFS= read -r m; do printf \'=== %s ===\\n\' \\\"\\$m\\\"; if timeout 5 find \\\"\\$m\\\" -mindepth 1 -maxdepth 1 -print -quit >/dev/null 2>&1; then printf \'OK: каталог читается\\n\'; else printf \'ОШИБКА/ТАЙМАУТ: %s\\n\' \\\"\\$m\\\"; fi; done|journalctl -k -b --no-pager | grep -Ei \'cifs|smb\' | tail -120|sudo -u \'USER_NAME\' klist -A"\n',
    '            REC_CAUSE="CIFS смонтирован, но фактическое чтение каталога или metadata lookup завершились ошибкой/тайм-аутом. Для sec=krb5,multiuser результат проверяется в контексте активного локального GUI-пользователя, а не root."\n'
    '            REC_IMPACT="Caja/приложения могут зависать либо не открывать конкретную шару, даже если mount формально присутствует."\n'
    '            REC_CHECK="Сопоставить SOURCE → TARGET и статус конкретного SMB-ресурса. Проверка выполняет полный readdir каталога под timeout и stat одного элемента, поэтому она не ограничивается первым cached dentry."\n'
    '            REC_ACTION="Устранить фактическую сетевую, Kerberos/credential или I/O-причину. Размонтирование выполнять только после проверки открытых файлов и процессов."\n'
    '            REC_COMMAND="findmnt -t cifs -o TARGET,SOURCE,OPTIONS|journalctl -k -b --no-pager | grep -Ei \'cifs|smb\' | tail -120|sudo -u \'USER_NAME\' klist -A"\n',
    1
)
text = text.replace(
    '        findmnt\\ -n\\ -l\\ -t\\ cifs\\ -o\\ TARGET*) desc="автоматически проверит фактическое чтение каждого локального TARGET CIFS через find с таймаутом; SOURCE вида //server/share не используется" ;;',
    '        findmnt\\ -n\\ -l\\ -t\\ cifs\\ -o\\ TARGET*) desc="покажет локальные TARGET CIFS; arm_info дополнительно выполняет полный readdir и metadata lookup с таймаутом в пользовательском контексте для multiuser" ;;',
    1
)

arm.write_text(text, encoding="utf-8")

probe_test = r'''#!/usr/bin/env bash
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
'''
(root / 'tests/test_cifs_probe.sh').write_text(probe_test, encoding='utf-8')

field = root / 'tests/cifs_field_probe.sh'
f = field.read_text(encoding='utf-8')
f = f.replace(
    '    if ! have timeout || ! have find; then\n        PROBE_ERR=\'timeout/find отсутствует — безопасная проверка не выполнена\'\n',
    '    if ! have timeout || ! have ls || ! have find || ! have stat; then\n        PROBE_ERR=\'timeout/ls/find/stat отсутствует — безопасная проверка не выполнена\'\n',
    1
)
old_direct = '''    if [[ -n $as_user ]]; then
        if have runuser; then
            runuser -u "$as_user" -- env LC_ALL=C timeout "$TIMEOUT_SEC" \\
                find "$mnt" -mindepth 1 -maxdepth 1 -print -quit \\
                >/dev/null 2>"$errfile"
            PROBE_RC=$?
        elif have sudo; then
            sudo -n -u "$as_user" -- env LC_ALL=C timeout "$TIMEOUT_SEC" \\
                find "$mnt" -mindepth 1 -maxdepth 1 -print -quit \\
                >/dev/null 2>"$errfile"
            PROBE_RC=$?
        else
            PROBE_RC=125
            printf '%s\\n' 'runuser/sudo отсутствует — нет безопасного способа сменить UID' >"$errfile"
        fi
    else
        env LC_ALL=C timeout "$TIMEOUT_SEC" \\
            find "$mnt" -mindepth 1 -maxdepth 1 -print -quit \\
            >/dev/null 2>"$errfile"
        PROBE_RC=$?
    fi
'''
new_direct = '''    local -a prefix=()
    local samplefile sample
    if [[ -n $as_user ]]; then
        if have runuser; then prefix=(runuser -u "$as_user" --)
        elif have sudo; then prefix=(sudo -n -u "$as_user" --)
        else
            PROBE_RC=125
            printf '%s\\n' 'runuser/sudo отсутствует — нет безопасного способа сменить UID' >"$errfile"
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
'''
if old_direct not in f:
    raise SystemExit('field probe body not found')
f = f.replace(old_direct, new_direct, 1)
f = f.replace('Цель: отличить реальный timeout ресурса от ошибки пользовательского контекста', 'Цель: отличить реальный timeout/metadata failure ресурса от ошибки пользовательского контекста', 1)
field.write_text(f, encoding='utf-8')

ch = root / 'CHANGELOG.md'
c = ch.read_text(encoding='utf-8')
needle = '- Исправлена вторая полевая проблема CIFS: внутренний checker больше не разбирает `TARGET,SOURCE` через `awk` (что ломало TARGET с пробелами) и не использует `stat -f` как доказательство доступности. Каждый TARGET читается отдельно, через минимальный `find -print -quit` с timeout; при WARN в обычном режиме выводятся конкретные проблемные TARGET.\n'
addition = needle + '- Усилена полевая проверка CIFS после обнаружения ложного `OK`: `find -print -quit` мог завершиться после первого cached dentry. Теперь выполняются полный `readdir` каталога (`ls -U -A -1`) и `stat` одного элемента под timeout; для `sec=krb5,multiuser` root-запуск проверяет ресурс в контексте активного локального GUI-пользователя. В отчёте каждый SMB mount показывается отдельной строкой `SOURCE → TARGET` со статусом.\n'
if needle in c and 'cached dentry' not in c:
    c = c.replace(needle, addition, 1)
ch.write_text(c, encoding='utf-8')
