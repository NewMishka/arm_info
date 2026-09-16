from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "arm_info.sh"
text = SCRIPT.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {count}")
    text = text.replace(old, new, 1)


# Version markers inside the executable.
text = text.replace("1.2.1", "1.2.2")

# Clear the terminal before interactive enterprise text reports. Do this before
# tee redirection so escape/control sequences never enter a saved report or JSON.
old = '''else
    case "$PROFILE" in
        domain|network|print|software|enterprise) ;;
        "") echo "Ошибка: требуется --profile или --compare" >&2; usage >&2; exit 64 ;;
        *) echo "Ошибка: неизвестный профиль: $PROFILE" >&2; exit 64 ;;
    esac
fi

if [[ -n $OUTPUT_PATH ]]; then
'''
new = '''else
    case "$PROFILE" in
        domain|network|print|software|enterprise) ;;
        "") echo "Ошибка: требуется --profile или --compare" >&2; usage >&2; exit 64 ;;
        *) echo "Ошибка: неизвестный профиль: $PROFILE" >&2; exit 64 ;;
    esac
fi

# Интерактивный корпоративный TXT-отчёт начинает вывод с чистого экрана.
# JSON и --compare не получают управляющих последовательностей.
if ((JSON_MODE==0)) && [[ -z $COMPARE_A ]] && [[ -t 1 ]]; then
    if command -v clear >/dev/null 2>&1; then
        clear
    else
        printf '\\033[2J\\033[H'
    fi
fi

if [[ -n $OUTPUT_PATH ]]; then
'''
replace_once(old, new, "interactive clear")

# 802.1X recommendation: make the certificate-date check explicit.
old = '''            REC_COMMAND="nmcli -f NAME,TYPE,802-1x.eap,802-1x.ca-cert,802-1x.client-cert connection show|openssl x509 -in <CERT> -noout -subject -issuer -dates|journalctl -u NetworkManager -b --no-pager | grep -Ei '802.1x|eap|supplicant|certificate' | tail -120"'''
new = '''            REC_COMMAND="nmcli -f NAME,TYPE,802-1x.eap,802-1x.ca-cert,802-1x.client-cert connection show|openssl x509 -in \\\"<CERT>\\\" -noout -dates|openssl x509 -in \\\"<CERT>\\\" -noout -subject -issuer|journalctl -u NetworkManager -b --no-pager | grep -Ei '802.1x|eap|supplicant|certificate' | tail -120"'''
replace_once(old, new, "802.1X recommendation commands")

# Replace recommendation text rendering with UTF-8 aware alignment/wrapping and
# per-command explanations.
old = '''print_rec_field() {
    local label=$1 text=$2
    printf '   %-18s %s\\n' "$label" "$text"
}

print_rec_commands() {
    local text=$1 cmd first=1
    while IFS='|' read -r cmd; do
        [[ -n $cmd ]] || continue
        if ((first)); then printf '   %-18s %s\\n' 'Команды:' "$cmd"; first=0
        else printf '   %-18s %s\\n' '' "$cmd"; fi
    done <<<"${text//|/$'\\n'}"
}
'''
new = r'''report_width() {
    local cols=${COLUMNS:-}
    if [[ ! $cols =~ ^[0-9]+$ ]] && command -v tput >/dev/null 2>&1; then
        cols=$(tput cols 2>/dev/null || true)
    fi
    [[ $cols =~ ^[0-9]+$ ]] || cols=110
    ((cols<86)) && cols=86
    ((cols>132)) && cols=132
    printf '%d' "$cols"
}

repeat_char() {
    local count=$1 char=${2:--}
    printf '%*s' "$count" '' | tr ' ' "$char"
}

pad_right() {
    local value=$1 width=$2 len=${#1}
    printf '%s' "$value"
    ((len<width)) && printf '%*s' "$((width-len))" ''
}

print_check_row() {
    local label=$1 status=$2 value=$3 total label_w=31 status_w=9 gap=2 value_w i max
    local -a label_lines=() value_lines=()
    total=$(report_width)
    ((total<96)) && label_w=27
    value_w=$((total-label_w-status_w-(gap*2)))
    ((value_w<24)) && value_w=24

    mapfile -t label_lines < <(printf '%s\n' "$label" | fold -s -w "$label_w")
    mapfile -t value_lines < <(printf '%s\n' "$value" | fold -s -w "$value_w")
    ((${#label_lines[@]})) || label_lines=("")
    ((${#value_lines[@]})) || value_lines=("")
    max=${#label_lines[@]}; ((${#value_lines[@]}>max)) && max=${#value_lines[@]}

    for ((i=0; i<max; i++)); do
        local l=${label_lines[i]:-} s='' v=${value_lines[i]:-}
        ((i==0)) && s=$status
        printf '%s%*s%s%*s%s\n' \
            "$(pad_right "$l" "$label_w")" "$gap" '' \
            "$(pad_right "$s" "$status_w")" "$gap" '' "$v"
    done
}

print_rec_field() {
    local label=$1 text=$2 total label_w=23 indent=3 gap=1 value_w i=0 line
    total=$(report_width)
    value_w=$((total-indent-label_w-gap))
    ((value_w<32)) && value_w=32
    while IFS= read -r line || [[ -n $line ]]; do
        if ((i==0)); then
            printf '%*s%s %s\n' "$indent" '' "$(pad_right "$label" "$label_w")" "$line"
        else
            printf '%*s%s %s\n' "$indent" '' "$(pad_right '' "$label_w")" "$line"
        fi
        i=$((i+1))
    done < <(printf '%s\n' "$text" | fold -s -w "$value_w")
    ((i>0)) || printf '%*s%s\n' "$indent" '' "$label"
}

command_description() {
    local cmd=$1
    case "$cmd" in
        realm\ list*) echo "покажет параметры присоединения к realm/домену" ;;
        sssctl\ domain-list*) echo "покажет домены, которые видит SSSD" ;;
        sssctl\ config-check*) echo "проверит конфигурацию SSSD на синтаксические ошибки" ;;
        hostname\ -f*) echo "покажет полное доменное имя АРМ" ;;
        *sssd.conf*) echo "покажет доменные секции конфигурации SSSD" ;;
        systemctl\ status\ sssd*) echo "покажет состояние службы SSSD и последнюю причину отказа" ;;
        systemctl\ status\ cups*) echo "покажет состояние службы CUPS и последнюю причину отказа" ;;
        journalctl*-u\ sssd*) echo "покажет события SSSD текущей загрузки для поиска первичной ошибки" ;;
        journalctl*-u\ NetworkManager*) echo "покажет ошибки NetworkManager/802.1X/EAP текущей загрузки" ;;
        journalctl*-u\ cups*) echo "покажет ошибки и события CUPS текущей загрузки" ;;
        journalctl*-k*) echo "покажет сообщения ядра, связанные с устройствами/сетевыми файловыми системами" ;;
        journalctl*) echo "покажет системные события, относящиеся к диагностируемой проблеме" ;;
        adcli\ testjoin*) echo "проверит доверительные отношения машинной учётной записи с AD" ;;
        timedatectl*) echo "покажет системное время, часовой пояс и состояние синхронизации" ;;
        chronyc\ tracking*) echo "покажет текущий offset и качество синхронизации времени" ;;
        chronyc\ sources*) echo "покажет доступные и выбранный источники времени" ;;
        dig*) echo "покажет DNS/SRV-записи, необходимые для поиска доменных служб" ;;
        host*) echo "выполнит DNS-проверку указанного имени/записи" ;;
        klist*) echo "покажет Kerberos cache, principal и сроки действия билетов" ;;
        find\ /tmp*krb5cc*) echo "найдёт файловые Kerberos cache на АРМ" ;;
        resolvectl*) echo "покажет фактические DNS-серверы и настройки systemd-resolved" ;;
        nmcli*-f*802-1x*) echo "покажет параметры 802.1X активных/сохранённых профилей NetworkManager" ;;
        nmcli*) echo "покажет состояние сетевых устройств и профилей NetworkManager" ;;
        openssl\ x509*-dates*) echo "покажет даты начала и окончания действия сертификата" ;;
        openssl\ x509*) echo "покажет сведения X.509: субъект, издатель и параметры сертификата" ;;
        getent*) echo "проверит разрешение имени через системные NSS/DNS-настройки" ;;
        ip\ -br\ link*) echo "покажет краткое состояние сетевых интерфейсов и link" ;;
        ip\ -br\ addr*) echo "покажет краткий список адресов сетевых интерфейсов" ;;
        ip\ -4\ route*) echo "покажет IPv4-маршруты и шлюз по умолчанию" ;;
        findmnt*) echo "покажет активные точки монтирования и их параметры" ;;
        timeout*stat*) echo "проверит доступность точки монтирования с ограничением времени ожидания" ;;
        gio\ mount*) echo "покажет пользовательские GVFS/GIO-подключения" ;;
        ps*) echo "покажет процессы и позволит определить зависший/родительский процесс" ;;
        find\ /run/user*) echo "покажет пользовательские GVFS-точки монтирования" ;;
        lpstat\ -r*) echo "проверит, отвечает ли планировщик CUPS" ;;
        lpstat*) echo "покажет очереди, задания, принтер по умолчанию и backend CUPS" ;;
        cupsctl*) echo "покажет текущие параметры сервера CUPS" ;;
        cupsenable*) echo "возобновит указанную очередь после устранения первичной причины" ;;
        cupsaccept*) echo "разрешит указанной очереди принимать новые задания" ;;
        cancel*) echo "отменит указанное задание печати; выполнять только после подтверждения" ;;
        du\ -sh\ /var/spool/cups*) echo "покажет объём диска, занятый spool CUPS" ;;
        command\ -v*) echo "проверит наличие требуемой диагностической утилиты" ;;
        rpm*) echo "покажет сведения RPM или пакет, которому принадлежит файл" ;;
        dnf*) echo "покажет пакет/провайдера требуемой утилиты в репозиториях" ;;
        arm_info*) echo "повторно запустит профиль arm_info для контроля после исправления" ;;
        *) echo "выполнит диагностическую проверку, связанную с указанной рекомендацией" ;;
    esac
}

print_rec_commands() {
    local text=$1 cmd desc idx=0
    while IFS='|' read -r cmd; do
        [[ -n $cmd ]] || continue
        idx=$((idx+1))
        desc=$(command_description "$cmd")
        print_rec_field "Команда $idx:" "$cmd ($desc)"
    done <<<"${text//|/$'\n'}"
}
'''
replace_once(old, new, "recommendation formatting")

# Replace the whole network profile so the 802.1X block exposes profile/EAP,
# certificate paths, validity dates and the exact openssl dates check.
pattern = re.compile(r'check_network\(\) \{.*?\n\}\n\ncheck_print\(\) \{', re.S)
match = pattern.search(text)
if not match:
    raise SystemExit("check_network block not found")
new_network = r'''check_network() {
    local gw ifaces idx=0 row iface ip mac speed duplex link dns_domain cifs_count=0 cifs_bad=0 mnt src gvfs_count=0 gvfs_bad=0 g dir
    local eap_count=0 cert_global_min=-1 cert_unknown=0 cert_seen=0 cert_index=0 uuid type eap conn_name ca_cert client_cert cert_kind certpath cert_display cert_label
    local cert_start cert_end start_fmt end_fmt end_epoch now days cert_cmd_path sev proc_caja proc_gvfs

    gw=$(ip -4 route show default 2>/dev/null | awk 'NR==1{print $3}')
    [[ -n $gw ]] && add_check "СЕТЬ" "network.gateway" "Шлюз" "$(mask_ipv4 "$gw")" ok || add_check "СЕТЬ" "network.gateway" "Шлюз" "не найден" warn

    ifaces=$(ip -4 -o addr show up 2>/dev/null | awk '$2!="lo"{print $2"|"$4}' | sort -u)
    if [[ -z $ifaces ]]; then add_check "СЕТЬ" "network.interfaces" "Активные IPv4" "нет" crit
    else
        while IFS='|' read -r iface ip; do
            [[ -n $iface ]] || continue; idx=$((idx+1)); ip=${ip%%/*}
            mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null || printf '-')
            speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null || true); duplex=$(cat "/sys/class/net/$iface/duplex" 2>/dev/null || true)
            if [[ $speed =~ ^[0-9]+$ ]] && ((speed>0)); then link="${speed} Mbit/s / ${duplex:-?}"; else link="скорость не определена"; fi
            if ((PRIVACY)); then mac='xx:xx:xx:xx:xx:xx'; fi
            add_check "СЕТЬ" "network.iface.$idx" "Интерфейс $idx" "$(mask_iface "$idx" "$iface") | $(mask_ipv4 "$ip") | $mac | $link" ok
        done <<<"$ifaces"
    fi

    dns_domain=$(_detect_domain); check_dns_common "DNS" "$dns_domain"

    if have nmcli; then
        while IFS=: read -r uuid type; do
            [[ -n $uuid ]] || continue
            case "$type" in ethernet|802-11-wireless|wifi) ;; *) continue;; esac
            eap=$(nmcli -g 802-1x.eap connection show uuid "$uuid" 2>/dev/null | head -n1)
            [[ -n $eap ]] || continue

            eap_count=$((eap_count+1))
            conn_name=$(nmcli -g connection.id connection show uuid "$uuid" 2>/dev/null | head -n1)
            if ((PRIVACY)); then conn_name="профиль $eap_count (скрыто)"; fi
            add_check "802.1X" "network.8021x.profile.$eap_count" "Профиль 802.1X #$eap_count" "${conn_name:-$uuid}" info
            add_check "802.1X" "network.8021x.eap.$eap_count" "EAP-метод" "$eap" info

            ca_cert=$(nmcli -g 802-1x.ca-cert connection show uuid "$uuid" 2>/dev/null | head -n1)
            client_cert=$(nmcli -g 802-1x.client-cert connection show uuid "$uuid" 2>/dev/null | head -n1)

            for cert_kind in client ca; do
                if [[ $cert_kind == client ]]; then
                    certpath=$client_cert; cert_label="Клиентский сертификат"
                else
                    certpath=$ca_cert; cert_label="CA-сертификат"
                fi
                [[ -n $certpath ]] || continue
                cert_seen=$((cert_seen+1)); cert_index=$((cert_index+1))
                certpath=${certpath#file://}
                cert_display=$certpath
                if ((PRIVACY)); then
                    [[ $cert_kind == client ]] && cert_display='<CLIENT_CERT>' || cert_display='<CA_CERT>'
                fi
                add_check "802.1X" "network.8021x.cert.$cert_index.path" "$cert_label" "$cert_display" info

                if [[ -r $certpath ]] && have openssl; then
                    cert_start=$(openssl x509 -in "$certpath" -noout -startdate 2>/dev/null | sed 's/^notBefore=//')
                    cert_end=$(openssl x509 -in "$certpath" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')
                    start_fmt=$(date -d "$cert_start" '+%d.%m.%Y %H:%M:%S %Z' 2>/dev/null || printf '%s' "$cert_start")
                    end_fmt=$(date -d "$cert_end" '+%d.%m.%Y %H:%M:%S %Z' 2>/dev/null || printf '%s' "$cert_end")
                    end_epoch=$(date -d "$cert_end" +%s 2>/dev/null || true); now=$(date +%s)
                    if [[ $end_epoch =~ ^[0-9]+$ ]]; then
                        days=$(((end_epoch-now)/86400))
                        ((cert_global_min<0 || days<cert_global_min)) && cert_global_min=$days
                        if ((days<14)); then sev=crit; elif ((days<30)); then sev=warn; else sev=ok; fi
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Срок действия" "$start_fmt — $end_fmt; осталось ${days} дн." info
                    else
                        cert_unknown=$((cert_unknown+1))
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Срок действия" "не удалось вычислить; notBefore=$cert_start; notAfter=$cert_end" info
                    fi
                    cert_cmd_path=$certpath; ((PRIVACY)) && cert_cmd_path='<CERT>'
                    add_check "802.1X" "network.8021x.cert.$cert_index.command" "Проверка срока" "openssl x509 -in \\\"$cert_cmd_path\\\" -noout -dates" info
                else
                    cert_unknown=$((cert_unknown+1))
                    if ! have openssl; then
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Срок действия" "не проверен: openssl отсутствует" info
                    else
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Срок действия" "не проверен: файл сертификата недоступен" info
                    fi
                fi
            done
        done < <(nmcli -t -f UUID,TYPE connection show --active 2>/dev/null)

        if ((eap_count>0)); then
            if ((cert_global_min>=0)); then
                if ((cert_global_min<14)); then sev=crit
                elif ((cert_global_min<30)); then sev=warn
                elif ((cert_unknown>0)); then sev=warn
                else sev=ok
                fi
                add_check "802.1X" "network.8021x" "Активные 802.1X" "$eap_count; минимальный остаток сертификата ${cert_global_min} дн.; непроверенных: $cert_unknown" "$sev"
            elif ((cert_seen>0)); then
                add_check "802.1X" "network.8021x" "Активные 802.1X" "$eap_count; срок сертификатов не определён" unknown
            else
                add_check "802.1X" "network.8021x" "Активные 802.1X" "$eap_count; пути сертификатов в активном профиле не обнаружены" unknown
            fi
        else
            add_check "802.1X" "network.8021x" "Активные 802.1X" "не обнаружены" info
        fi
    else
        add_check "802.1X" "network.8021x" "802.1X" "nmcli отсутствует" unknown
    fi

    if have findmnt; then
        while IFS='|' read -r mnt src; do
            [[ -n $mnt ]] || continue; cifs_count=$((cifs_count+1))
            if run_timeout 4 stat -f "$mnt" >/dev/null 2>&1; then :; else cifs_bad=$((cifs_bad+1)); fi
        done < <(findmnt -rn -t cifs -o TARGET,SOURCE 2>/dev/null | awk '{print $1"|"$2}')
        if ((cifs_count==0)); then add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "нет" info
        elif ((cifs_bad==0)); then add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "$cifs_count, доступны" ok
        else add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "$cifs_count, недоступны/зависли: $cifs_bad" warn; fi
    else add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "findmnt отсутствует" unknown; fi

    for g in /run/user/*/gvfs; do
        [[ -d $g ]] || continue
        while IFS= read -r dir; do
            [[ -n $dir ]] || continue; gvfs_count=$((gvfs_count+1))
            if run_timeout 4 stat -f "$dir" >/dev/null 2>&1; then :; else gvfs_bad=$((gvfs_bad+1)); fi
        done < <(find "$g" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    done
    if ((gvfs_count==0)); then add_check "SMB / GVFS" "network.gvfs" "GVFS mounts" "нет" info
    elif ((gvfs_bad==0)); then add_check "SMB / GVFS" "network.gvfs" "GVFS mounts" "$gvfs_count, доступны" ok
    else add_check "SMB / GVFS" "network.gvfs" "GVFS mounts" "$gvfs_count, недоступны/зависли: $gvfs_bad" warn; fi
    proc_caja=$(pgrep -xc caja 2>/dev/null || true); proc_gvfs=$(pgrep -fc 'gvfsd-smb|gvfsd-fuse' 2>/dev/null || true)
    add_check "SMB / GVFS" "network.desktop" "Caja / GVFS процессы" "caja:$proc_caja gvfs:$proc_gvfs" ok
}

check_print() {'''
text = text[:match.start()] + new_network + text[match.end():]

# Replace enterprise text output with explicit columns and wrapping.
pattern = re.compile(r'emit_text\(\) \{.*?\n\}\n\nemit_json\(\) \{', re.S)
match = pattern.search(text)
if not match:
    raise SystemExit("emit_text block not found")
new_emit = r'''emit_text() {
    local current="" i sevmark n=0 width
    width=$(report_width)
    printf 'ARM_INFO ENTERPRISE %s\n' "$VERSION"
    printf 'Профиль: %s\n' "$PROFILE"
    printf 'Дата: %s\n' "$(date '+%d.%m.%Y %H:%M:%S')"
    ((PRIVACY)) && printf 'Privacy: включён\n'

    for i in "${!KEYS[@]}"; do
        if [[ ${SECTIONS[i]} != "$current" ]]; then
            current=${SECTIONS[i]}
            printf '\n%s\n' "$current"
            repeat_char "$width" '-'; printf '\n'
            print_check_row 'Параметр' 'Статус' 'Значение'
            repeat_char "$width" '-'; printf '\n'
        fi
        case "${SEVERITIES[i]}" in ok) sevmark='[OK]';; info) sevmark='[INFO]';; warn) sevmark='[WARN]';; crit) sevmark='[CRIT]';; *) sevmark='[N/A]';; esac
        print_check_row "${LABELS[i]}" "$sevmark" "${VALUES[i]}"
        [[ -n ${DETAILS[i]} ]] && print_check_row 'Примечание' '' "${DETAILS[i]}"
    done

    printf '\nСВОДКА\n'; repeat_char "$width" '-'; printf '\n'
    print_check_row 'Показатель' '' 'Количество'
    repeat_char "$width" '-'; printf '\n'
    print_check_row 'Критично' '' "$CRIT_COUNT"
    print_check_row 'Предупреждения' '' "$WARN_COUNT"
    print_check_row 'Неполные проверки' '' "$UNKNOWN_COUNT"

    printf '\nРЕКОМЕНДАЦИИ\n'; repeat_char "$width" '-'; printf '\n'
    if ((${#REC_KEYS[@]}==0)); then
        print_rec_field 'Статус:' 'Дополнительных действий по выбранному профилю не требуется.'
    else
        for i in "${!REC_KEYS[@]}"; do
            n=$((n+1))
            printf '\n'
            print_rec_field "$n. [${REC_LEVELS[i]}]" "${REC_TITLES[i]}"
            print_rec_field 'Источник:' "${REC_SOURCES[i]}"
            print_rec_field 'Возможные причины:' "${REC_CAUSES[i]}"
            print_rec_field 'Влияние:' "${REC_IMPACTS[i]}"
            print_rec_field 'Что проверить:' "${REC_CHECKS[i]}"
            print_rec_field 'Действие:' "${REC_ACTIONS[i]}"
            print_rec_commands "${REC_COMMANDS[i]}"
            print_rec_field 'Контроль результата:' "${REC_VERIFIES[i]}"
        done
    fi
}

emit_json() {'''
text = text[:match.start()] + new_emit + text[match.end():]

SCRIPT.write_text(text, encoding="utf-8")

# VERSION
(ROOT / "VERSION").write_text("1.2.2\n", encoding="utf-8")

# RPM spec
spec_path = ROOT / "packaging/arm_info.spec"
spec = spec_path.read_text(encoding="utf-8")
spec = spec.replace("Version:        1.2.1", "Version:        1.2.2", 1)
changelog_marker = "%changelog\n"
entry = "* Wed Sep 16 2026 NewMishka - 1.2.2-1\n- Aligned/wrapped enterprise report, expanded 802.1X certificate diagnostics\n- Command explanations and interactive screen clear for corporate profiles\n\n"
if entry not in spec:
    spec = spec.replace(changelog_marker, changelog_marker + entry, 1)
spec_path.write_text(spec, encoding="utf-8")

# README
readme_path = ROOT / "README.md"
readme = readme_path.read_text(encoding="utf-8")
readme = readme.replace("Начиная с версии **1.2.1**", "Начиная с версии **1.2.2**", 1)
readme = readme.replace("`arm_info 1.2.1` содержит", "`arm_info 1.2.2` содержит", 1)
readme = readme.replace("Текущая версия: **1.2.1**.", "Текущая версия: **1.2.2**.", 1)
anchor = "`--corp` запускает `domain + network + print` и **не выполняет глобальную инвентаризацию ПО**, поэтому отчёт не раздувается сотнями строк.\n"
addition = "\nВ **1.2.2** текстовый корпоративный отчёт выровнен по колонкам и аккуратно переносит длинные значения. Блок `802.1X` показывает активный профиль, EAP-метод, пути клиентского/CA-сертификата, даты действия и готовую проверку `openssl x509 -in \"<CERT>\" -noout -dates`. Перед интерактивным TXT-выводом экран очищается; JSON остаётся чистым. Команды в рекомендациях сопровождаются пояснением в скобках, что именно даст каждая команда.\n"
if addition.strip() not in readme:
    readme = readme.replace(anchor, anchor + addition, 1)
readme_path.write_text(readme, encoding="utf-8")

# Enterprise documentation
doc_path = ROOT / "docs/ENTERPRISE_PROFILES.md"
doc = doc_path.read_text(encoding="utf-8")
old_802 = "- активные NetworkManager 802.1X-профили;\n- сроки доступных CA/client certificates 802.1X;"
new_802 = "- активные NetworkManager 802.1X-профили и EAP-метод;\n- пути клиентского и CA-сертификата 802.1X;\n- даты начала/окончания действия сертификатов и остаток в днях;\n- готовую команду проверки срока `openssl x509 -in \"<CERT>\" -noout -dates`;"
doc = doc.replace(old_802, new_802, 1)
format_note = "\nНачиная с **1.2.2**, TXT-отчёт enterprise-профилей выводится в выровненных колонках, длинные значения и рекомендации переносятся по ширине терминала. Для каждой команды в рекомендациях в скобках выводится краткое объяснение результата команды. При интерактивном TXT-запуске корпоративного профиля экран предварительно очищается; JSON/файловый вывод не загрязняется управляющими последовательностями.\n"
if format_note.strip() not in doc:
    doc = doc.replace("## Профили\n", format_note + "\n## Профили\n", 1)
doc_path.write_text(doc, encoding="utf-8")

# Changelog
chg_path = ROOT / "CHANGELOG.md"
chg = chg_path.read_text(encoding="utf-8")
section = """## 1.2.2 — 2026-09-16

### Changed
- Корпоративный TXT-отчёт выровнен по явным колонкам `Параметр / Статус / Значение`.
- Длинные значения, примечания и рекомендации переносятся по ширине терминала без разрушения структуры отчёта.
- Блок 802.1X показывает профиль, EAP, клиентский/CA-сертификат, даты действия, остаток срока и команду `openssl x509 -in \"<CERT>\" -noout -dates`.
- Каждая команда в рекомендациях получает пояснение в скобках, что именно она покажет или изменит.
- Интерактивный корпоративный TXT-отчёт очищает экран перед выводом; JSON остаётся без управляющих последовательностей.

"""
if "## 1.2.2 — 2026-09-16" not in chg:
    chg = chg.replace("# Changelog\n\n", "# Changelog\n\n" + section, 1)
chg_path.write_text(chg, encoding="utf-8")

# Release notes
release = ROOT / "docs/releases/v1.2.2.md"
release.write_text("""# arm_info 1.2.2

Улучшение читаемости корпоративной диагностики и блока 802.1X.

- корпоративный TXT-отчёт получил выровненные колонки `Параметр / Статус / Значение`;
- длинные строки и рекомендации переносятся по ширине терминала;
- блок 802.1X показывает активный профиль, EAP, пути client/CA certificates, даты действия и остаток срока;
- в блоке 802.1X выводится готовая проверка `openssl x509 -in \"<CERT>\" -noout -dates`;
- команды в рекомендациях выровнены и снабжены пояснением в скобках;
- интерактивный `--corp` очищает экран перед TXT-выводом;
- JSON не получает escape/control sequences и остаётся пригодным для автоматизации;
- глобальная инвентаризация ПО по-прежнему запускается только отдельно через `--profile software`.

Практический запуск:

```bash
sudo bash /tmp/arm_info.sh --corp
```

Обезличенный JSON:

```bash
sudo bash /tmp/arm_info.sh --corp --privacy --json -o /tmp/arm-corp.json
```
""", encoding="utf-8")

# Tests: preserve behavioral tests and add guards for the new report contract.
test_path = ROOT / "tests/test_enterprise.sh"
test = test_path.read_text(encoding="utf-8")
extra = r'''
# v1.2.2 text-report contract.
grep -q "print_check_row 'Параметр' 'Статус' 'Значение'" "$SCRIPT" || die "enterprise column header"
grep -q 'openssl x509 -in' "$SCRIPT" || die "802.1X certificate date command"
grep -q 'покажет даты начала и окончания действия сертификата' "$SCRIPT" || die "command explanations"
grep -q 'JSON_MODE==0' "$SCRIPT" || die "interactive clear guard"
'''
if "# v1.2.2 text-report contract." not in test:
    test += extra

test_path.write_text(test, encoding="utf-8")
