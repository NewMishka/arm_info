#!/usr/bin/env bash
# arm_info enterprise profiles — v1.2.0
# Read-only diagnostics for RED OS enterprise workstations.
set -u
set -o pipefail

VERSION="1.2.0"
PROFILE=""
PRIVACY=0
JSON_MODE=0
OUTPUT_PATH=""
COMPARE_A=""
COMPARE_B=""

usage() {
    cat <<'USAGE'
arm_info enterprise profiles 1.2.0

Использование:
  arm_info --profile domain [--privacy] [--json] [-o FILE]
  arm_info --profile network [--privacy] [--json] [-o FILE]
  arm_info --profile print [--privacy] [--json] [-o FILE]
  arm_info --profile software [--privacy] [--json] [-o FILE]
  arm_info --profile enterprise [--privacy] [--json] [-o FILE]
  arm_info --compare REPORT_A.json REPORT_B.json [--json] [-o FILE]

Профили:
  domain       AD/SSSD/Kerberos, DNS SRV, KDC/LDAP, синхронизация времени
  network      DNS, интерфейсы, 802.1X, CIFS/SMB, GVFS/Caja
  print        CUPS, очереди, задания, backend URI, ошибки журнала
  software     версии корпоративного ПО и проблемные процессы
  enterprise   domain + network + print + software

Коды завершения:
  0  проблем не обнаружено
  1  есть предупреждения / для compare найдены отличия
  2  обнаружено критическое отклонение
  3  проверка неполная (нет части утилит/данных), критичных отклонений нет
  64 ошибка CLI
USAGE
}

while (($#)); do
    case "$1" in
        --profile)
            [[ $# -ge 2 ]] || { echo "Ошибка: --profile требует значение" >&2; exit 64; }
            PROFILE=$2; shift 2 ;;
        --profile=*) PROFILE=${1#*=}; shift ;;
        --compare)
            [[ $# -ge 3 ]] || { echo "Ошибка: --compare требует два JSON-файла" >&2; exit 64; }
            COMPARE_A=$2; COMPARE_B=$3; shift 3 ;;
        --privacy) PRIVACY=1; shift ;;
        --json) JSON_MODE=1; shift ;;
        -o|--output)
            [[ $# -ge 2 ]] || { echo "Ошибка: $1 требует путь" >&2; exit 64; }
            OUTPUT_PATH=$2; shift 2 ;;
        -V|--version) echo "arm_info enterprise $VERSION"; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        *) echo "Ошибка: неизвестный параметр: $1" >&2; usage >&2; exit 64 ;;
    esac
done

if [[ -n $COMPARE_A || -n $COMPARE_B ]]; then
    [[ -n $COMPARE_A && -n $COMPARE_B ]] || { echo "Ошибка: укажите два файла для сравнения" >&2; exit 64; }
else
    case "$PROFILE" in
        domain|network|print|software|enterprise) ;;
        "") echo "Ошибка: требуется --profile или --compare" >&2; usage >&2; exit 64 ;;
        *) echo "Ошибка: неизвестный профиль: $PROFILE" >&2; exit 64 ;;
    esac
fi

if [[ -n $OUTPUT_PATH ]]; then
    OUTDIR=$(dirname -- "$OUTPUT_PATH")
    [[ -d $OUTDIR && -w $OUTDIR ]] || { echo "Ошибка: каталог для отчёта недоступен: $OUTDIR" >&2; exit 73; }
    exec > >(tee "$OUTPUT_PATH")
fi

have() { command -v "$1" >/dev/null 2>&1; }
run_timeout() {
    local sec=$1; shift
    if have timeout; then timeout "$sec" "$@"; else "$@"; fi
}
trim() { sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }
join_by() { local IFS=$1; shift; printf '%s' "$*"; }

mask_ipv4() {
    local ip=$1
    if ((PRIVACY==0)); then printf '%s' "$ip"; return; fi
    if [[ $ip =~ ^([0-9]{1,3})\.([0-9]{1,3})\. ]]; then printf '%s.%s.x.x' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"; else printf 'скрыто'; fi
}
mask_domain() { if ((PRIVACY)); then printf 'скрыто'; else printf '%s' "$1"; fi; }
mask_host() { if ((PRIVACY)); then printf 'ARM-REDACTED'; else printf '%s' "$1"; fi; }
mask_iface() { if ((PRIVACY)); then printf 'net%s' "$1"; else printf '%s' "$2"; fi; }
sanitize_uri() {
    local u=$1
    u=$(printf '%s' "$u" | sed -E 's#(://)[^/@:]+:[^/@]+@#\1***:***@#')
    if ((PRIVACY)); then
        u=$(printf '%s' "$u" | sed -E 's#(://)([^/@]+@)?[^/:]+#\1\2host-redacted#')
    fi
    printf '%s' "$u"
}

KEYS=(); LABELS=(); VALUES=(); SEVERITIES=(); SECTIONS=(); DETAILS=()
WARN_COUNT=0; CRIT_COUNT=0; UNKNOWN_COUNT=0
add_check() {
    local section=$1 key=$2 label=$3 value=$4 severity=${5:-ok} detail=${6:-}
    KEYS+=("$key"); LABELS+=("$label"); VALUES+=("$value"); SEVERITIES+=("$severity"); SECTIONS+=("$section"); DETAILS+=("$detail")
    case "$severity" in warn) WARN_COUNT=$((WARN_COUNT+1));; crit) CRIT_COUNT=$((CRIT_COUNT+1));; unknown) UNKNOWN_COUNT=$((UNKNOWN_COUNT+1));; esac
}

json_escape() {
    local s=${1-}
    s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

_detect_domain() {
    local d=""
    if have realm; then d=$(realm list --name-only 2>/dev/null | head -n1 | trim); fi
    if [[ -z $d ]] && have sssctl; then d=$(sssctl domain-list 2>/dev/null | head -n1 | trim); fi
    if [[ -z $d && -r /etc/sssd/sssd.conf ]]; then d=$(awk -F'[/\]]' '/^[[:space:]]*\[domain\//{print $2; exit}' /etc/sssd/sssd.conf 2>/dev/null | trim); fi
    if [[ -z $d ]]; then d=$(hostname -d 2>/dev/null | trim); fi
    printf '%s' "$d"
}

_dns_upstreams() {
    local vals=""
    if have resolvectl; then
        vals=$(resolvectl dns 2>/dev/null | awk -F: 'NF>1{print $2}' | xargs -n1 2>/dev/null | grep -E '^[0-9a-fA-F:.]+$' | sort -u | paste -sd, -)
    fi
    if [[ -z $vals ]] && have nmcli; then
        vals=$(nmcli -t -f IP4.DNS device show 2>/dev/null | cut -d: -f2- | grep -v '^$' | sort -u | paste -sd, -)
    fi
    if [[ -z $vals ]]; then vals=$(awk '/^[[:space:]]*nameserver[[:space:]]+/{print $2}' /etc/resolv.conf 2>/dev/null | sort -u | paste -sd, -); fi
    printf '%s' "$vals"
}

_srv_records() {
    local name=$1
    if have dig; then dig +time=2 +tries=1 +short "$name" SRV 2>/dev/null
    elif have host; then host -W 2 -t SRV "$name" 2>/dev/null | awk '/has SRV record/{print $(NF-3),$(NF-2),$(NF-1),$NF}'
    fi
}

_tcp_ok() {
    local host=$1 port=$2
    host=${host%.}
    if have nc; then run_timeout 3 nc -z "$host" "$port" >/dev/null 2>&1
    elif have timeout; then timeout 3 bash -c "</dev/null >/dev/tcp/$host/$port" >/dev/null 2>&1
    else return 2
    fi
}

check_dns_common() {
    local section=${1:-DNS} domain=${2:-} resolv_target manager dns search_domain fqdn rc ldap_srv krb_srv ldap_count krb_count targets target reachable=0 tested=0
    resolv_target=$(readlink -f /etc/resolv.conf 2>/dev/null || printf '/etc/resolv.conf')
    case "$resolv_target" in
        *systemd/resolve*) manager="systemd-resolved" ;;
        *NetworkManager*) manager="NetworkManager" ;;
        *) if have nmcli; then manager="NetworkManager/статический"; else manager="статический/не определён"; fi ;;
    esac
    add_check "$section" "dns.manager" "Управление DNS" "$manager" ok "$resolv_target"

    dns=$(_dns_upstreams)
    if [[ -z $dns ]]; then
        add_check "$section" "dns.servers" "DNS-серверы" "не определены" crit
    else
        if ((PRIVACY)); then add_check "$section" "dns.servers" "DNS-серверы" "$(awk -F, '{print NF}' <<<"$dns") сервер(а), скрыто" ok
        else add_check "$section" "dns.servers" "DNS-серверы" "$dns" ok; fi
    fi

    if grep -Eq '^[[:space:]]*nameserver[[:space:]]+127\.0\.0\.53([[:space:]]|$)' /etc/resolv.conf 2>/dev/null; then
        if [[ -n $dns && $dns != "127.0.0.53" ]]; then add_check "$section" "dns.stub" "127.0.0.53 stub" "есть, upstream определён" ok
        else add_check "$section" "dns.stub" "127.0.0.53 stub" "есть, upstream не найден" warn "Проверьте resolvectl dns / NetworkManager"; fi
    fi

    search_domain=$(awk '/^[[:space:]]*(search|domain)[[:space:]]+/{for(i=2;i<=NF;i++)print $i}' /etc/resolv.conf 2>/dev/null | head -n1)
    [[ -z $search_domain ]] && search_domain=$domain
    if [[ -n $search_domain ]]; then add_check "$section" "dns.search" "DNS suffix/search" "$(mask_domain "$search_domain")" ok
    else add_check "$section" "dns.search" "DNS suffix/search" "не определён" unknown; fi

    fqdn=$(hostname -f 2>/dev/null || true)
    if [[ -n $fqdn && $fqdn != "localhost" ]]; then
        if getent ahostsv4 "$fqdn" >/dev/null 2>&1 || getent hosts "$fqdn" >/dev/null 2>&1; then rc=ok; else rc=warn; fi
        add_check "$section" "dns.fqdn" "Разрешение FQDN" "$(mask_host "$fqdn")" "$rc"
    else add_check "$section" "dns.fqdn" "Разрешение FQDN" "FQDN не определён" warn; fi

    if [[ -n $domain ]]; then
        ldap_srv=$(_srv_records "_ldap._tcp.$domain")
        krb_srv=$(_srv_records "_kerberos._tcp.$domain")
        ldap_count=$(grep -c . <<<"$ldap_srv" 2>/dev/null || true); krb_count=$(grep -c . <<<"$krb_srv" 2>/dev/null || true)
        if ((ldap_count>0)); then add_check "$section" "dns.srv.ldap" "LDAP SRV" "$ldap_count записей" ok; else add_check "$section" "dns.srv.ldap" "LDAP SRV" "не найден" warn; fi
        if ((krb_count>0)); then add_check "$section" "dns.srv.kerberos" "Kerberos SRV" "$krb_count записей" ok; else add_check "$section" "dns.srv.kerberos" "Kerberos SRV" "не найден" warn; fi

        targets=$(printf '%s\n%s\n' "$ldap_srv" "$krb_srv" | awk 'NF{print $NF}' | sed 's/\.$//' | sort -u | head -n3)
        while IFS= read -r target; do
            [[ -n $target ]] || continue
            for port in 88 389; do
                if _tcp_ok "$target" "$port"; then reachable=$((reachable+1)); fi
                tested=$((tested+1))
            done
        done <<<"$targets"
        if ((tested>0)); then
            if ((reachable==tested)); then rc=ok; elif ((reachable>0)); then rc=warn; else rc=crit; fi
            add_check "$section" "domain.dc.ports" "KDC/LDAP доступность" "$reachable из $tested TCP-проверок" "$rc"
        else
            add_check "$section" "domain.dc.ports" "KDC/LDAP доступность" "не проверена" unknown "Нужны SRV-записи и nc/timeout"
        fi
    else
        add_check "$section" "dns.srv" "Доменные SRV" "домен не определён" unknown
    fi
}

check_domain() {
    local d sssd_state join_state kstate cache_count sync_state chrony sssd_logs c6 c7 c15 sev
    d=$(_detect_domain)
    if [[ -n $d ]]; then add_check "ДОМЕН / KERBEROS" "domain.name" "Домен" "$(mask_domain "$d")" ok
    else add_check "ДОМЕН / KERBEROS" "domain.name" "Домен" "не определён" warn; fi

    if have systemctl; then
        sssd_state=$(systemctl is-active sssd 2>/dev/null || true)
        case "$sssd_state" in active) sev=ok;; inactive|failed) sev=crit;; *) sev=unknown;; esac
        add_check "ДОМЕН / KERBEROS" "domain.sssd" "SSSD" "${sssd_state:-не определён}" "$sev"
    else add_check "ДОМЕН / KERBEROS" "domain.sssd" "SSSD" "systemctl отсутствует" unknown; fi

    if have adcli; then
        if [[ -n $d ]]; then run_timeout 10 adcli testjoin -D "$d" >/dev/null 2>&1; else run_timeout 10 adcli testjoin >/dev/null 2>&1; fi
        case $? in 0) join_state="исправен"; sev=ok;; 124) join_state="тайм-аут проверки"; sev=warn;; *) join_state="ошибка testjoin"; sev=crit;; esac
        add_check "ДОМЕН / KERBEROS" "domain.join" "AD join" "$join_state" "$sev"
    elif have realm && realm list 2>/dev/null | grep -q '^realm-name:'; then
        add_check "ДОМЕН / KERBEROS" "domain.join" "AD join" "realm настроен, adcli отсутствует" unknown
    else add_check "ДОМЕН / KERBEROS" "domain.join" "AD join" "adcli недоступен" unknown; fi

    if have klist; then
        if klist -s >/dev/null 2>&1; then kstate="действующий билет"; sev=ok; else kstate="действующий билет не найден"; sev=warn; fi
        add_check "ДОМЕН / KERBEROS" "kerberos.ticket" "Kerberos ticket" "$kstate" "$sev"
        cache_count=$(klist -A 2>/dev/null | grep -c '^Ticket cache:' || true)
        if ((cache_count==0)); then cache_count=$(find /tmp -maxdepth 1 -type f -name 'krb5cc_*' -readable 2>/dev/null | wc -l); fi
        add_check "ДОМЕН / KERBEROS" "kerberos.caches" "Доступных cache" "$cache_count" ok
    else add_check "ДОМЕН / KERBEROS" "kerberos.ticket" "Kerberos ticket" "klist отсутствует" unknown; fi

    sync_state=""
    if have timedatectl; then sync_state=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true); fi
    if [[ $sync_state == yes ]]; then sev=ok; elif [[ $sync_state == no ]]; then sev=crit; else sev=unknown; sync_state="не определено"; fi
    add_check "ДОМЕН / KERBEROS" "time.sync" "Синхронизация времени" "$sync_state" "$sev"
    if have chronyc; then chrony=$(chronyc tracking 2>/dev/null | awk -F: '/System time/{gsub(/^[ \t]+/,"",$2); print $2; exit}'); [[ -n $chrony ]] && add_check "ДОМЕН / KERBEROS" "time.chrony" "Chrony offset" "$chrony" ok; fi

    if have journalctl; then
        sssd_logs=$(journalctl -u sssd -b --no-pager 2>/dev/null || true)
        c6=$(grep -Eci '(krb5|kerberos).*(code|error)[^0-9-]*6([^0-9]|$)' <<<"$sssd_logs" || true)
        c7=$(grep -Eci '(krb5|kerberos).*(code|error)[^0-9-]*7([^0-9]|$)' <<<"$sssd_logs" || true)
        c15=$(grep -Eci '(krb5|kerberos).*(code|error)[^0-9-]*15([^0-9]|$)' <<<"$sssd_logs" || true)
        if ((c6+c7+c15>0)); then sev=warn; else sev=ok; fi
        add_check "ДОМЕН / KERBEROS" "kerberos.errors" "Kerberos 6/7/15 в SSSD" "6:$c6  7:$c7  15:$c15" "$sev" "Счётчики относятся только к текущей загрузке"
    else add_check "ДОМЕН / KERBEROS" "kerberos.errors" "Kerberos 6/7/15 в SSSD" "journalctl отсутствует" unknown; fi

    check_dns_common "DNS / DOMAIN" "$d"
}

check_network() {
    local gw ifaces idx=0 row iface ip mac speed duplex link dns_domain cifs_count=0 cifs_bad=0 mnt src gvfs_count=0 gvfs_bad=0 g dir eap_count=0 cert_min=-1 cert_global_min=-1 uuid type eap certpath end end_epoch now days proc_caja proc_gvfs
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
            eap_count=$((eap_count+1)); cert_min=-1
            while IFS= read -r certpath; do
                certpath=${certpath#file://}; [[ -r $certpath ]] || continue
                if have openssl; then
                    end=$(openssl x509 -in "$certpath" -noout -enddate 2>/dev/null | cut -d= -f2-)
                    end_epoch=$(date -d "$end" +%s 2>/dev/null || true); now=$(date +%s)
                    if [[ $end_epoch =~ ^[0-9]+$ ]]; then days=$(((end_epoch-now)/86400)); ((cert_min<0 || days<cert_min)) && cert_min=$days; fi
                fi
            done < <(nmcli -g 802-1x.ca-cert,802-1x.client-cert connection show uuid "$uuid" 2>/dev/null | grep -v '^$')
            if ((cert_min>=0 && (cert_global_min<0 || cert_min<cert_global_min))); then cert_global_min=$cert_min; fi
        done < <(nmcli -t -f UUID,TYPE connection show --active 2>/dev/null)
        if ((eap_count>0)); then
            if ((cert_global_min>=0)); then add_check "802.1X" "network.8021x" "Активные 802.1X" "$eap_count; минимальный срок сертификата ${cert_global_min} дн." "$([[ $cert_global_min -lt 14 ]] && echo crit || { [[ $cert_global_min -lt 30 ]] && echo warn || echo ok; })"
            else add_check "802.1X" "network.8021x" "Активные 802.1X" "$eap_count; срок сертификата не определён" unknown; fi
        else add_check "802.1X" "network.8021x" "Активные 802.1X" "не обнаружены" info; fi
    else add_check "802.1X" "network.8021x" "802.1X" "nmcli отсутствует" unknown; fi

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

check_print() {
    local state sev default qcount=0 disabled=0 jobs=0 uris errcount
    if have systemctl; then
        state=$(systemctl is-active cups 2>/dev/null || systemctl is-active cups.service 2>/dev/null || true)
        case "$state" in active) sev=ok;; inactive|failed) sev=crit;; *) sev=unknown;; esac
        add_check "ПЕЧАТЬ / CUPS" "print.cups.service" "CUPS service" "${state:-не определён}" "$sev"
    else add_check "ПЕЧАТЬ / CUPS" "print.cups.service" "CUPS service" "systemctl отсутствует" unknown; fi

    if have lpstat; then
        if LC_ALL=C lpstat -r 2>/dev/null | grep -qi 'scheduler is running'; then add_check "ПЕЧАТЬ / CUPS" "print.scheduler" "CUPS scheduler" "работает" ok
        else add_check "ПЕЧАТЬ / CUPS" "print.scheduler" "CUPS scheduler" "не отвечает" crit; fi
        default=$(LC_ALL=C lpstat -d 2>/dev/null | sed -E 's/^system default destination:[[:space:]]*//' | head -n1)
        [[ -n $default ]] && add_check "ПЕЧАТЬ / CUPS" "print.default" "Принтер по умолчанию" "$default" ok || add_check "ПЕЧАТЬ / CUPS" "print.default" "Принтер по умолчанию" "не задан" info
        qcount=$(LC_ALL=C lpstat -p 2>/dev/null | grep -c '^printer ' || true)
        disabled=$(LC_ALL=C lpstat -p 2>/dev/null | grep -Eci 'disabled|paused|stopped' || true)
        jobs=$(LC_ALL=C lpstat -o 2>/dev/null | grep -c . || true)
        if ((disabled>0)); then sev=warn; else sev=ok; fi
        add_check "ПЕЧАТЬ / CUPS" "print.queues" "Очереди" "$qcount; paused/disabled: $disabled" "$sev"
        if ((jobs>20)); then sev=warn; else sev=ok; fi
        add_check "ПЕЧАТЬ / CUPS" "print.jobs" "Задания в очередях" "$jobs" "$sev"
        uris=$(LC_ALL=C lpstat -v 2>/dev/null | sed -E 's/^device for ([^:]+):[[:space:]]*/\1=/' | head -n10)
        if [[ -n $uris ]]; then
            while IFS= read -r row; do
                local name=${row%%=*} uri=${row#*=}
                add_check "ПЕЧАТЬ / CUPS" "print.uri.$name" "Backend $name" "$(sanitize_uri "$uri")" info
            done <<<"$uris"
        fi
    else add_check "ПЕЧАТЬ / CUPS" "print.lpstat" "Очереди CUPS" "lpstat отсутствует" unknown; fi

    if have journalctl; then
        errcount=$(journalctl -u cups -b -p warning..alert --no-pager 2>/dev/null | grep -c . || true)
        if ((errcount>20)); then sev=warn; else sev=ok; fi
        add_check "ПЕЧАТЬ / CUPS" "print.journal" "CUPS warning/error" "$errcount за текущую загрузку" "$sev"
    else add_check "ПЕЧАТЬ / CUPS" "print.journal" "CUPS journal" "journalctl отсутствует" unknown; fi
}

_rpm_matches() {
    local regex=$1
    rpm -qa --qf '%{NAME}|%{VERSION}-%{RELEASE}\n' 2>/dev/null | grep -Ei "$regex" | sort -u
}

check_software() {
    local rows count zombies proc
    if have rpm; then
        rows=$(_rpm_matches '(^|[-_])(r7|remmina|freerdp|icaclient|citrix|firefox|chromium|basis|workplace|bsscrypto|cryptopro|cprocsp|jacarta|pcsc|snx)([-_]|$)|^(firefox|chromium|remmina|freerdp|icaclient|pcsc-lite)')
        count=$(grep -c . <<<"$rows" 2>/dev/null || true)
        add_check "КОРПОРАТИВНОЕ ПО" "software.matches" "Найдено пакетов" "$count" info
        for pattern in 'firefox' 'chromium' 'remmina' 'freerdp' 'icaclient|citrix' 'r7' 'basis|workplace' 'bsscrypto|cryptopro|cprocsp|jacarta|pcsc' 'snx'; do
            local hit label
            hit=$(grep -Ei "$pattern" <<<"$rows" | head -n3 | tr '\n' ';' | sed 's/;$//')
            [[ -n $hit ]] || continue
            case "$pattern" in
                firefox) label="Firefox";; chromium) label="Chromium";; remmina) label="Remmina";; freerdp) label="FreeRDP";; 'icaclient|citrix') label="Citrix";; r7) label="R7";; 'basis|workplace') label="Basis Workplace";; 'snx') label="SNX";; *) label="Crypto/Token";; esac
            add_check "КОРПОРАТИВНОЕ ПО" "software.$label" "$label" "$hit" info
        done
    else add_check "КОРПОРАТИВНОЕ ПО" "software.rpm" "RPM inventory" "rpm отсутствует" unknown; fi

    zombies=$(ps -eo stat=,comm= 2>/dev/null | awk '$1 ~ /^Z/ && tolower($2) ~ /(wfica|citrix|remmina|r7|firefox|chromium|basis)/{n++} END{print n+0}')
    if ((zombies>0)); then add_check "КОРПОРАТИВНОЕ ПО" "software.zombies" "Zombie-процессы" "$zombies" warn
    else add_check "КОРПОРАТИВНОЕ ПО" "software.zombies" "Zombie-процессы" "0" ok; fi
    proc=$(pgrep -fc 'wfica|selfservice|remmina|r7|firefox|chromium|basis' 2>/dev/null || true)
    add_check "КОРПОРАТИВНОЕ ПО" "software.processes" "Активные процессы" "$proc" info
}

emit_text() {
    local current="" i sevmark
    printf 'ARM_INFO ENTERPRISE %s\n' "$VERSION"
    printf 'Профиль: %s\n' "$PROFILE"
    printf 'Дата: %s\n' "$(date '+%d.%m.%Y %H:%M:%S')"
    ((PRIVACY)) && printf 'Privacy: включён\n'
    for i in "${!KEYS[@]}"; do
        if [[ ${SECTIONS[i]} != "$current" ]]; then current=${SECTIONS[i]}; printf '\n%s\n' "$current"; printf '%*s\n' 92 '' | tr ' ' '-'; fi
        case "${SEVERITIES[i]}" in ok) sevmark='OK';; info) sevmark='INFO';; warn) sevmark='WARN';; crit) sevmark='CRIT';; *) sevmark='N/A';; esac
        printf '%-31s %-7s %s\n' "${LABELS[i]}" "[$sevmark]" "${VALUES[i]}"
        [[ -n ${DETAILS[i]} ]] && printf '  %-29s %s\n' 'Примечание:' "${DETAILS[i]}"
    done
    printf '\nСВОДКА\n'; printf '%*s\n' 92 '' | tr ' ' '-'
    printf '%-31s %s\n' 'Критично' "$CRIT_COUNT"
    printf '%-31s %s\n' 'Предупреждения' "$WARN_COUNT"
    printf '%-31s %s\n' 'Неполные проверки' "$UNKNOWN_COUNT"
}

emit_json() {
    local i comma="" status="ok"
    ((CRIT_COUNT>0)) && status="critical" || { ((WARN_COUNT>0)) && status="warning" || { ((UNKNOWN_COUNT>0)) && status="incomplete"; }; }
    printf '{\n'
    printf '  "schema_version": 2,\n'
    printf '  "tool": "arm_info-enterprise",\n'
    printf '  "version": "%s",\n' "$VERSION"
    printf '  "profile": "%s",\n' "$(json_escape "$PROFILE")"
    printf '  "privacy": %s,\n' "$([[ $PRIVACY -eq 1 ]] && echo true || echo false)"
    printf '  "generated_at": "%s",\n' "$(date --iso-8601=seconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
    printf '  "status": "%s",\n' "$status"
    printf '  "summary": {"critical": %d, "warnings": %d, "unknown": %d},\n' "$CRIT_COUNT" "$WARN_COUNT" "$UNKNOWN_COUNT"
    printf '  "checks": [\n'
    for i in "${!KEYS[@]}"; do
        printf '%s    {"key":"%s","section":"%s","label":"%s","value":"%s","severity":"%s","detail":"%s"}' \
          "$comma" "$(json_escape "${KEYS[i]}")" "$(json_escape "${SECTIONS[i]}")" "$(json_escape "${LABELS[i]}")" "$(json_escape "${VALUES[i]}")" "${SEVERITIES[i]}" "$(json_escape "${DETAILS[i]}")"
        comma=$',\n'
    done
    printf '\n  ]\n}\n'
}

compare_reports() {
    have python3 || { echo "Ошибка: для --compare требуется python3" >&2; exit 69; }
    [[ -r $COMPARE_A && -r $COMPARE_B ]] || { echo "Ошибка: один из файлов сравнения недоступен" >&2; exit 66; }
    python3 - "$COMPARE_A" "$COMPARE_B" "$JSON_MODE" <<'PY'
import json,sys
from pathlib import Path

a,b,json_mode=Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3]=='1'
try:
    A=json.loads(a.read_text(encoding='utf-8'))
    B=json.loads(b.read_text(encoding='utf-8'))
except Exception as e:
    print(f"Ошибка чтения JSON: {e}", file=sys.stderr); sys.exit(65)

IGNORE={'generated_at','timestamp','date','report','report_file','uptime'}
def enterprise_map(d):
    if isinstance(d,dict) and isinstance(d.get('checks'),list):
        return {x.get('key'):x.get('value') for x in d['checks'] if isinstance(x,dict) and x.get('key')}
    return None

def flat(obj,p=''):
    out={}
    if isinstance(obj,dict):
        for k,v in obj.items():
            if k in IGNORE: continue
            q=f"{p}.{k}" if p else k
            out.update(flat(v,q))
    elif isinstance(obj,list):
        for i,v in enumerate(obj): out.update(flat(v,f"{p}[{i}]"))
    else: out[p]=obj
    return out
FA=enterprise_map(A) or flat(A)
FB=enterprise_map(B) or flat(B)
keys=sorted(set(FA)|set(FB))
diff=[]
for k in keys:
    va,vb=FA.get(k,'<нет>'),FB.get(k,'<нет>')
    if va!=vb: diff.append({'key':k,'a':va,'b':vb})
if json_mode:
    print(json.dumps({'schema_version':1,'differences':diff,'count':len(diff)},ensure_ascii=False,indent=2))
else:
    print('СРАВНЕНИЕ ОТЧЁТОВ')
    print('-'*92)
    if not diff: print('Отличий по сравниваемым полям не обнаружено.')
    else:
        for x in diff:
            print(f"{x['key']}")
            print(f"  A: {x['a']}")
            print(f"  B: {x['b']}")
        print(f"\nВсего отличий: {len(diff)}")
sys.exit(1 if diff else 0)
PY
}

if [[ -n $COMPARE_A ]]; then compare_reports; exit $?; fi

case "$PROFILE" in
    domain) check_domain ;;
    network) check_network ;;
    print) check_print ;;
    software) check_software ;;
    enterprise) check_domain; check_network; check_print; check_software ;;
esac

if ((JSON_MODE)); then emit_json; else emit_text; fi

if ((CRIT_COUNT>0)); then exit 2
elif ((WARN_COUNT>0)); then exit 1
elif ((UNKNOWN_COUNT>0)); then exit 3
else exit 0
fi
