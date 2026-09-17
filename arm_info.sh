#!/bin/bash

(
# ============================================================
# arm_info 1.2.4 — диагностика АРМ для РЕД ОС 7 / 8
# Запуск: исполняемый Bash-файл; base и enterprise находятся в одном файле.
# Результат выводится на экран; сохранение выполняется только по -s/--save.
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then
    echo "Ошибка: скрипт необходимо запускать через bash." >&2
    exit 1
fi

ARM_INFO_VERSION="1.2.4"

ARM_INFO_SELF_SOURCE=${BASH_SOURCE[0]:-$0}
if [[ -f $ARM_INFO_SELF_SOURCE ]]; then
    ARM_INFO_SELF_PATH=$(readlink -f -- "$ARM_INFO_SELF_SOURCE" 2>/dev/null || printf '%s' "$ARM_INFO_SELF_SOURCE")
    printf -v ARM_INFO_SELF_Q '%q' "$ARM_INFO_SELF_PATH"
    ARM_INFO_SELF_CMD="bash $ARM_INFO_SELF_Q"
else
    ARM_INFO_SELF_CMD="arm_info"
fi


# enterprise-profile-dispatch-v1.2.4 — single-file edition
# Enterprise-профили встроены в arm_info.sh; внешний helper не требуется.
_arm_enterprise_run() (
# arm_info enterprise profiles — v1.2.4
# Read-only diagnostics for RED OS enterprise workstations.
set -u
set -o pipefail

VERSION="1.2.4"
PROFILE=""
PRIVACY=0
JSON_MODE=0
SAVE_REPORT=0
OUTPUT_PATH=""
COMPARE_A=""
COMPARE_B=""

usage() {
    cat <<'USAGE'
arm_info enterprise profiles 1.2.4

Использование:
  arm_info --profile domain [-p|--privacy] [--json] [-s|--save] [-o FILE]
  arm_info --profile network [-p|--privacy] [--json] [-s|--save] [-o FILE]
  arm_info --profile print [-p|--privacy] [--json] [-s|--save] [-o FILE]
  arm_info --profile software [-p|--privacy] [--json] [-s|--save] [-o FILE]
  arm_info -c [-p|--privacy] [--json] [-s|--save] [-o FILE]
  arm_info --corp [-p|--privacy] [--json] [-s|--save] [-o FILE]
  arm_info --profile enterprise [-p|--privacy] [--json] [-s|--save] [-o FILE]
  arm_info --compare REPORT_A.json REPORT_B.json [--json] [-s|--save] [-o FILE]

Профили:
  domain       AD/SSSD/Kerberos, DNS SRV, KDC/LDAP, синхронизация времени
  network      DNS, интерфейсы, 802.1X, CIFS/SMB, GVFS/Caja
  print        CUPS, очереди, задания, backend URI, ошибки журнала
  software     глобальная инвентаризация всех RPM-пакетов и общие процессы
  enterprise   domain + network + print (без инвентаризации ПО)

Параметры:
  -p, --privacy           обезличить отчёт
  -s, --save              сохранить отчёт в файл
  -o, --output PATH       указать файл или каталог сохранения
  --json                  вывести отчёт в JSON

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
        -c|--corp) PROFILE=enterprise; shift ;;
        --profile)
            [[ $# -ge 2 ]] || { echo "Ошибка: --profile требует значение" >&2; exit 64; }
            PROFILE=$2; shift 2 ;;
        --profile=*) PROFILE=${1#*=}; shift ;;
        --compare)
            [[ $# -ge 3 ]] || { echo "Ошибка: --compare требует два JSON-файла" >&2; exit 64; }
            COMPARE_A=$2; COMPARE_B=$3; shift 3 ;;
        -p|--privacy) PRIVACY=1; shift ;;
        --json) JSON_MODE=1; shift ;;
        -s|--save) SAVE_REPORT=1; shift ;;
        -o|--output)
            [[ $# -ge 2 ]] || { echo "Ошибка: $1 требует путь" >&2; exit 64; }
            OUTPUT_PATH=$2; shift 2 ;;
        -V|--version) echo "arm_info enterprise $VERSION"; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        *) echo "Ошибка: неизвестный параметр: $1" >&2; usage >&2; exit 64 ;;
    esac
done

if [[ -n $OUTPUT_PATH && $SAVE_REPORT -ne 1 ]]; then
    echo "Ошибка: -o/--output используется только вместе с -s/--save" >&2
    exit 64
fi

if [[ -n $COMPARE_A || -n $COMPARE_B ]]; then
    [[ -n $COMPARE_A && -n $COMPARE_B ]] || { echo "Ошибка: укажите два файла для сравнения" >&2; exit 64; }
else
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
        printf '\033[2J\033[H'
    fi
fi

# Файл создаётся только по явному -s/--save. Без -o имя формируется автоматически.
# Для профилей используются отдельные теги; enterprise/--corp сохраняет CORP-префикс.
if [[ -z $COMPARE_A && -z $OUTPUT_PATH ]] && ((SAVE_REPORT==1)); then
    CORP_TAG=${PROFILE^^}
    [[ $PROFILE == enterprise ]] && CORP_TAG=CORP
    CORP_EXT=txt
    ((JSON_MODE==1)) && CORP_EXT=json
    CORP_STAMP=$(date '+%Y%m%d_%H%M%S')
    CORP_HOST=$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'ARM')
    CORP_HOST=$(printf '%s' "$CORP_HOST" | tr -c '[:alnum:]_.-' '_')
    if ((PRIVACY)); then
        CORP_NAME="ARM_INFO_${CORP_TAG}_PRIVATE_${CORP_STAMP}.${CORP_EXT}"
    else
        CORP_NAME="ARM_INFO_${CORP_TAG}_${CORP_HOST}_${CORP_STAMP}.${CORP_EXT}"
    fi
    CORP_DIR=$(pwd -P 2>/dev/null || printf '/tmp')
    [[ -d $CORP_DIR && -w $CORP_DIR ]] || CORP_DIR=/tmp
    OUTPUT_PATH="$CORP_DIR/$CORP_NAME"
fi

if [[ -n $COMPARE_A && -z $OUTPUT_PATH ]] && ((SAVE_REPORT==1)); then
    CORP_EXT=txt
    ((JSON_MODE==1)) && CORP_EXT=json
    CORP_STAMP=$(date '+%Y%m%d_%H%M%S')
    CORP_DIR=$(pwd -P 2>/dev/null || printf '/tmp')
    [[ -d $CORP_DIR && -w $CORP_DIR ]] || CORP_DIR=/tmp
    OUTPUT_PATH="$CORP_DIR/ARM_INFO_COMPARE_${CORP_STAMP}.${CORP_EXT}"
fi

if [[ -n $OUTPUT_PATH ]] && ((SAVE_REPORT==1)); then
    if [[ -d $OUTPUT_PATH ]]; then
        # Для -o DIR используем то же имя, что и при автоматическом сохранении.
        CORP_TAG=${PROFILE^^}
        [[ $PROFILE == enterprise ]] && CORP_TAG=CORP
        CORP_EXT=txt
        ((JSON_MODE==1)) && CORP_EXT=json
        CORP_STAMP=$(date '+%Y%m%d_%H%M%S')
        CORP_HOST=$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'ARM')
        CORP_HOST=$(printf '%s' "$CORP_HOST" | tr -c '[:alnum:]_.-' '_')
        if ((PRIVACY)); then CORP_NAME="ARM_INFO_${CORP_TAG}_PRIVATE_${CORP_STAMP}.${CORP_EXT}"
        else CORP_NAME="ARM_INFO_${CORP_TAG}_${CORP_HOST}_${CORP_STAMP}.${CORP_EXT}"; fi
        OUTPUT_PATH="${OUTPUT_PATH%/}/$CORP_NAME"
    fi
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


# Подробные рекомендации формируются отдельно от check-логики. Это позволяет
# сохранять стабильные machine-readable ключи и при этом давать администратору
# максимум контекста: причины, влияние, проверки, действия и команды.
REC_KEYS=(); REC_LEVELS=(); REC_TITLES=(); REC_CAUSES=(); REC_IMPACTS=()
REC_CHECKS=(); REC_ACTIONS=(); REC_COMMANDS=(); REC_VERIFIES=(); REC_SOURCES=()

recommendation_for() {
    local key=$1 severity=$2 value=$3 detail=${4:-}
    REC_CAUSE="Проверка не смогла подтвердить нормальное состояние. Возможны локальная ошибка конфигурации, недоступность зависимой службы/узла или отсутствие диагностической утилиты."
    REC_IMPACT="Соответствующая функция АРМ может работать нестабильно либо диагностика по этому пункту остаётся неполной."
    REC_CHECK="Сопоставить текущее значение с рабочим АРМ, проверить системный журнал текущей загрузки и доступность связанных служб."
    REC_ACTION="Устранить первичную причину, затем повторить профильную диагностику arm_info."
    REC_COMMAND="journalctl -b -p warning..alert --no-pager | tail -100|$ARM_INFO_SELF_CMD --profile $PROFILE"
    REC_VERIFY="Повторный запуск должен перевести проверку в OK/INFO и убрать её из раздела рекомендаций."

    case "$key" in
        domain.name)
            REC_CAUSE="Домен не определён через realm/SSSD/FQDN. Возможны неполное присоединение к домену, повреждённая конфигурация SSSD или некорректный hostname/FQDN."
            REC_IMPACT="Доменные учётные записи, Kerberos SSO, LDAP и поиск контроллеров домена могут работать некорректно."
            REC_CHECK="Сравнить realm, список доменов SSSD, FQDN и секции [domain/...] в sssd.conf."
            REC_ACTION="Восстановить корректное определение домена; не выполнять повторный join до проверки DNS, времени и текущего состояния присоединения."
            REC_COMMAND="realm list|sssctl domain-list|hostname -f|grep -E '^\\[domain/' /etc/sssd/sssd.conf 2>/dev/null"
            ;;
        domain.sssd)
            REC_CAUSE="SSSD не активен, завершился с ошибкой либо systemd не смог определить его состояние."
            REC_IMPACT="Доменные входы, разрешение пользователей/групп, sudo-правила и Kerberos через SSSD могут быть недоступны."
            REC_CHECK="Проверить состояние службы, последние ошибки и статус домена SSSD."
            REC_ACTION="Исправить первую ошибку в журнале и только после этого перезапустить SSSD. Перед очисткой кэша сохранить диагностику."
            REC_COMMAND="systemctl status sssd --no-pager -l|journalctl -u sssd -b --no-pager | tail -150|sssctl domain-list|sssctl config-check"
            REC_VERIFY="systemctl is-active sssd должен вернуть active; домен должен определяться без ошибок."
            ;;
        domain.join)
            REC_CAUSE="Проверка доверительных отношений AD не прошла либо adcli недоступен. Причиной часто бывают DNS, время, машинная учётная запись или недоступность DC."
            REC_IMPACT="Kerberos и доменная аутентификация могут периодически или полностью не работать."
            REC_CHECK="Сначала проверить DNS SRV, синхронизацию времени, доступность KDC/LDAP и только затем состояние join."
            REC_ACTION="Не выполнять повторное присоединение вслепую. Зафиксировать вывод adcli/SSSD и восстановить первичную причину."
            REC_COMMAND="adcli testjoin --verbose|timedatectl|dig +short _kerberos._tcp.DOMAIN_FQDN SRV|dig +short _ldap._tcp.DOMAIN_FQDN SRV|journalctl -u sssd -b --no-pager | tail -150"
            ;;
        kerberos.ticket)
            REC_CAUSE="Действующий Kerberos ticket не найден либо klist недоступен. При запуске от root билет интерактивного пользователя может находиться в другом credential cache."
            REC_IMPACT="SSO к доменным ресурсам, CIFS, LDAP и приложениям с GSSAPI может запрашивать пароль или завершаться ошибкой."
            REC_CHECK="Проверить все доступные cache, срок действия TGT, principal и время на АРМ."
            REC_ACTION="Для нужного пользователя получить/обновить билет штатным способом; не удалять cache до фиксации причины."
            REC_COMMAND="klist -l|klist -A|sudo -u 'USER_NAME' klist -A|timedatectl"
            ;;
        kerberos.errors)
            REC_CAUSE="В журнале SSSD текущей загрузки обнаружены записи с признаками ошибок Kerberos. Конкретный код не предполагается заранее — анализируются все Kerberos/krb5 ошибки."
            REC_IMPACT="Возможны отказы входа, блокировки после смены пароля, запросы пароля вместо SSO и недоступность доменных ресурсов."
            REC_CHECK="Просмотреть сами сообщения Kerberos, время события, principal/сервер, параллельно проверить билет, DNS SRV и синхронизацию времени."
            REC_ACTION="Устранять ошибку по фактическому тексту журнала; не ограничиваться заранее заданным перечнем кодов."
            REC_COMMAND="journalctl -u sssd -b --no-pager | grep -Ei 'krb5|kerberos' | tail -120|klist -A|timedatectl|sssctl domain-list"
            REC_VERIFY="После устранения причины новые Kerberos-ошибки не должны появляться; старые записи текущей загрузки могут оставаться в журнале до reboot."
            ;;
        time.sync)
            REC_CAUSE="Системное время не подтверждено как синхронизированное. Возможны недоступный NTP, неверный источник времени или остановленная служба синхронизации."
            REC_IMPACT="Kerberos чувствителен к расхождению времени; возможны отказы preauthentication и SSO."
            REC_CHECK="Проверить NTPSynchronized, текущий offset, источники времени и журнал службы синхронизации."
            REC_ACTION="Восстановить штатную синхронизацию времени с разрешённым источником организации."
            REC_COMMAND="timedatectl|chronyc tracking|chronyc sources -v|journalctl -b --no-pager | grep -Ei 'chrony|ntp|timesync' | tail -100"
            ;;
        dns.servers|dns.stub)
            REC_CAUSE="Рабочие upstream DNS не определены или локальный stub 127.0.0.53 не имеет подтверждённого upstream."
            REC_IMPACT="Поиск DC/KDC/LDAP, доменная аутентификация, CIFS и другие сетевые сервисы могут работать нестабильно."
            REC_CHECK="Сравнить /etc/resolv.conf, resolvectl и DNS из активного NetworkManager-профиля. Проверить, что доменные DNS действительно доступны."
            REC_ACTION="Восстановить DNS через штатный менеджер сети; не править generated resolv.conf вручную, если он управляется NetworkManager/systemd-resolved."
            REC_COMMAND="cat /etc/resolv.conf|resolvectl status|systemd-resolve --status|nmcli -f GENERAL.CONNECTION,IP4.DNS,IP4.DOMAIN device show|ip -4 route"
            ;;
        dns.search)
            REC_CAUSE="DNS search/domain suffix не определён."
            REC_IMPACT="Короткие доменные имена и автоматический поиск доменных сервисов могут разрешаться не так, как ожидается."
            REC_CHECK="Проверить search/domain в resolv.conf и параметры активного сетевого соединения."
            REC_ACTION="Настроить корректный DNS search domain через штатную сетевую конфигурацию организации."
            REC_COMMAND="grep -E '^(search|domain|nameserver)' /etc/resolv.conf|nmcli -f GENERAL.CONNECTION,IP4.DNS,IP4.DOMAIN device show"
            ;;
        dns.fqdn)
            REC_CAUSE="FQDN хоста не определяется или не разрешается через текущий DNS."
            REC_IMPACT="Kerberos SPN, доменные сервисы и приложения, использующие полное имя хоста, могут получать ошибки."
            REC_CHECK="Сопоставить hostname, hostname -f, hosts и DNS A/PTR."
            REC_ACTION="Исправить hostname/DNS запись по правилам домена; избегать локальных костылей в /etc/hosts без согласования."
            REC_COMMAND="hostnamectl|hostname -f|getent hosts \"$(hostname -f 2>/dev/null)\"|getent ahostsv4 \"$(hostname -f 2>/dev/null)\""
            ;;
        dns.srv.ldap|dns.srv.kerberos|dns.srv)
            REC_CAUSE="Доменные SRV-записи не найдены либо проверить их невозможно."
            REC_IMPACT="Клиент может не находить контроллеры домена, KDC или LDAP автоматически."
            REC_CHECK="Проверить DNS-серверы и SRV-записи для фактического домена с рабочего и проблемного АРМ."
            REC_ACTION="Исправить DNS/зону домена или клиентскую DNS-конфигурацию; не прописывать DC статически как замену корректным SRV без необходимости."
            REC_COMMAND="dig +short _kerberos._tcp.DOMAIN_FQDN SRV|dig +short _ldap._tcp.DOMAIN_FQDN SRV|host -t SRV _kerberos._tcp.DOMAIN_FQDN|host -t SRV _ldap._tcp.DOMAIN_FQDN"
            ;;
        domain.dc.ports)
            REC_CAUSE="Не все найденные KDC/LDAP endpoints доступны по проверяемым TCP-портам. Возможны маршрут, firewall, DNS или недоступный DC."
            REC_IMPACT="Аутентификация и LDAP-запросы могут зависеть от случайно выбранного DC и работать непредсказуемо."
            REC_CHECK="Определить все SRV targets, проверить разрешение их имён, маршрут и TCP 88/389 по каждому узлу."
            REC_ACTION="Восстановить сетевую доступность либо вывести неисправный DC из клиентского DNS discovery на стороне инфраструктуры."
            REC_COMMAND="dig +short _kerberos._tcp.DOMAIN_FQDN SRV|dig +short _ldap._tcp.DOMAIN_FQDN SRV|timeout 5 nc -vz DC_FQDN 88|timeout 5 nc -vz DC_FQDN 389|ip route get DC_IP"
            ;;
        network.gateway)
            REC_CAUSE="Default route не найден."
            REC_IMPACT="Связь за пределами локальной подсети и доступ к части инфраструктуры будут недоступны."
            REC_CHECK="Проверить активное соединение, IPv4-параметры и таблицу маршрутизации."
            REC_ACTION="Восстановить штатный сетевой профиль/маршрут через NetworkManager."
            REC_COMMAND="ip -4 route|ip -br addr|nmcli device status|nmcli connection show --active"
            ;;
        network.interfaces)
            REC_CAUSE="Нет активного не-loopback IPv4-интерфейса. Возможны link down, DHCP/статическая конфигурация или проблема драйвера/802.1X."
            REC_IMPACT="Сетевые функции АРМ недоступны."
            REC_CHECK="Проверить link, состояние NetworkManager, адреса и журнал сетевого интерфейса."
            REC_ACTION="Восстановить физический линк/профиль/аутентификацию сети, затем получить корректный IPv4."
            REC_COMMAND="ip -br link|ip -br addr|nmcli device status|journalctl -u NetworkManager -b --no-pager | tail -150"
            ;;
        network.8021x)
            REC_CAUSE="802.1X-профиль неполон, срок сертификата мал/истёк либо проверить сертификат невозможно."
            REC_IMPACT="АРМ может потерять сетевой доступ после переподключения или по истечении сертификата."
            REC_CHECK="Проверить EAP-метод, CA/client certificate, срок действия и ошибки NetworkManager/supplicant. Если сертификат DER, для ручного openssl добавьте -inform DER."
            REC_ACTION="Заранее обновить истекающий сертификат или исправить профиль 802.1X согласно политике организации."
            REC_COMMAND="nmcli -f NAME,UUID,TYPE connection show|nmcli connection show 'PROFILE_NAME' | grep -E '^802-1x\.(eap|identity|ca-cert|client-cert|phase2-ca-cert|phase2-client-cert|private-key|system-ca-certs):'|openssl x509 -in \"CERT_PATH\" -noout -subject -issuer -dates|journalctl -u NetworkManager -b --no-pager | grep -Ei '802.1x|eap|supplicant|certificate' | tail -120"
            ;;
        network.cifs|network.cifs.mount.*)
            REC_CAUSE="CIFS смонтирован, но фактическое чтение каталога или metadata lookup завершились ошибкой/тайм-аутом. Для sec=krb5,multiuser результат проверяется в контексте активного локального GUI-пользователя, а не root."
            REC_IMPACT="Caja/приложения могут зависать либо не открывать конкретную шару, даже если mount формально присутствует."
            REC_CHECK="Сопоставить SOURCE → TARGET и статус конкретного SMB-ресурса. Проверка выполняет полный readdir каталога под timeout и stat одного элемента, поэтому она не ограничивается первым cached dentry."
            REC_ACTION="Устранить фактическую сетевую, Kerberos/credential или I/O-причину. Размонтирование выполнять только после проверки открытых файлов и процессов."
            REC_COMMAND="findmnt -t cifs -o TARGET,SOURCE,OPTIONS|journalctl -k -b --no-pager | grep -Ei 'cifs|smb' | tail -120|sudo -u 'USER_NAME' klist -A"
            ;;
        network.gvfs|network.gvfs.*)
            REC_CAUSE="Один или несколько GVFS mount не отвечают. Возможны недоступный SMB-ресурс или зависшие пользовательские gvfs-процессы."
            REC_IMPACT="Файловый менеджер может долго открывать сетевые папки, зависать при удалении/копировании и удерживать старые подключения."
            REC_CHECK="Проверить gio mounts, процессы gvfs/caja и доступность конкретного каталога с timeout."
            REC_ACTION="После фиксации диагностики перезапустить только проблемные пользовательские gvfs/caja процессы либо переподключить ресурс."
            REC_COMMAND="loginctl list-sessions --no-legend|ps -ef | grep -E 'caja|gvfsd' | grep -v grep|find /run/user/*/gvfs -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null"
            ;;
        print.cups.service)
            REC_CAUSE="Служба CUPS не активна либо её состояние не определено."
            REC_IMPACT="Локальная и сетевая печать через CUPS будет недоступна."
            REC_CHECK="Проверить systemd state и полный журнал CUPS текущей загрузки."
            REC_ACTION="Устранить первую ошибку конфигурации/backend, затем перезапустить CUPS."
            REC_COMMAND="systemctl status cups --no-pager -l|journalctl -u cups -b --no-pager | tail -150|cupsctl"
            ;;
        print.scheduler)
            REC_CAUSE="CUPS scheduler не отвечает на lpstat."
            REC_IMPACT="Очереди и задания печати не могут обслуживаться корректно."
            REC_CHECK="Сопоставить состояние cups.service, scheduler и журнал."
            REC_ACTION="Восстановить работу scheduler после устранения причины службы/конфигурации."
            REC_COMMAND="lpstat -r|systemctl status cups --no-pager -l|journalctl -u cups -b --no-pager | tail -150"
            ;;
        print.queues)
            REC_CAUSE="Обнаружены paused/disabled/stopped очереди. Причиной могут быть backend, аутентификация, недоступный принтер или ручная приостановка."
            REC_IMPACT="Задания будут накапливаться или не попадут на устройство печати."
            REC_CHECK="Получить состояние каждой очереди, причины остановки, backend URI и незавершённые задания."
            REC_ACTION="Исправить первичную причину. Возобновлять очередь только после проверки backend/устройства."
            REC_COMMAND="lpstat -a -p -d -v|lpstat -W not-completed -o|journalctl -u cups -b --no-pager | tail -150|cupsenable QUEUE_NAME|cupsaccept QUEUE_NAME"
            ;;
        print.jobs)
            REC_CAUSE="В очередях накопилось много незавершённых заданий. Возможны остановленная очередь, недоступный backend или проблемное задание."
            REC_IMPACT="Новые задания задерживаются; spool может расти."
            REC_CHECK="Определить очередь и самое старое/проблемное задание, затем проверить состояние принтера и backend."
            REC_ACTION="Устранить причину очереди. Удалять задания только осознанно после согласования, чтобы не потерять пользовательскую печать."
            REC_COMMAND="lpstat -W not-completed -o|lpstat -p -v|du -sh /var/spool/cups 2>/dev/null|cancel JOB_ID"
            ;;
        print.lpstat)
            REC_CAUSE="Утилита lpstat отсутствует, поэтому состояние очередей CUPS не проверено."
            REC_IMPACT="Диагностика печати неполная; это не означает неисправность CUPS."
            REC_CHECK="Проверить наличие cups-client/пакета, предоставляющего lpstat."
            REC_ACTION="Установить штатный клиент CUPS из разрешённого репозитория, если диагностика печати нужна на этом АРМ."
            REC_COMMAND="command -v lpstat|rpm -q cups-client|dnf provides '/usr/bin/lpstat'"
            ;;
        print.journal)
            REC_CAUSE="В журнале CUPS много warning/error за текущую загрузку либо журнал недоступен."
            REC_IMPACT="Могут присутствовать повторяющиеся ошибки backend, фильтра, аутентификации или устройства."
            REC_CHECK="Посмотреть не только количество, но и уникальные последние сообщения с Job/Printer context."
            REC_ACTION="Устранять наиболее раннюю повторяющуюся первичную ошибку; не ориентироваться только на число записей."
            REC_COMMAND="journalctl -u cups -b -p warning..alert --no-pager | tail -150|journalctl -u cups -b --no-pager | grep -Ei 'job|printer|backend|filter|auth|error|failed' | tail -150"
            ;;
        software.rpm)
            REC_CAUSE="RPM inventory недоступна, потому что rpm не найден."
            REC_IMPACT="Сравнение программного состава АРМ будет неполным."
            REC_CHECK="Проверить используемый пакетный менеджер и наличие rpm."
            REC_ACTION="Для РЕД ОС восстановить штатные rpm-инструменты перед инвентаризацией."
            REC_COMMAND="command -v rpm|command -v dnf|dnf provides '/usr/bin/rpm'"
            ;;
        software.zombies)
            REC_CAUSE="Обнаружены zombie-процессы. Zombie уже завершён; запись остаётся, пока родительский процесс не заберёт exit status."
            REC_IMPACT="Единичный zombie обычно не критичен, но постоянный рост указывает на проблему родительского процесса/приложения."
            REC_CHECK="Определить PID/PPID zombie, затем исследовать состояние и журнал родителя."
            REC_ACTION="Не пытаться kill zombie напрямую. Исправлять/перезапускать родительский процесс только после определения влияния на пользователя."
            REC_COMMAND="ps -eo pid,ppid,stat,lstart,comm,args | awk '$3 ~ /^Z/'|ps -fp PARENT_PID|journalctl _PID=PARENT_PID -b --no-pager | tail -100"
            ;;
    esac

    [[ -n $detail ]] && REC_CHECK="$REC_CHECK Дополнительный контекст проверки: $detail"
    if [[ $severity == crit ]]; then REC_LEVEL="КРИТИЧНО"
    elif [[ $severity == warn ]]; then REC_LEVEL="ВНИМАНИЕ"
    else REC_LEVEL="ПРОВЕРКА"; fi
}

build_recommendations() {
    local i
    REC_KEYS=(); REC_LEVELS=(); REC_TITLES=(); REC_CAUSES=(); REC_IMPACTS=()
    REC_CHECKS=(); REC_ACTIONS=(); REC_COMMANDS=(); REC_VERIFIES=(); REC_SOURCES=()
    for i in "${!KEYS[@]}"; do
        case "${SEVERITIES[i]}" in warn|crit|unknown) ;; *) continue ;; esac
        recommendation_for "${KEYS[i]}" "${SEVERITIES[i]}" "${VALUES[i]}" "${DETAILS[i]}"
        REC_KEYS+=("${KEYS[i]}")
        REC_LEVELS+=("$REC_LEVEL")
        REC_TITLES+=("${LABELS[i]}: ${VALUES[i]}")
        REC_CAUSES+=("$REC_CAUSE")
        REC_IMPACTS+=("$REC_IMPACT")
        REC_CHECKS+=("$REC_CHECK")
        REC_ACTIONS+=("$REC_ACTION")
        REC_COMMANDS+=("$REC_COMMAND")
        REC_VERIFIES+=("$REC_VERIFY")
        REC_SOURCES+=("${SECTIONS[i]} / ${KEYS[i]}")
    done
}

report_width() {
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
    local cmd=$1 desc
    case "$cmd" in
        realm\ list*) desc="покажет параметры текущего присоединения к realm/домену" ;;
        sssctl\ domain-list*) desc="покажет домены, которые видит SSSD" ;;
        sssctl\ config-check*) desc="проверит конфигурацию SSSD на синтаксические и структурные ошибки" ;;
        hostname\ -f*) desc="покажет FQDN, который система определяет для этого АРМ" ;;
        hostnamectl*) desc="покажет статический/текущий hostname и базовые сведения о системе" ;;
        grep*sssd.conf*) desc="покажет доменные секции из конфигурации SSSD" ;;
        systemctl\ status\ sssd*) desc="покажет состояние SSSD и последние сообщения systemd о службе" ;;
        systemctl\ status\ cups*) desc="покажет состояние CUPS и последние сообщения systemd о службе" ;;
        systemctl\ status*) desc="покажет состояние указанной systemd-службы и последние сообщения о её запуске" ;;
        systemctl\ --failed*) desc="покажет systemd-службы, находящиеся в failed" ;;
        journalctl*-u\ sssd*) desc="покажет журнал SSSD текущей загрузки для поиска первичной ошибки" ;;
        journalctl*-u\ NetworkManager*) desc="покажет события NetworkManager/802.1X/EAP текущей загрузки" ;;
        journalctl*-u\ cups*) desc="покажет ошибки и события CUPS текущей загрузки" ;;
        journalctl*-k*) desc="покажет сообщения ядра, связанные с устройствами и сетевыми файловыми системами" ;;
        journalctl*) desc="покажет системный журнал, относящийся к диагностируемой проблеме" ;;
        adcli\ testjoin*) desc="проверит машинные Kerberos-учётные данные из keytab и валидность присоединения к AD; --verbose добавит детали discovery/authentication" ;;
        timedatectl*) desc="покажет системное время, часовой пояс и состояние синхронизации" ;;
        chronyc\ tracking*) desc="покажет текущий offset и качество синхронизации chrony" ;;
        chronyc\ sources*) desc="покажет доступные источники времени и выбранный источник chrony" ;;
        dig*) desc="запросит DNS/SRV-записи, используемые для поиска доменных служб" ;;
        host*) desc="выполнит DNS-проверку указанного имени или SRV-записи" ;;
        klist\ -l*) desc="покажет Kerberos credential caches в коллекции текущего пользователя" ;;
        klist*) desc="покажет Kerberos cache, principal и сроки действия билетов текущего пользователя" ;;
        sudo\ -u*\ klist*) desc="покажет Kerberos-билеты в контексте указанного пользователя; это важно, если arm_info запущен от root" ;;
        resolvectl*) desc="покажет фактические DNS-серверы и домены systemd-resolved; на системах без resolvectl команда может отсутствовать" ;;
        systemd-resolve*) desc="покажет DNS-состояние старых версий systemd-resolved; используется как совместимый fallback" ;;
        nmcli\ -f\ GENERAL.CONNECTION,IP4.DNS,IP4.DOMAIN\ device\ show*) desc="покажет активное соединение, DNS-серверы и DNS-domain по сетевым устройствам" ;;
        nmcli\ -f\ NAME,UUID,TYPE\ connection\ show*) desc="покажет сохранённые NetworkManager-профили, чтобы выбрать нужный PROFILE_NAME" ;;
        nmcli\ connection\ show*) desc="покажет параметры выбранного NetworkManager-профиля; фильтр оставляет только 802.1X-поля" ;;
        nmcli*) desc="покажет состояние сетевых устройств и профилей NetworkManager" ;;
        openssl\ x509*) desc="прочитает X.509-сертификат и покажет Subject, Issuer, начало и окончание срока действия; для DER добавьте -inform DER" ;;
        getent*) desc="проверит разрешение имени через системные NSS/DNS-настройки" ;;
        ip\ -br\ link*) desc="покажет краткое состояние сетевых интерфейсов и link" ;;
        ip\ -br\ addr*) desc="покажет краткий список адресов сетевых интерфейсов" ;;
        ip\ -4\ route*) desc="покажет IPv4-маршруты и маршрут по умолчанию" ;;
        ip\ route\ get*) desc="покажет, через какой интерфейс и шлюз система пойдёт к указанному IP" ;;
        timeout*nc*) desc="проверит установление TCP-соединения с указанным DC/портом и ограничит ожидание 5 секундами" ;;
        findmnt\ -n\ -l\ -t\ cifs\ -o\ TARGET*) desc="покажет локальные TARGET CIFS; arm_info дополнительно выполняет полный readdir и metadata lookup с таймаутом в пользовательском контексте для multiuser" ;;
        findmnt\ -t\ cifs*) desc="покажет активные CIFS-точки монтирования, источник и параметры mount" ;;
        timeout*stat*) desc="проверит доступность конкретной точки монтирования без длительного зависания" ;;
        loginctl\ list-sessions*) desc="покажет активные пользовательские sessions и UID для привязки GVFS к нужному пользователю" ;;
        ps*) desc="покажет процессы и позволит определить зависший или родительский процесс" ;;
        find\ /run/user*) desc="покажет пользовательские GVFS-точки монтирования" ;;
        lpstat\ -r*) desc="проверит, отвечает ли CUPS scheduler" ;;
        lpstat*) desc="покажет состояние очередей/приёма заданий, задания, default printer и backend CUPS" ;;
        cupsctl*) desc="покажет текущие параметры сервера CUPS" ;;
        cupsenable*) desc="возобновит указанную очередь после устранения первичной причины" ;;
        cupsaccept*) desc="разрешит указанной очереди принимать новые задания" ;;
        cancel*) desc="отменит указанное задание печати; выполнять только после подтверждения, что задание можно удалить" ;;
        du\ -sh\ /var/spool/cups*) desc="покажет объём диска, занятый spool CUPS" ;;
        command\ -v*) desc="проверит наличие указанной утилиты в PATH" ;;
        rpm\ -q\ cups-client*) desc="проверит, установлен ли пакет cups-client, обычно содержащий lpstat" ;;
        rpm*) desc="покажет сведения RPM/пакета" ;;
        dnf\ provides*) desc="найдёт пакет из разрешённых репозиториев, который предоставляет указанный исполняемый файл" ;;
        dnf\ install*) desc="установит указанный пакет через DNF после подтверждения транзакции" ;;
        bash*arm_info.sh*|arm_info*) desc="повторно запустит arm_info для контроля результата после исправления" ;;
        *) desc="выполнит диагностическую проверку, связанную с указанной рекомендацией" ;;
    esac

    if [[ $cmd =~ (DOMAIN_FQDN|DC_FQDN|DC_IP|USER_NAME|PROFILE_NAME|CERT_PATH|QUEUE_NAME|JOB_ID|PARENT_PID|UNIT_NAME|DEVICE_PATH|MD_DEVICE|IFACE_NAME) ]]; then
        desc="$desc Перед выполнением замените служебный маркер на фактическое значение из отчёта/системы."
    fi
    case "$cmd" in
        cupsenable*|cupsaccept*|cancel*|dnf\ install*) desc="ИЗМЕНЯЕТ СОСТОЯНИЕ: $desc" ;;
    esac
    printf '%s' "$desc"
}

split_rec_commands() {
    # REC_COMMAND historical format uses an unquoted | as a list separator.
    # Preserve real shell pipelines (" | ") and regex pipes inside quotes.
    local s=$1 current="" quote="" i ch prev next len=${#1}
    for ((i=0; i<len; i++)); do
        ch=${s:i:1}
        if [[ $ch == "'" && $quote != '"' ]]; then
            if [[ $quote == "'" ]]; then quote=""; else quote="'"; fi
            current+=$ch
            continue
        fi
        if [[ $ch == '"' && $quote != "'" ]]; then
            if [[ $quote == '"' ]]; then quote=""; else quote='"'; fi
            current+=$ch
            continue
        fi
        if [[ $ch == '|' && -z $quote ]]; then
            prev=""; next=""
            ((i>0)) && prev=${s:i-1:1}
            ((i+1<len)) && next=${s:i+1:1}
            if [[ $prev != [[:space:]] && $next != [[:space:]] && $prev != '|' && $next != '|' ]]; then
                printf '%s\n' "$current"
                current=""
                continue
            fi
        fi
        current+=$ch
    done
    [[ -n $current ]] && printf '%s\n' "$current"
}

print_rec_command_line() {
    # Команда печатается одной физической строкой. Терминал может визуально
    # перенести её по ширине окна, но в вывод не вставляется перевод строки,
    # поэтому копирование длинной команды не разрывает shell pipeline/аргументы.
    local label=$1 cmd=$2 desc=$3 indent=3 label_w=23
    printf '%*s%s %s\n' "$indent" '' "$(pad_right "$label" "$label_w")" "$cmd"
    print_rec_field '' "($desc)"
}

print_rec_commands() {
    local text=$1 cmd desc idx=0
    while IFS= read -r cmd; do
        [[ -n $cmd ]] || continue
        idx=$((idx+1))
        desc=$(command_description "$cmd")
        print_rec_command_line "Команда $idx:" "$cmd" "$desc"
    done < <(split_rec_commands "$text")
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

_srv_targets() {
    # SRV target "." means that the service is unavailable, not a DC.
    awk 'NF == 4 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $4 != "." {
        host=tolower($4); sub(/\.$/, "", host)
        if (host ~ /^[a-z0-9_][a-z0-9_.-]*$/) print host
    }' | sort -u
}

_tcp_ok() {
    local host=$1 port=$2
    host=${host%.}
    have timeout || return 2
    if have nc; then timeout -k 1 3 nc -z "$host" "$port" >/dev/null 2>&1
    else timeout -k 1 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" >/dev/null 2>&1
    fi
}

check_dns_common() {
    local section=${1:-DNS} domain=${2:-} resolv_target manager dns search_domain fqdn rc ldap_srv krb_srv dc_srv ldap_count krb_count targets target reachable=0 tested=0 untested=0
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
        dc_srv=$(_srv_records "_ldap._tcp.dc._msdcs.$domain")
        ldap_count=$(grep -c . <<<"$ldap_srv" 2>/dev/null || true); krb_count=$(grep -c . <<<"$krb_srv" 2>/dev/null || true)
        if ((ldap_count>0)); then add_check "$section" "dns.srv.ldap" "LDAP SRV" "$ldap_count записей" ok; else add_check "$section" "dns.srv.ldap" "LDAP SRV" "не найден" warn; fi
        if ((krb_count>0)); then add_check "$section" "dns.srv.kerberos" "Kerberos SRV" "$krb_count записей" ok; else add_check "$section" "dns.srv.kerberos" "Kerberos SRV" "не найден" warn; fi

        targets=$(printf '%s\n' "$ldap_srv" "$krb_srv" "$dc_srv" | _srv_targets)
        add_check "$section" "domain.dc.discovery" "Контроллеров по DNS" "$(grep -c . <<<"$targets" || true)" info \
          "Все уникальные узлы из LDAP, Kerberos и AD DC SRV; это обнаруженные узлы, а не список активных соединений АРМ."
        local dc_index=0 krb_rc ldap_rc dc_sev dc_display krb_text ldap_text port
        while IFS= read -r target; do
            [[ -n $target ]] || continue
            dc_index=$((dc_index+1))
            krb_rc=0; ldap_rc=0
            _tcp_ok "$target" 88 || krb_rc=$?
            _tcp_ok "$target" 389 || ldap_rc=$?
            for port in "$krb_rc" "$ldap_rc"; do
                if ((port==2)); then untested=$((untested+1))
                else tested=$((tested+1)); ((port==0)) && reachable=$((reachable+1)); fi
            done
            case $krb_rc in 0) krb_text='доступен';; 2) krb_text='не проверен';; *) krb_text='недоступен';; esac
            case $ldap_rc in 0) ldap_text='доступен';; 2) ldap_text='не проверен';; *) ldap_text='недоступен';; esac
            if ((krb_rc==2 || ldap_rc==2)); then
                dc_sev=unknown
            elif ((krb_rc==0 && ldap_rc==0)); then
                dc_sev=ok
            elif ((krb_rc==0 || ldap_rc==0)); then
                dc_sev=warn
            else
                dc_sev=crit
            fi
            if ((PRIVACY)); then dc_display='скрыто'; else dc_display=$target; fi
            add_check "$section" "domain.dc.node.$dc_index" "Контроллер #$dc_index" \
              "$dc_display — Kerberos 88: $krb_text; LDAP 389: $ldap_text" "$dc_sev"
        done <<<"$targets"
        if ((tested>0)); then
            if ((reachable==tested)); then rc=ok; elif ((reachable>0)); then rc=warn; else rc=crit; fi
            add_check "$section" "domain.dc.ports" "KDC/LDAP доступность" "$reachable из $tested TCP-проверок; не проверены: $untested" "$rc"
        else
            add_check "$section" "domain.dc.ports" "KDC/LDAP доступность" "не проверена" unknown "Нужны SRV-записи и nc/timeout"
        fi
    else
        add_check "$section" "dns.srv" "Доменные SRV" "домен не определён" unknown
    fi
}

check_domain() {
    local d sssd_state join_state kstate cache_count sync_state chrony sssd_logs krb_errors sev
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
        krb_errors=$(awk 'BEGIN{IGNORECASE=1} /(krb5|kerberos)/ && /(error|fail|failure|failed|denied|reject|unable|cannot|expired|clock skew|preauth|not found|unreachable|timeout)/ {n++} END{print n+0}' <<<"$sssd_logs")
        if ((krb_errors>0)); then sev=warn; else sev=ok; fi
        add_check "ДОМЕН / KERBEROS" "kerberos.errors" "Ошибки Kerberos" "$krb_errors" "$sev" "Количество записей с признаками ошибок Kerberos за текущую загрузку"
    else add_check "ДОМЕН / KERBEROS" "kerberos.errors" "Ошибки Kerberos" "journalctl отсутствует" unknown; fi

    check_dns_common "DNS / DOMAIN" "$d"
}


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
    if [[ -n $as_user && $as_user != "$(id -un 2>/dev/null)" && $as_user != "$(id -u)" ]]; then
        ((EUID==0)) || return 125
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
    _cifs_exec_as "$as_user" env LC_ALL=C timeout -k 1 6 ls -U -A -1 -- "$mnt/" >/dev/null 2>"$errfile"
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
    _cifs_exec_as "$as_user" env LC_ALL=C timeout -k 1 6 find "$mnt" -mindepth 1 -maxdepth 1 -print -quit >"$samplefile" 2>"$errfile"
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
        _cifs_exec_as "$as_user" env LC_ALL=C timeout -k 1 6 stat -L -- "$sample" >/dev/null 2>"$errfile"
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

_gvfs_runtime_dirs() {
    # Сначала перечисляем runtime-каталоги, не обращаясь к FUSE от root.
    printf '%s\n' /run/user/[0-9]*
}

check_gvfs() {
    local smb_index=${1:-0} runtime g uid gvfs_user dir name dirs_file errfile rc
    local count=0 good=0 bad=0 unknown=0 discovery_unknown=0 session=0
    local state sev label display detail
    while IFS= read -r runtime; do
        uid=${runtime##*/}
        [[ $uid =~ ^[0-9]+$ ]] || continue
        g=$runtime/gvfs
        session=$((session+1))
        gvfs_user=$(id -nu "$uid" 2>/dev/null || true)
        dirs_file=$(mktemp) || {
            discovery_unknown=$((discovery_unknown+1))
            add_check "SMB / GVFS" "network.gvfs.discovery.$session" "Перечисление GVFS" "нет временного файла для списка" unknown
            continue
        }
        errfile=$(mktemp) || {
            rm -f -- "$dirs_file"; discovery_unknown=$((discovery_unknown+1))
            add_check "SMB / GVFS" "network.gvfs.discovery.$session" "Перечисление GVFS" "нет временного файла для ошибок" unknown
            continue
        }
        rc=125
        if [[ -n $gvfs_user ]] && have timeout && have ls; then
            # ls -U без -l/-F/color перечисляет имена без stat каждого ресурса.
            # Сломанная шара остаётся в списке. Не использовать find -type d.
            _cifs_exec_as "$gvfs_user" env LC_ALL=C timeout -k 1 6 \
              ls -U -A -1 --color=never --quoting-style=literal -- "$g" >"$dirs_file" 2>"$errfile"
            rc=$?
        fi
        if ((rc!=0)) && ! grep -Fq 'No such file or directory' "$errfile"; then
            discovery_unknown=$((discovery_unknown+1))
            display=$(mask_domain "$gvfs_user (UID $uid)")
            add_check "SMB / GVFS" "network.gvfs.discovery.$session" "Перечисление GVFS" \
              "$display; список не получен полностью (rc=$rc)" unknown \
              "Проверить сессию владельца GVFS; отсутствие списка не означает отсутствие подключений."
        fi
        while IFS= read -r name || [[ -n $name ]]; do
            [[ -n $name ]] || continue
            dir=$g/$name
            count=$((count+1))
            _cifs_probe "$dir" "$gvfs_user"
            state=$CIFS_PROBE_STATE
            case $state in
                OK) good=$((good+1)); sev=ok ;;
                INCONCLUSIVE) unknown=$((unknown+1)); sev=unknown ;;
                *) bad=$((bad+1)); sev=warn ;;
            esac
            if [[ $name == smb-share:* ]]; then
                smb_index=$((smb_index+1)); label="SMB-ресурс #$smb_index"
            else label="GVFS-ресурс #$count"; fi
            if ((PRIVACY)); then
                display='ресурс скрыт'
                detail="контекст: скрыто; GVFS; rc=$CIFS_PROBE_RC"
            else
                display=$dir
                detail="контекст: $gvfs_user; GVFS; rc=$CIFS_PROBE_RC"
                [[ -n $CIFS_PROBE_ERR ]] && detail+="; $CIFS_PROBE_ERR"
            fi
            add_check "SMB / GVFS" "network.gvfs.mount.$count" "$label" \
              "$display; $(_cifs_state_text "$state")" "$sev" "$detail"
        done <"$dirs_file"
        rm -f -- "$dirs_file" "$errfile"
    done < <(_gvfs_runtime_dirs)
    if ((count==0 && discovery_unknown==0)); then
        add_check "SMB / GVFS" "network.gvfs" "GVFS mounts" "нет" info
    else
        add_check "SMB / GVFS" "network.gvfs" "GVFS итого" \
          "$count; доступны: $good; проблемы: $bad; не проверены: $unknown; неполных списков: $discovery_unknown" info
    fi
}

check_network() {
    local gw ifaces idx=0 row iface ip mac speed duplex link dns_domain cifs_count=0 cifs_ok=0 cifs_bad=0 cifs_unknown=0 mnt
    local cifs_source cifs_options cifs_multiuser cifs_user cifs_context cifs_state cifs_text cifs_detail cifs_sev cifs_source_display cifs_target_display
    local eap_count=0 active_eap_count=0 cert_global_min=-1 cert_unknown=0 cert_seen=0 cert_index=0 system_ca_profiles=0 uuid type eap conn_name
    local cert_spec cert_kind cert_field cert_label certref certpath cert_display cert_start cert_end start_fmt end_fmt end_epoch now days cert_cmd_path sev
    local cert_meta cert_subject cert_issuer cert_inform phase2_auth phase2_autheap system_ca ca_path private_key phase2_private_key
    local client_ref phase2_client_ref probe_client probe_ca probe_p2_client probe_p2_ca probe_key probe_p2_key active_uuid_list profile_state
    local fallback_cert_count=0 fallback_idx=0 fallback_fqdn fallback_short fallback_path fallback_meta fallback_start fallback_end fallback_start_fmt fallback_end_fmt fallback_end_epoch fallback_days
    local proc_caja proc_gvfs

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

    # В enterprise DNS уже собран check_domain; повтор создавал одинаковые JSON keys.
    if [[ $PROFILE != enterprise ]]; then
        dns_domain=$(_detect_domain); check_dns_common "DNS" "$dns_domain"
    fi

    if have nmcli; then
        # -g включает terse output; на ряде версий NetworkManager двоеточия в file://
        # экранируются. Сначала запрашиваем --escape no, затем используем fallback.
        nm_802_value() {
            local field=$1 id=$2 v
            v=$(nmcli -e no -g "$field" connection show uuid "$id" 2>/dev/null | head -n1)
            if [[ -z $v ]]; then
                v=$(nmcli -g "$field" connection show uuid "$id" 2>/dev/null | head -n1)
                v=${v//\\:/:}
                v=${v//\\\\/\\}
            fi
            printf '%s' "$v"
        }

        active_uuid_list=$(nmcli -t -f UUID connection show --active 2>/dev/null || true)
        while IFS=: read -r uuid type; do
            [[ -n $uuid ]] || continue
            case "$type" in ethernet|802-11-wireless|wifi) ;; *) continue;; esac
            eap=$(nm_802_value 802-1x.eap "$uuid")
            probe_client=$(nm_802_value 802-1x.client-cert "$uuid")
            probe_ca=$(nm_802_value 802-1x.ca-cert "$uuid")
            probe_p2_client=$(nm_802_value 802-1x.phase2-client-cert "$uuid")
            probe_p2_ca=$(nm_802_value 802-1x.phase2-ca-cert "$uuid")
            probe_key=$(nm_802_value 802-1x.private-key "$uuid")
            probe_p2_key=$(nm_802_value 802-1x.phase2-private-key "$uuid")
            [[ -n $eap || -n $probe_client || -n $probe_ca || -n $probe_p2_client || -n $probe_p2_ca || -n $probe_key || -n $probe_p2_key ]] || continue

            eap_count=$((eap_count+1))
            profile_state="настроен, не активен"
            if grep -Fxq "$uuid" <<<"$active_uuid_list"; then
                profile_state="активен"
                active_eap_count=$((active_eap_count+1))
            fi
            conn_name=$(nm_802_value connection.id "$uuid")
            if ((PRIVACY)); then conn_name="профиль $eap_count (скрыто)"; fi
            add_check "802.1X" "network.8021x.profile.$eap_count" "Профиль 802.1X #$eap_count" "${conn_name:-$uuid}; $profile_state" info
            add_check "802.1X" "network.8021x.eap.$eap_count" "EAP-метод" "${eap:-не указан}" info

            phase2_auth=$(nm_802_value 802-1x.phase2-auth "$uuid")
            phase2_autheap=$(nm_802_value 802-1x.phase2-autheap "$uuid")
            [[ -n $phase2_auth ]] && add_check "802.1X" "network.8021x.phase2-auth.$eap_count" "Phase2 auth" "$phase2_auth" info
            [[ -n $phase2_autheap ]] && add_check "802.1X" "network.8021x.phase2-autheap.$eap_count" "Phase2 EAP" "$phase2_autheap" info

            system_ca=$(nm_802_value 802-1x.system-ca-certs "$uuid")
            ca_path=$(nm_802_value 802-1x.ca-path "$uuid")
            if [[ $system_ca == yes || $system_ca == true || $system_ca == 1 ]]; then
                system_ca_profiles=$((system_ca_profiles+1))
                add_check "802.1X" "network.8021x.system-ca.$eap_count" "Системное хранилище CA" "используется" info
            fi
            if [[ -n $ca_path ]]; then
                if ((PRIVACY)); then ca_path='<CA_PATH>'; fi
                add_check "802.1X" "network.8021x.ca-path.$eap_count" "Каталог CA" "$ca_path" info
            fi

            client_ref=$(nm_802_value 802-1x.client-cert "$uuid")
            phase2_client_ref=$(nm_802_value 802-1x.phase2-client-cert "$uuid")
            private_key=$(nm_802_value 802-1x.private-key "$uuid")
            phase2_private_key=$(nm_802_value 802-1x.phase2-private-key "$uuid")

            # Проверяем внешний и phase2 наборы сертификатов. Поддерживаются file://,
            # обычные пути, PEM и DER. PKCS#11/blob отображаются, но без интерактивного
            # запроса PIN их срок не считается достоверно доступным.
            for cert_spec in \
                "client|802-1x.client-cert|Клиентский сертификат" \
                "ca|802-1x.ca-cert|CA-сертификат" \
                "phase2-client|802-1x.phase2-client-cert|Phase2 клиентский сертификат" \
                "phase2-ca|802-1x.phase2-ca-cert|Phase2 CA-сертификат"
            do
                IFS='|' read -r cert_kind cert_field cert_label <<<"$cert_spec"
                certref=$(nm_802_value "$cert_field" "$uuid")
                [[ -n $certref ]] || continue

                cert_seen=$((cert_seen+1)); cert_index=$((cert_index+1))
                certpath=$certref
                certpath=${certpath#file://}
                certpath=${certpath#file:}
                cert_display=$certref
                if ((PRIVACY)); then
                    case "$cert_kind" in
                        client) cert_display='<CLIENT_CERT>' ;;
                        ca) cert_display='<CA_CERT>' ;;
                        phase2-client) cert_display='<PHASE2_CLIENT_CERT>' ;;
                        *) cert_display='<PHASE2_CA_CERT>' ;;
                    esac
                fi
                add_check "802.1X" "network.8021x.cert.$cert_index.path" "$cert_label" "$cert_display" info

                case "$certref" in
                    pkcs11:*)
                        cert_unknown=$((cert_unknown+1))
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Даты — $cert_label" "не проверены автоматически: сертификат задан PKCS#11 URI" unknown
                        continue
                        ;;
                    blob:*|blob://*)
                        cert_unknown=$((cert_unknown+1))
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Даты — $cert_label" "не проверены автоматически: сертификат хранится как blob" unknown
                        continue
                        ;;
                esac

                if [[ -r $certpath ]] && have openssl; then
                    cert_inform=''
                    cert_meta=$(openssl x509 -in "$certpath" -noout -startdate -enddate -subject -issuer 2>/dev/null || true)
                    if [[ $cert_meta != *notAfter=* ]]; then
                        cert_meta=$(openssl x509 -inform DER -in "$certpath" -noout -startdate -enddate -subject -issuer 2>/dev/null || true)
                        [[ $cert_meta == *notAfter=* ]] && cert_inform='-inform DER '
                    fi

                    if [[ $cert_meta == *notAfter=* ]]; then
                        cert_start=$(printf '%s\n' "$cert_meta" | sed -n 's/^notBefore=//p' | head -n1)
                        cert_end=$(printf '%s\n' "$cert_meta" | sed -n 's/^notAfter=//p' | head -n1)
                        cert_subject=$(printf '%s\n' "$cert_meta" | sed -n 's/^subject=//p' | head -n1)
                        cert_issuer=$(printf '%s\n' "$cert_meta" | sed -n 's/^issuer=//p' | head -n1)
                        start_fmt=$(date -d "$cert_start" '+%d.%m.%Y %H:%M:%S %Z' 2>/dev/null || printf '%s' "$cert_start")
                        end_fmt=$(date -d "$cert_end" '+%d.%m.%Y %H:%M:%S %Z' 2>/dev/null || printf '%s' "$cert_end")
                        end_epoch=$(date -d "$cert_end" +%s 2>/dev/null || true); now=$(date +%s)

                        if ((PRIVACY)); then cert_subject='скрыто'; cert_issuer='скрыто'; fi
                        [[ -n $cert_subject ]] && add_check "802.1X" "network.8021x.cert.$cert_index.subject" "Subject — $cert_label" "$cert_subject" info
                        [[ -n $cert_issuer ]] && add_check "802.1X" "network.8021x.cert.$cert_index.issuer" "Issuer — $cert_label" "$cert_issuer" info
                        add_check "802.1X" "network.8021x.cert.$cert_index.not_before" "Начало действия — $cert_label" "$start_fmt" info

                        if [[ $end_epoch =~ ^[0-9]+$ ]]; then
                            days=$(((end_epoch-now)/86400))
                            ((cert_global_min<0 || days<cert_global_min)) && cert_global_min=$days
                            if ((days<14)); then sev=crit; elif ((days<30)); then sev=warn; else sev=ok; fi
                            add_check "802.1X" "network.8021x.cert.$cert_index.not_after" "Окончание действия — $cert_label" "$end_fmt" "$sev"
                            add_check "802.1X" "network.8021x.cert.$cert_index.remaining" "Осталось — $cert_label" "${days} дн." "$sev"
                        else
                            cert_unknown=$((cert_unknown+1))
                            add_check "802.1X" "network.8021x.cert.$cert_index.not_after" "Окончание действия — $cert_label" "$end_fmt (дату не удалось преобразовать)" unknown
                        fi

                        cert_cmd_path=$certpath; ((PRIVACY)) && cert_cmd_path='<CERT>'
                        add_check "802.1X" "network.8021x.cert.$cert_index.command" "Проверка срока" "openssl x509 ${cert_inform}-in \"$cert_cmd_path\" -noout -dates -subject -issuer" info
                    else
                        cert_unknown=$((cert_unknown+1))
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Даты — $cert_label" "не прочитаны как PEM или DER" unknown
                        cert_cmd_path=$certpath; ((PRIVACY)) && cert_cmd_path='<CERT>'
                        add_check "802.1X" "network.8021x.cert.$cert_index.command" "Проверка PEM/DER" "openssl x509 -in \"$cert_cmd_path\" -noout -dates || openssl x509 -inform DER -in \"$cert_cmd_path\" -noout -dates" info
                    fi
                else
                    cert_unknown=$((cert_unknown+1))
                    if ! have openssl; then
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Даты — $cert_label" "не проверены: openssl отсутствует" unknown
                    else
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Даты — $cert_label" "не проверены: файл сертификата недоступен: $cert_display" unknown
                    fi
                fi
            done

            # Если EAP-TLS/phase2 TLS использует private-key/PKCS#12, но client-cert
            # отдельно не задан, показываем источник, чтобы профиль не выглядел пустым.
            if [[ -z $client_ref && -n $private_key ]]; then
                cert_display=$private_key; ((PRIVACY)) && cert_display='<PRIVATE_KEY_OR_PKCS12>'
                add_check "802.1X" "network.8021x.private-key.$eap_count" "Источник ключа/PKCS#12" "$cert_display" info
            fi
            if [[ -z $phase2_client_ref && -n $phase2_private_key ]]; then
                cert_display=$phase2_private_key; ((PRIVACY)) && cert_display='<PHASE2_PRIVATE_KEY_OR_PKCS12>'
                add_check "802.1X" "network.8021x.phase2-private-key.$eap_count" "Phase2 ключ/PKCS#12" "$cert_display" info
            fi
            if [[ ($eap == *tls* || $phase2_auth == tls || $phase2_autheap == tls) && -z $client_ref && -z $phase2_client_ref && -z $private_key && -z $phase2_private_key ]]; then
                add_check "802.1X" "network.8021x.client-cert.missing.$eap_count" "Клиентский сертификат" "для TLS не найден в профиле" warn
            fi
        done < <(nmcli -t -f UUID,TYPE connection show 2>/dev/null)

        if ((eap_count>0)); then
            if ((cert_global_min>=0)); then
                if ((cert_global_min<14)); then sev=crit
                elif ((cert_global_min<30)); then sev=warn
                elif ((cert_unknown>0)); then sev=warn
                else sev=ok
                fi
                add_check "802.1X" "network.8021x" "Профили 802.1X" "настроено: $eap_count; активных: $active_eap_count; минимальный остаток сертификата ${cert_global_min} дн.; непроверенных: $cert_unknown" "$sev"
            elif ((cert_seen>0)); then
                add_check "802.1X" "network.8021x" "Профили 802.1X" "настроено: $eap_count; активных: $active_eap_count; сертификаты найдены, но даты не определены; непроверенных: $cert_unknown" unknown
            elif ((system_ca_profiles>0)); then
                add_check "802.1X" "network.8021x" "Профили 802.1X" "настроено: $eap_count; активных: $active_eap_count; используется системное хранилище CA; отдельные сертификаты не заданы" info
            else
                add_check "802.1X" "network.8021x" "Профили 802.1X" "настроено: $eap_count; активных: $active_eap_count; ссылки на сертификаты не обнаружены" unknown
            fi
        else
            add_check "802.1X" "network.8021x" "Профили 802.1X NetworkManager" "не обнаружены" info
        fi
    else
        add_check "802.1X" "network.8021x" "802.1X" "nmcli отсутствует" unknown
    fi

    # Дополнительный поиск сертификата АРМ. Нужен для РЕД ОС, где 802.1X может
    # быть задан legacy ifcfg/wpa_supplicant/внешним механизмом, а nmcli не показывает
    # 802-1x секцию активного профиля. Сертификат помечается как кандидат, пока связь
    # с конкретным профилем не подтверждена.
    if ((cert_seen==0)) && have openssl; then
        fallback_fqdn=$(hostname -f 2>/dev/null || true)
        fallback_short=$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)
        while IFS= read -r fallback_path; do
            [[ -n $fallback_path && -r $fallback_path ]] || continue
            fallback_meta=$(openssl x509 -in "$fallback_path" -noout -startdate -enddate -subject -issuer 2>/dev/null || true)
            [[ $fallback_meta == *notAfter=* ]] || continue
            fallback_cert_count=$((fallback_cert_count+1)); fallback_idx=$((fallback_idx+1))
            cert_display=$fallback_path; ((PRIVACY)) && cert_display='<HOST_CERT_CANDIDATE>'
            add_check "802.1X" "network.8021x.fallback.$fallback_idx.path" "Сертификат АРМ (кандидат 802.1X)" "$cert_display" info
            fallback_start=$(printf '%s\n' "$fallback_meta" | sed -n 's/^notBefore=//p' | head -n1)
            fallback_end=$(printf '%s\n' "$fallback_meta" | sed -n 's/^notAfter=//p' | head -n1)
            fallback_start_fmt=$(date -d "$fallback_start" '+%d.%m.%Y %H:%M:%S %Z' 2>/dev/null || printf '%s' "$fallback_start")
            fallback_end_fmt=$(date -d "$fallback_end" '+%d.%m.%Y %H:%M:%S %Z' 2>/dev/null || printf '%s' "$fallback_end")
            fallback_end_epoch=$(date -d "$fallback_end" +%s 2>/dev/null || true); now=$(date +%s)
            add_check "802.1X" "network.8021x.fallback.$fallback_idx.not_before" "Начало действия — сертификат АРМ" "$fallback_start_fmt" info
            if [[ $fallback_end_epoch =~ ^[0-9]+$ ]]; then
                fallback_days=$(((fallback_end_epoch-now)/86400))
                if ((fallback_days<14)); then sev=crit; elif ((fallback_days<30)); then sev=warn; else sev=ok; fi
                add_check "802.1X" "network.8021x.fallback.$fallback_idx.not_after" "Окончание действия — сертификат АРМ" "$fallback_end_fmt" "$sev"
                add_check "802.1X" "network.8021x.fallback.$fallback_idx.remaining" "Осталось — сертификат АРМ" "${fallback_days} дн." "$sev"
            else
                add_check "802.1X" "network.8021x.fallback.$fallback_idx.not_after" "Окончание действия — сертификат АРМ" "$fallback_end_fmt" unknown
            fi
            cert_cmd_path=$fallback_path; ((PRIVACY)) && cert_cmd_path='<CERT>'
            add_check "802.1X" "network.8021x.fallback.$fallback_idx.command" "Проверка срока" "openssl x509 -in \"$cert_cmd_path\" -noout -dates -subject -issuer" info
        done < <({
            [[ -n $fallback_fqdn ]] && printf '%s\n' "/etc/pki/tls/${fallback_fqdn}.pem" "/etc/pki/tls/certs/${fallback_fqdn}.pem"
            if [[ -n $fallback_short && -d /etc/pki/tls ]]; then
                find /etc/pki/tls /etc/pki/tls/certs -maxdepth 1 -type f -iname "${fallback_short}*.pem" 2>/dev/null
            fi
        } | awk '!seen[$0]++' | head -n5)
        if ((fallback_cert_count>0)); then
            add_check "802.1X" "network.8021x.fallback.source" "Источник сертификата 802.1X" "профиль NetworkManager не подтвердил сертификат; найден host-named сертификат АРМ" unknown
        fi
    fi

    if have findmnt; then
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
            if ((PRIVACY)); then
                cifs_detail="контекст: скрыто; multiuser: $cifs_multiuser"
            else
                cifs_detail="контекст: $cifs_context; multiuser: $cifs_multiuser"
            fi
            # stderr утилит содержит реальный путь/имя даже при маскировке строки.
            if [[ -n $CIFS_PROBE_ERR ]] && ((PRIVACY==0)); then cifs_detail="$cifs_detail; $CIFS_PROBE_ERR"; fi
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

    check_gvfs "$cifs_count"
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

check_software() {
    local rows count zombies processes pkg version key
    if have rpm; then
        rows=$(rpm -qa --qf '%{NAME}.%{ARCH}|%{VERSION}-%{RELEASE}
' 2>/dev/null | LC_ALL=C sort -f)
        count=$(grep -c . <<<"$rows" 2>/dev/null || true)
        add_check "ИНВЕНТАРИЗАЦИЯ ПО" "software.total" "Установлено RPM-пакетов" "$count" info
        while IFS='|' read -r pkg version; do
            [[ -n $pkg ]] || continue
            key=$(printf '%s' "$pkg" | tr -c '[:alnum:]_.+-' '_')
            add_check "ИНВЕНТАРИЗАЦИЯ ПО" "software.package.$key" "$pkg" "$version" info
        done <<<"$rows"
    else
        add_check "ИНВЕНТАРИЗАЦИЯ ПО" "software.rpm" "RPM inventory" "rpm отсутствует" unknown
    fi

    processes=$(ps -e --no-headers 2>/dev/null | wc -l | tr -d ' ')
    [[ $processes =~ ^[0-9]+$ ]] || processes=0
    add_check "ПРОЦЕССЫ" "software.processes.total" "Активные процессы" "$processes" info

    zombies=$(ps -eo stat= 2>/dev/null | awk '$1 ~ /^Z/{n++} END{print n+0}')
    if ((zombies>0)); then
        add_check "ПРОЦЕССЫ" "software.zombies" "Zombie-процессы" "$zombies" warn
    else
        add_check "ПРОЦЕССЫ" "software.zombies" "Zombie-процессы" "0" ok
    fi
}

emit_text() {
    local current="" i sevmark n=0 width
    width=$(report_width)
    printf 'ARM_INFO КОРПОРАТИВНЫЙ %s\n' "$VERSION"
    if [[ $PROFILE == enterprise ]]; then
        printf 'Профиль: корпоративный\n'
    else
        printf 'Профиль: %s\n' "$PROFILE"
    fi
    printf 'Дата: %s\n' "$(date '+%d.%m.%Y %H:%M:%S')"
    ((PRIVACY)) && printf 'Privacy: включён\n'
    if [[ -n $OUTPUT_PATH ]] && ((SAVE_REPORT==1)); then
        printf 'Отчёт: %s\n' "$OUTPUT_PATH"
    elif [[ $PROFILE == enterprise ]] && ((SAVE_REPORT==0)); then
        printf 'Сохранение: отключено ()\n'
    fi

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
    if [[ -n $OUTPUT_PATH ]] && ((SAVE_REPORT==1)); then
        printf '\nОтчёт сохранён: %s\n' "$OUTPUT_PATH"
    fi
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
    printf '\n  ],\n'
    printf '  "recommendations": [\n'
    comma=""
    for i in "${!REC_KEYS[@]}"; do
        printf '%s    {"key":"%s","level":"%s","title":"%s","source":"%s","possible_causes":"%s","impact":"%s","checks":"%s","action":"%s","commands":[' \
          "$comma" "$(json_escape "${REC_KEYS[i]}")" "$(json_escape "${REC_LEVELS[i]}")" "$(json_escape "${REC_TITLES[i]}")" "$(json_escape "${REC_SOURCES[i]}")" \
          "$(json_escape "${REC_CAUSES[i]}")" "$(json_escape "${REC_IMPACTS[i]}")" "$(json_escape "${REC_CHECKS[i]}")" "$(json_escape "${REC_ACTIONS[i]}")"
        local cmd ccomma=""
        while IFS= read -r cmd; do
            [[ -n $cmd ]] || continue
            printf '%s"%s"' "$ccomma" "$(json_escape "$cmd")"
            ccomma=','
        done < <(split_rec_commands "${REC_COMMANDS[i]}")
        printf '],"verification":"%s"}' "$(json_escape "${REC_VERIFIES[i]}")"
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
    enterprise) check_domain; check_network; check_print ;;
esac

build_recommendations
if ((JSON_MODE)); then emit_json; else emit_text; fi

if [[ -n $OUTPUT_PATH ]] && ((SAVE_REPORT==1)); then
    chmod 0644 "$OUTPUT_PATH" 2>/dev/null || true
    if [[ "${SUDO_UID:-}" =~ ^[0-9]+$ && "${SUDO_GID:-}" =~ ^[0-9]+$ ]]; then
        chown "$SUDO_UID:$SUDO_GID" "$OUTPUT_PATH" 2>/dev/null || true
    fi
fi

if ((CRIT_COUNT>0)); then exit 2
elif ((WARN_COUNT>0)); then exit 1
elif ((UNKNOWN_COUNT>0)); then exit 3
else exit 0
fi
)

_arm_enterprise_requested=0
for _arm_arg in "$@"; do
    case "$_arm_arg" in
        -c|--corp|--profile|--profile=*|--compare) _arm_enterprise_requested=1; break ;;
    esac
done
if ((_arm_enterprise_requested)); then
    _arm_enterprise_run "$@"
    exit $?
fi

# -------------------- НАСТРОЙКИ ПО УМОЛЧАНИЮ --------------------
# Значения можно переопределить в /etc/arm_info.conf или через --config.
FS_WARN=80
FS_HIGH=90
FS_CRIT=95
INODE_WARN=80
CPU_TEMP_WARN=80
CPU_TEMP_HIGH=85
CPU_TEMP_VHIGH=90
CPU_TEMP_CRIT=95
HDD_TEMP_WARN=50
HDD_TEMP_HIGH=60
HDD_TEMP_CRIT=65
SSD_TEMP_WARN=60
SSD_TEMP_HIGH=70
SSD_TEMP_CRIT=80
NVME_TEMP_WARN=70
NVME_TEMP_HIGH=80
NVME_TEMP_CRIT=90
SSD_LIFE_PLAN=30
SSD_LIFE_WARN=20
SSD_LIFE_CRIT=10
NET_ERROR_NOTICE_PPM=10
NET_ERROR_WARN_PPM=100
NET_ERROR_CRIT_PPM=1000
NET_DROP_WARN_PPM=1000
NET_DROP_HIGH_PPM=5000
NET_DROP_CRIT_PPM=10000
REPORT_DIR_DEFAULT=""
PRIVACY_DEFAULT=0

CONFIG_FILE="/etc/arm_info.conf"
PRIVACY_MODE=$PRIVACY_DEFAULT
SAVE_REPORT=0
QUIET_MODE=0
JSON_MODE=0
OUTPUT_PATH=""
SHOW_HELP=0

usage() {
    cat <<'EOF'
arm_info — диагностика технического состояния Linux-АРМ

Использование:
  bash arm_info.sh [параметры]

Параметры:
  -h, --help              показать справку
  -V, --version           показать версию
  -p, --privacy           обезличить hostname, IP, MAC, DNS и имена интерфейсов
  -s, --save              сохранить отчёт в файл
  -o, --output PATH       сохранить отчёт в указанный файл или каталог
  -q, --quiet             не выводить отчёт в терминал (имеет смысл с сохранением)
  --json                  вывести отчёт в JSON вместо текстового формата
  --config PATH           использовать другой конфигурационный файл
  -c, --corp              сокращённый запуск corporate-профиля: domain+network+print
  --profile NAME          domain|network|print|software|enterprise
  --compare A.json B.json сравнить два JSON-отчёта АРМ

Коды завершения:
  0  состояние нормальное, проверка достаточно полная
  1  обнаружены предупреждения/неудовлетворительное состояние
  2  обнаружено критическое состояние
  3  состояние нормальное, но диагностика неполная
EOF
}

# Разбираем CLI только при запуске как файла; при вставке в терминал аргументов нет.
while (($#)); do
    case "$1" in
        -h|--help) SHOW_HELP=1; shift ;;
        -V|--version) echo "arm_info $ARM_INFO_VERSION"; exit 0 ;;
        -p|--privacy) PRIVACY_MODE=1; shift ;;
        -s|--save) SAVE_REPORT=1; shift ;;
        -q|--quiet) QUIET_MODE=1; shift ;;
        --json) JSON_MODE=1; shift ;;
        -o|--output)
            [ $# -ge 2 ] || { echo "Ошибка: для $1 требуется путь." >&2; exit 64; }
            OUTPUT_PATH=$2; shift 2 ;;
        --config)
            [ $# -ge 2 ] || { echo "Ошибка: для $1 требуется путь." >&2; exit 64; }
            CONFIG_FILE=$2; shift 2 ;;
        --) shift; break ;;
        *) echo "Ошибка: неизвестный параметр: $1" >&2; usage >&2; exit 64 ;;
    esac
done
((SHOW_HELP==1)) && { usage; exit 0; }
if [[ -n $OUTPUT_PATH && $SAVE_REPORT -ne 1 ]]; then
    echo "Ошибка: -o/--output используется только вместе с -s/--save" >&2
    exit 64
fi
if ((QUIET_MODE==1 && SAVE_REPORT==0)); then
    echo "Ошибка: -q/--quiet используется только вместе с -s/--save" >&2
    exit 64
fi

# Безопасно читаем только разрешённые ключи KEY=VALUE. Конфиг не source-ится.
load_config() {
    local file=$1 key val
    [ -r "$file" ] || return 0
    while IFS='=' read -r key val; do
        key=$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        val=${val%%#*}; val=$(printf '%s' "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$key" in
            FS_WARN|FS_HIGH|FS_CRIT|INODE_WARN|CPU_TEMP_WARN|CPU_TEMP_HIGH|CPU_TEMP_VHIGH|CPU_TEMP_CRIT|HDD_TEMP_WARN|HDD_TEMP_HIGH|HDD_TEMP_CRIT|SSD_TEMP_WARN|SSD_TEMP_HIGH|SSD_TEMP_CRIT|NVME_TEMP_WARN|NVME_TEMP_HIGH|NVME_TEMP_CRIT|SSD_LIFE_PLAN|SSD_LIFE_WARN|SSD_LIFE_CRIT|NET_ERROR_NOTICE_PPM|NET_ERROR_WARN_PPM|NET_ERROR_CRIT_PPM|NET_DROP_WARN_PPM|NET_DROP_HIGH_PPM|NET_DROP_CRIT_PPM|PRIVACY_DEFAULT)
                [[ "$val" =~ ^[0-9]+$ ]] && printf -v "$key" '%s' "$val" ;;
            REPORT_DIR_DEFAULT) REPORT_DIR_DEFAULT=$val ;;
        esac
    done < "$file"
}
load_config "$CONFIG_FILE"

# --privacy имеет приоритет над значением по умолчанию; если флаг не указан, применяем конфиг.
if ((PRIVACY_MODE==0 && PRIVACY_DEFAULT==1)); then PRIVACY_MODE=1; fi

WIDTH=${COLUMNS:-}
if [[ ! $WIDTH =~ ^[0-9]+$ ]] && command -v tput >/dev/null 2>&1; then WIDTH=$(tput cols 2>/dev/null || true); fi
[[ $WIDTH =~ ^[0-9]+$ ]] || WIDTH=110
((WIDTH<92)) && WIDTH=92
((WIDTH>132)) && WIDTH=132
line() { printf '%*s\n' "$WIDTH" '' | tr ' ' '-'; }
section() { echo; echo "$1"; line; }
table() {
    if command -v column >/dev/null 2>&1; then column -t -s '|'; else tr '|' ' '; fi
}
min_score() { (( $2 < $1 )) && echo "$2" || echo "$1"; }
clamp_score() { local v="$1"; ((v<0))&&v=0; ((v>100))&&v=100; echo "$v"; }


ru_plural() {
    local n=$1 one=$2 few=$3 many=$4 n10 n100
    n10=$((n % 10)); n100=$((n % 100))
    if ((n100>=11 && n100<=14)); then printf '%s' "$many"
    elif ((n10==1)); then printf '%s' "$one"
    elif ((n10>=2 && n10<=4)); then printf '%s' "$few"
    else printf '%s' "$many"
    fi
}

format_uptime_ru() {
    local seconds total_minutes days hours minutes out=""
    if [[ -r /proc/uptime ]]; then
        seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
    fi
    [[ ${seconds:-} =~ ^[0-9]+$ ]] || { printf 'Не определено'; return; }
    total_minutes=$((seconds / 60))
    days=$((total_minutes / 1440))
    hours=$(((total_minutes % 1440) / 60))
    minutes=$((total_minutes % 60))
    if ((days>0)); then out="$days $(ru_plural "$days" 'день' 'дня' 'дней')"; fi
    if ((hours>0)); then [[ -n $out ]] && out+=" "; out+="$hours $(ru_plural "$hours" 'час' 'часа' 'часов')"; fi
    if ((minutes>0 || (days==0 && hours==0))); then [[ -n $out ]] && out+=" "; out+="$minutes $(ru_plural "$minutes" 'минута' 'минуты' 'минут')"; fi
    printf '%s' "$out"
}

format_years_ru_from_months() {
    local months=$1 tenths whole frac
    [[ $months =~ ^[0-9]+$ ]] || { printf 'Не определён'; return; }
    tenths=$(((months * 10 + 6) / 12))
    whole=$((tenths / 10)); frac=$((tenths % 10))
    if ((frac==0)); then
        printf '%d %s' "$whole" "$(ru_plural "$whole" 'год' 'года' 'лет')"
    else
        printf '%d,%d года' "$whole" "$frac"
    fi
}

REC_LEVELS=(); REC_TITLES=(); REC_CAUSES=(); REC_IMPACTS=(); REC_DIAGNOSTICS=(); REC_ACTIONS=(); REC_CHECKS=(); REC_VERIFICATIONS=()
add_rec() {
    local level=$1 title=$2 impact=$3 action=$4 command=${5:-}
    local cause diagnostic verification

    cause="Показатель вышел за нормальное состояние либо его достоверная проверка ограничена. Причину следует подтвердить по фактическому состоянию АРМ и системным журналам."
    diagnostic="Повторно проверить показатель, сопоставить его с журналом текущей загрузки и, если возможно, с исправным АРМ аналогичной конфигурации."
    verification="После устранения первичной причины повторный запуск arm_info должен показать нормализацию показателя и отсутствие новых связанных ошибок."

    case "$title" in
        SMART*)
            cause="SMART недоступен полностью или частично: smartctl может отсутствовать, накопитель/контроллер может не поддерживать прямой SMART-доступ либо требовать иной device type."
            diagnostic="Определить все накопители и способ их подключения, выполнить smartctl --scan-open, затем проверить SMART каждого физического диска и сообщения ядра по storage/I/O."
            verification="SMART должен читаться для всех поддерживаемых фиксированных накопителей; в повторном отчёте полнота диагностики должна увеличиться."
            ;;
        ФС*заполнена*)
            cause="Обычно место занимают пользовательские данные, журналы, кэши, временные файлы, старые пакеты или удалённые, но всё ещё открытые процессами файлы."
            diagnostic="Проверить df, крупнейшие каталоги в пределах этой ФС, размер журналов и наличие удалённых открытых файлов. Перед удалением определить владельца данных и назначение каталога."
            verification="Заполнение должно вернуться ниже предупреждающего порога, запись в ФС должна выполняться без ENOSPC, а рост свободного места — сохраняться после повторной проверки."
            ;;
        Inode*)
            cause="Высокое использование inode обычно связано с очень большим числом мелких файлов: кэшами, spool, временными данными, логами или каталогами приложений."
            diagnostic="Сравнить df -i по точкам монтирования и найти каталоги с аномально большим количеством файлов; не удалять служебные каталоги без понимания назначения."
            verification="Использование inode должно снизиться ниже порога и создание новых файлов должно проходить без ошибки No space left on device."
            ;;
        *read-only*)
            cause="Корневая ФС могла перейти в read-only после ошибок файловой системы, I/O, накопителя, контроллера, кабеля или питания."
            diagnostic="Зафиксировать findmnt и kernel journal, проверить SMART и I/O-ошибки. fsck выполнять только в безопасном режиме на размонтированной файловой системе."
            verification="После устранения причины корневая ФС должна штатно монтироваться RW, а новые filesystem/I/O ошибки не должны появляться в журнале."
            ;;
        *ОЗУ*|*запас\ ОЗУ*)
            cause="Недостаток доступной памяти может быть вызван реальной рабочей нагрузкой, утечкой памяти, слишком большим числом процессов либо недостаточным объёмом RAM."
            diagnostic="Проверить MemAvailable, swap, крупнейшие процессы по RSS/%MEM и динамику потребления. Одноразовый снимок не считать доказательством утечки."
            verification="При типовой нагрузке должен оставаться стабильный запас MemAvailable, не должно быть новых OOM, а swap не должен постоянно расти из-за дефицита RAM."
            ;;
        *OOM-killer*)
            cause="Ядро исчерпало доступную память/commit и принудительно завершило процесс. Причиной может быть пик нагрузки, утечка, слишком маленький swap либо ограничение cgroup."
            diagnostic="Найти OOM-событие и killed process в kernel journal, проверить состояние памяти до/после инцидента, лимиты cgroup и самые ресурсоёмкие процессы."
            verification="При воспроизведении штатной нагрузки новые OOM-kill события не должны появляться; запас памяти должен оставаться предсказуемым."
            ;;
        *failed-службы*)
            cause="Служба могла завершиться из-за ошибки конфигурации, недоступной зависимости, сети, прав, файла/сертификата или аппаратной проблемы."
            diagnostic="Для каждой failed-unit сначала изучить systemctl status и журнал именно этой unit, начиная с первой ошибки, а не с последствий каскадного сбоя."
            verification="systemctl --failed не должен содержать критичные для АРМ службы; исправленная unit должна быть active либо штатно inactive по своему назначению."
            ;;
        *аппаратные/дисковые\ ошибки*)
            cause="Kernel hardware/storage errors могут указывать на накопитель, контроллер, кабель, питание, память или драйвер; одна строка журнала не определяет неисправный компонент автоматически."
            diagnostic="Сгруппировать kernel-сообщения по устройству и времени, сопоставить с SMART, I/O counters, EDAC и моментом пользовательского сбоя."
            verification="После исправления аппаратной/связной причины новые I/O/hardware errors не должны появляться, а SMART/EDAC не должны показывать ухудшение."
            ;;
        *journal*)
            cause="Большое число уникальных error-сообщений может быть следствием одной первичной ошибки или нескольких независимых проблем служб/драйверов."
            diagnostic="Отсортировать ошибки по unit/kernel subsystem и времени, определить повторяемость и найти самую раннюю первичную ошибку до каскадных сообщений."
            verification="После исправления первичной причины число новых ошибок за сопоставимый период должно снизиться, а затронутые функции работать стабильно."
            ;;
        *температура\ CPU*)
            cause="Перегрев возможен из-за пыли, остановки/деградации вентилятора, плохого контакта радиатора, старого термоинтерфейса, высокой температуры среды или длительной нагрузки."
            diagnostic="Сопоставить температуру с текущей нагрузкой, оборотами вентиляторов (если доступны), чистотой системы охлаждения и повторить замер после стабилизации нагрузки."
            verification="При типовой нагрузке температура должна устойчиво оставаться ниже порогов, без thermal throttling и аварийных thermal-сообщений."
            ;;
        *системная\ нагрузка*)
            cause="Высокий Load Average может означать загрузку CPU или процессы в непрерываемом ожидании I/O; сам Load без контекста не показывает источник."
            diagnostic="Проверить top/ps, процессы в D-state, iostat/vmstat при наличии и нагрузку дисков/сети; сравнить с нормальной рабочей нагрузкой."
            verification="После устранения источника Load1 должен соответствовать числу потоков CPU и штатному профилю нагрузки, а задержки пользователя исчезнуть."
            ;;
        Эксплуатационный*)
            cause="Возраст является только эксплуатационным ориентиром, а не доказательством износа конкретного узла. Риск оценивается вместе со SMART, охлаждением, БП и историей сбоев."
            diagnostic="Проверить резервное копирование, SMART/наработку накопителей, охлаждение, состояние вентиляторов и историю аппаратных ошибок."
            verification="План профилактики/замены должен учитывать фактические показатели и критичность АРМ; сама возрастная рекомендация после обслуживания может оставаться."
            ;;
        *активный\ IPv4-интерфейс*)
            cause="Нет рабочего IPv4 из-за link down, кабеля/порта, драйвера, NetworkManager-профиля, DHCP/статической настройки или сетевой аутентификации."
            diagnostic="Проверить link/state, адреса, активный профиль, журнал NetworkManager и при наличии 802.1X — состояние EAP/сертификатов."
            verification="Интерфейс должен быть UP с корректным IPv4, маршрутом и DNS; необходимые инфраструктурные узлы должны быть доступны."
            ;;
        *маршрут\ по\ умолчанию*)
            cause="Default route отсутствует из-за неполной IP-конфигурации, сетевого профиля или ошибки DHCP/статического шлюза."
            diagnostic="Сопоставить ip route с параметрами активного NetworkManager-профиля и проверить достижимость предполагаемого шлюза."
            verification="Должен появиться корректный default route через ожидаемый интерфейс; маршрутизация до нужных сетей должна проходить без обходных ручных правил."
            ;;
        *DNS-серверы\ не\ определены*)
            cause="DNS не получен/не задан в активном профиле либо generated resolv.conf/stub не содержит рабочего upstream."
            diagnostic="Проверить resolv.conf, resolvectl (если используется), NetworkManager IP4.DNS/IP4.DOMAIN и разрешение FQDN/доменных SRV."
            verification="Должны определяться рабочие DNS upstream и стабильно разрешаться FQDN, включая необходимые доменные SRV-записи."
            ;;
        *сетевых\ ошибок/учитываемых\ потерь*)
            cause="В оценке сети учитываются RX/TX errors, rx_missed_errors и tx_dropped. Общий rx_dropped выводится отдельно как диагностический счётчик и сам по себе не считается неисправностью, потому что может включать штатные L2/filter drops."
            diagnostic="Проверить ip -s -s link и ethtool -S по конкретному интерфейсу. Особое внимание: rx_missed_errors, CRC/frame/FIFO/carrier и tx_dropped; общий rx_dropped сопоставлять с ними, а не трактовать отдельно как потерю полезного трафика."
            verification="RX/TX errors, rx_missed_errors и tx_dropped не должны систематически расти при нормальной нагрузке; информационный rx_dropped может расти без снижения score, если учитываемые ошибки/потери остаются ниже порогов."
            ;;
        *время\ не\ синхронизировано*)
            cause="NTP/chrony источник недоступен, служба времени остановлена, неверно настроена либо системное время слишком сильно отклонено."
            diagnostic="Проверить timedatectl, chronyc tracking/sources, журнал службы времени и сетевую доступность разрешённых NTP-источников."
            verification="Система должна показывать синхронизацию, а offset/stratum — стабильные значения; Kerberos не должен выдавать ошибки, связанные со временем."
            ;;
        *аварийного\ завершения*)
            cause="Предыдущая загрузка могла завершиться из-за отключения питания, зависания, kernel panic/watchdog, аппаратного сбоя или принудительной перезагрузки."
            diagnostic="Изучить конец журнала предыдущей загрузки, last -x, kernel warning/error и сопоставить время с внешними событиями/обращением пользователя."
            verification="Последующие выключения/перезагрузки должны быть штатными; признаки panic/watchdog/I/O/power ошибок не должны повторяться."
            ;;
        *RAID*DEGRADED*)
            cause="Software RAID потерял резервирование: один или несколько членов массива отсутствуют/failed/removed либо идёт незавершённое восстановление."
            diagnostic="Проверить /proc/mdstat и mdadm --detail всех md-устройств, затем SMART каждого физического члена."
            verification="Массив должен вернуться в clean/active с ожидаемым числом членов; resync/recovery должен завершиться без новых disk errors."
            ;;
        ECC:*)
            cause="EDAC зафиксировал исправленные или неисправимые ошибки памяти. Причиной может быть DIMM, слот, контроллер памяти, питание или редкий transient event."
            diagnostic="Зафиксировать CE/UE по контроллерам/каналам, проверить рост счётчиков, журнал EDAC/MCE и провести аппаратный memory test в окно обслуживания."
            verification="UE не должны повторяться; CE не должны расти систематически. После замены/перестановки модуля счётчики и аппаратные тесты должны быть стабильны."
            ;;
        *батареи*)
            cause="Расчётная full capacity заметно ниже design capacity; это типичный признак естественного износа аккумулятора."
            diagnostic="Сопоставить energy-full/design, cycle count (если доступен), реальную автономность и наличие внезапных падений заряда."
            verification="После замены/обслуживания health и фактическая автономность должны соответствовать требованиям; при сохранении батареи контролировать дальнейшую деградацию."
            ;;
        SSSD*)
            cause="SSSD установлен, но не активен/нештатен; возможны ошибки конфигурации, DNS, времени, Kerberos, доступа к DC или локальной БД SSSD."
            diagnostic="Проверить status, config-check/domain-list и journalctl -u sssd; отдельно убедиться в корректности DNS и времени до очистки кэшей или повторного join."
            verification="SSSD должен быть active, домен доступен, разрешение пользователей/групп и штатная доменная аутентификация должны проходить без новых ошибок."
            ;;
        CUPS*)
            cause="CUPS не активен при настроенных очередях из-за ошибки службы, backend, конфигурации, фильтра, аутентификации или устройства."
            diagnostic="Проверить cups.service, scheduler, lpstat -p/-v, незавершённые jobs и журнал CUPS до попытки возобновления/очистки очереди."
            verification="CUPS должен быть active, scheduler отвечать, нужные очереди не быть paused, а тестовое задание завершаться штатно."
            ;;
    esac

    REC_LEVELS+=("$level"); REC_TITLES+=("$title"); REC_CAUSES+=("$cause"); REC_IMPACTS+=("$impact")
    REC_DIAGNOSTICS+=("$diagnostic"); REC_ACTIONS+=("$action"); REC_CHECKS+=("$command"); REC_VERIFICATIONS+=("$verification")
}
base_pad_right() {
    local value=$1 width=$2 len=${#1}
    printf '%s' "$value"
    ((len<width)) && printf '%*s' "$((width-len))" ''
}

print_wrapped() {
    local label="$1" text="$2" indent=3 label_w=23 gap=1 value_w first=1 ln
    value_w=$((WIDTH-indent-label_w-gap))
    ((value_w<32)) && value_w=32
    while IFS= read -r ln || [[ -n $ln ]]; do
        if ((first)); then
            printf '%*s%s %s\n' "$indent" '' "$(base_pad_right "$label" "$label_w")" "$ln"
            first=0
        else
            printf '%*s%s %s\n' "$indent" '' "$(base_pad_right '' "$label_w")" "$ln"
        fi
    done < <(printf '%s\n' "$text" | fold -s -w "$value_w")
    ((first==0)) || printf '%*s%s\n' "$indent" '' "$label"
}

base_print_command_line() {
    # Как и в корпоративном отчёте, команда остаётся одной физической строкой.
    # Перенос выполняет только терминал визуально, что сохраняет копируемую строку.
    local label=$1 cmd=$2 desc=$3 indent=3 label_w=23
    printf '%*s%s %s\n' "$indent" '' "$(base_pad_right "$label" "$label_w")" "$cmd"
    print_wrapped '' "($desc)"
}

base_command_description() {
    local cmd=$1 desc
    case "$cmd" in
        journalctl\ --list-boots*) desc="покажет доступные загрузки в journal и их номера для выбора предыдущей загрузки" ;;
        journalctl\ -k*) desc="покажет сообщения ядра текущей загрузки для поиска аппаратных, дисковых и драйверных ошибок" ;;
        journalctl\ -b\ -p\ err..alert*) desc="покажет ошибки уровня error и выше за текущую загрузку" ;;
        journalctl*) desc="покажет системный журнал, относящийся к диагностируемой проблеме" ;;
        systemctl\ --failed*) desc="покажет службы systemd, завершившиеся с ошибкой" ;;
        systemctl\ status*) desc="покажет подробное состояние выбранной службы и последние сообщения о её запуске" ;;
        smartctl\ --scan-open*) desc="покажет накопители, которые smartctl смог обнаружить и открыть, включая тип доступа" ;;
        smartctl*) desc="покажет SMART-состояние и диагностические атрибуты указанного накопителя" ;;
        dnf\ install\ smartmontools*) desc="установит пакет smartmontools после подтверждения транзакции DNF" ;;
        du\ --inodes*) desc="покажет каталоги верхнего уровня с наибольшим количеством inode; на большой ФС проверка может занять время" ;;
        du\ -xhd1*) desc="покажет размеры каталогов первого уровня в пределах выбранной файловой системы" ;;
        df\ -h*) desc="покажет заполнение файловой системы и доступное место" ;;
        df\ -i*) desc="покажет использование inode файловой системы" ;;
        findmnt\ -n\ -l\ -t\ cifs\ -o\ TARGET*) desc="автоматически проверит фактическое чтение каждого локального TARGET CIFS через find с таймаутом; SOURCE вида //server/share не используется" ;;
        findmnt*) desc="покажет источник, тип и параметры монтирования файловой системы" ;;
        ps\ -eo*|ps\ aux*) desc="покажет процессы с сортировкой для поиска основных потребителей ресурсов" ;;
        free\ -h*) desc="покажет использование ОЗУ и swap" ;;
        vmstat*) desc="снимет несколько кратких замеров CPU, run queue, памяти, swap и I/O" ;;
        top\ -b*) desc="сделает одноразовый неинтерактивный снимок процессов и нагрузки" ;;
        sensors*) desc="покажет температуры и другие датчики, доступные через lm_sensors" ;;
        timedatectl*) desc="покажет системное время и состояние синхронизации" ;;
        chronyc*) desc="покажет состояние/источник синхронизации chrony; если chronyc не установлен, команда будет недоступна" ;;
        cat\ /proc/mdstat*) desc="покажет обнаруженные Linux software RAID и состояние их членов" ;;
        mdadm*) desc="покажет подробное состояние выбранного software RAID; замените MD_DEVICE" ;;
        grep*power_supply*) desc="покажет доступные sysfs-показатели батареи: ёмкость, design/full и циклы" ;;
        grep*edac*) desc="покажет счётчики corrected/uncorrectable ECC из EDAC" ;;
        ip\ -s\ link*) desc="покажет RX/TX counters, errors и dropped по сетевым интерфейсам" ;;
        ip\ -br\ addr*) desc="покажет краткий список интерфейсов и IPv4/IPv6-адресов" ;;
        ip\ -4\ route*) desc="покажет IPv4-маршруты и default route" ;;
        ethtool*) desc="покажет link, speed, duplex и параметры интерфейса; если ethtool не установлен, команда будет недоступна" ;;
        cat\ /etc/resolv.conf*) desc="покажет текущий resolv.conf и источник DNS/search-domain, видимый libc" ;;
        nmcli*) desc="покажет DNS и параметры активных NetworkManager-соединений" ;;
        resolvectl*) desc="покажет DNS/upstream по интерфейсам systemd-resolved; команда может отсутствовать на системах без resolved" ;;
        bash*arm_info.sh*|arm_info*) desc="повторно запустит arm_info для планового контроля" ;;
        *) desc="покажет диагностические данные для проверки этой рекомендации" ;;
    esac
    if [[ $cmd =~ (UNIT_NAME|DEVICE_PATH|MD_DEVICE|IFACE_NAME) ]]; then
        desc="$desc Перед выполнением замените служебный маркер на фактическое значение."
    fi
    case "$cmd" in
        dnf\ install*) desc="ИЗМЕНЯЕТ СОСТОЯНИЕ: $desc" ;;
    esac
    printf '%s' "$desc"
}

base_split_commands() {
    local s=$1 current="" quote="" i ch len=${#1}
    for ((i=0; i<len; i++)); do
        ch=${s:i:1}
        if [[ -n $quote ]]; then
            current+=$ch
            [[ $ch == "$quote" ]] && quote=""
            continue
        fi
        case "$ch" in
            "'"|'"') quote=$ch; current+=$ch ;;
            ';')
                current=$(printf '%s' "$current" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [[ -n $current ]] && printf '%s
' "$current"
                current=""
                ;;
            *) current+=$ch ;;
        esac
    done
    current=$(printf '%s' "$current" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -n $current ]] && printf '%s
' "$current"
}

base_print_rec_commands() {
    local text=$1 cmd desc idx=0
    while IFS= read -r cmd; do
        [[ -n $cmd ]] || continue
        idx=$((idx+1))
        desc=$(base_command_description "$cmd")
        base_print_command_line "Команда $idx:" "$cmd" "$desc"
    done < <(base_split_commands "$text")
}

run_smart() {
    if command -v timeout >/dev/null 2>&1; then timeout 8 smartctl "$@"; else smartctl "$@"; fi
}

read_cpu_temp_once() {
    local h name f raw t z type vals=()
    for h in /sys/class/hwmon/hwmon*; do
        [ -r "$h/name" ] || continue
        name=$(tr '[:upper:]' '[:lower:]' < "$h/name" 2>/dev/null)
        case "$name" in coretemp|k10temp|zenpower|cpu_thermal|soc_thermal) ;; *) continue ;; esac
        for f in "$h"/temp*_input; do
            [ -r "$f" ] || continue
            raw=$(cat "$f" 2>/dev/null); [[ "$raw" =~ ^-?[0-9]+$ ]] || continue
            if ((raw>1000 || raw< -1000)); then t=$(((raw+500)/1000)); else t=$raw; fi
            ((t>0 && t<150)) && vals+=("$t")
        done
    done
    if ((${#vals[@]}==0)); then
        for z in /sys/class/thermal/thermal_zone*; do
            [ -r "$z/temp" ] || continue
            type=$(cat "$z/type" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            case "$type" in *cpu*|*x86_pkg_temp*|*coretemp*|*k10temp*|*tctl*|*tdie*) ;; *) continue ;; esac
            raw=$(cat "$z/temp" 2>/dev/null); [[ "$raw" =~ ^-?[0-9]+$ ]] || continue
            if ((raw>1000 || raw< -1000)); then t=$(((raw+500)/1000)); else t=$raw; fi
            ((t>0 && t<150)) && vals+=("$t")
        done
    fi
    if ((${#vals[@]}>0)); then printf '%s\n' "${vals[@]}" | sort -nr | head -1; return; fi
    if command -v sensors >/dev/null 2>&1; then
        LC_ALL=C sensors 2>/dev/null | awk '
        /^[[:space:]]*(Package id|Physical id|Core [0-9]+|Tctl|Tdie|CPU):/ {
            if (match($0,/\+[0-9]+([.][0-9]+)?/)) {
                x=substr($0,RSTART+1,RLENGTH-1)+0; if(x>m && x<150)m=x
            }
        } END{if(m>0)printf "%d\n",m+0.5}'
    fi
}

# -------------------- ОТЧЁТ --------------------
HOST=$(hostname 2>/dev/null); [ -z "$HOST" ] && HOST="unknown-host"
SAFE_HOST=$(printf '%s' "$HOST" | tr -c '[:alnum:]_.-' '_')
STAMP=$(date '+%Y-%m-%d_%H-%M-%S')
EXT=txt; ((JSON_MODE==1)) && EXT=json
REPORT_DIR="${REPORT_DIR_DEFAULT:-${REPORT_DIR:-$(pwd -P 2>/dev/null)}}"; [ -z "$REPORT_DIR" ] && REPORT_DIR=/tmp
if [ ! -d "$REPORT_DIR" ] || [ ! -w "$REPORT_DIR" ]; then REPORT_DIR=/tmp; fi
if ((PRIVACY_MODE==1)); then DEFAULT_NAME="ARM_INFO_PRIVATE_${STAMP}.${EXT}"; else DEFAULT_NAME="ARM_INFO_${SAFE_HOST}_${STAMP}.${EXT}"; fi
if [ -n "$OUTPUT_PATH" ]; then
    if [ -d "$OUTPUT_PATH" ]; then REPORT_FILE="$OUTPUT_PATH/$DEFAULT_NAME"; else REPORT_FILE="$OUTPUT_PATH"; fi
else
    REPORT_FILE="$REPORT_DIR/$DEFAULT_NAME"
fi
if ((SAVE_REPORT==1)); then
    _outdir=$(dirname -- "$REPORT_FILE")
    if [ ! -d "$_outdir" ] || [ ! -w "$_outdir" ]; then REPORT_FILE="/tmp/$DEFAULT_NAME"; fi
fi
[ -t 1 ] && ((QUIET_MODE==0)) && command -v clear >/dev/null 2>&1 && clear
if ((SAVE_REPORT==1 && QUIET_MODE==0)); then
    exec > >(tee "$REPORT_FILE") 2>&1
elif ((SAVE_REPORT==1 && QUIET_MODE==1)); then
    exec > "$REPORT_FILE" 2>&1
elif ((SAVE_REPORT==0 && QUIET_MODE==1)); then
    exec >/dev/null 2>&1
fi

# -------------------- СИСТЕМА --------------------
if [ -r /etc/os-release ]; then . /etc/os-release; OS="${PRETTY_NAME:-$NAME}"; else OS="Не определено"; fi
KERNEL=$(uname -r 2>/dev/null); ARCH=$(uname -m 2>/dev/null)
UPTIME=$(format_uptime_ru)
NOW_EPOCH=$(date +%s)
INSTALL_EPOCH=$(stat -c %W / 2>/dev/null)
if ! [[ "$INSTALL_EPOCH" =~ ^[0-9]+$ ]] || ((INSTALL_EPOCH<=0 || INSTALL_EPOCH>NOW_EPOCH)); then INSTALL_EPOCH=""; fi
if [ -z "$INSTALL_EPOCH" ] && command -v rpm >/dev/null 2>&1; then
    INSTALL_EPOCH=$(rpm -qa --qf '%{INSTALLTIME}\n' 2>/dev/null | grep -E '^[0-9]+$' | sort -n | head -1)
fi
if [[ "$INSTALL_EPOCH" =~ ^[0-9]+$ ]] && ((INSTALL_EPOCH>0 && INSTALL_EPOCH<=NOW_EPOCH)); then
    INSTALL_DATE=$(date -d "@$INSTALL_EPOCH" '+%d.%m.%Y' 2>/dev/null)
    AGE_DAYS=$(((NOW_EPOCH-INSTALL_EPOCH)/86400)); ((AGE_DAYS<0))&&AGE_DAYS=0
    AGE_YEARS=$((AGE_DAYS/365))
else INSTALL_DATE="Не определено"; AGE_DAYS=-1; AGE_YEARS=-1; fi

SYSTEM_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null | head -1)
SYSTEM_PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null | head -1)
BIOS_VERSION=$(cat /sys/class/dmi/id/bios_version 2>/dev/null | head -1)
BIOS_DATE_RAW=$(cat /sys/class/dmi/id/bios_date 2>/dev/null | head -1)
[ -z "$SYSTEM_VENDOR" ]&&SYSTEM_VENDOR="-"; [ -z "$SYSTEM_PRODUCT" ]&&SYSTEM_PRODUCT="-"; [ -z "$BIOS_VERSION" ]&&BIOS_VERSION="-"
BIOS_DATE="Не определено"
BIOS_EPOCH=$(date -d "$BIOS_DATE_RAW" +%s 2>/dev/null)
if [[ "$BIOS_EPOCH" =~ ^[0-9]+$ ]] && ((BIOS_EPOCH>946684800 && BIOS_EPOCH<=NOW_EPOCH)); then BIOS_DATE=$(date -d "@$BIOS_EPOCH" '+%d.%m.%Y'); fi

# -------------------- ПРОЦЕССОР --------------------
CPU_MODEL=$(LC_ALL=C lscpu 2>/dev/null | awk -F: '/^Model name:/{sub(/^[ \t]+/,"",$2);print $2;exit}')
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(grep -m1 '^model name[[:space:]]*:' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^[[:space:]]*//')
[ -z "$CPU_MODEL" ] && CPU_MODEL="Не определено"
CORES=$(LC_ALL=C lscpu -p=CORE,SOCKET 2>/dev/null | awk -F, '!/^#/&&$1~/^[0-9]+$/&&$2~/^[0-9]+$/{s[$1":"$2]=1}END{for(k in s)n++;print n+0}')
if ! [[ "$CORES" =~ ^[0-9]+$ ]] || ((CORES==0)); then
    CORES=$(for c in /sys/devices/system/cpu/cpu[0-9]*; do [ -r "$c/topology/core_id" ]||continue; echo "$(cat "$c/topology/physical_package_id" 2>/dev/null):$(cat "$c/topology/core_id" 2>/dev/null)"; done | sort -u | grep -c .)
fi
THREADS=$(LC_ALL=C nproc --all 2>/dev/null); [[ "$THREADS" =~ ^[0-9]+$ ]] || THREADS=$(grep -c '^processor[[:space:]]*:' /proc/cpuinfo 2>/dev/null)
SOCKETS=$(LC_ALL=C lscpu -p=SOCKET 2>/dev/null | awk -F, '!/^#/&&$1~/^[0-9]+$/{s[$1]=1}END{for(k in s)n++;print n+0}')
[[ "$SOCKETS" =~ ^[0-9]+$ ]] && ((SOCKETS>0)) || SOCKETS="?"
[[ "$CORES" =~ ^[0-9]+$ ]] && ((CORES>0)) || CORES="?"; [[ "$THREADS" =~ ^[0-9]+$ ]]&&((THREADS>0)) || THREADS="?"
LOAD1=$(awk '{print $1}' /proc/loadavg 2>/dev/null); [ -z "$LOAD1" ]&&LOAD1=0

CPU_TEMP="-"; CPU_TEMP_MAX="-"; CPU_TEMP_SAMPLES=()
for _i in 1 2 3; do _t=$(read_cpu_temp_once); [[ "$_t" =~ ^[0-9]+$ ]]&&CPU_TEMP_SAMPLES+=("$_t"); [ "$_i" -lt 3 ]&&sleep 0.3; done
if ((${#CPU_TEMP_SAMPLES[@]}>0)); then
    CPU_TEMP_MAX=$(printf '%s\n' "${CPU_TEMP_SAMPLES[@]}" | sort -nr | head -1)
    _sorted=$(printf '%s\n' "${CPU_TEMP_SAMPLES[@]}" | sort -n); _n=${#CPU_TEMP_SAMPLES[@]}
    if ((_n==1)); then CPU_TEMP=${CPU_TEMP_SAMPLES[0]}; elif ((_n==2)); then CPU_TEMP=$(printf '%s\n' "$_sorted"|head -1); else CPU_TEMP=$(printf '%s\n' "$_sorted"|sed -n '2p'); fi
fi

# -------------------- ОЗУ --------------------
MEM_TOTAL_KB=$(awk '/MemTotal:/{print $2}' /proc/meminfo); MEM_AVAIL_KB=$(awk '/MemAvailable:/{print $2}' /proc/meminfo)
SWAP_TOTAL_KB=$(awk '/SwapTotal:/{print $2}' /proc/meminfo); SWAP_FREE_KB=$(awk '/SwapFree:/{print $2}' /proc/meminfo)
[[ "$MEM_TOTAL_KB" =~ ^[0-9]+$ ]]||MEM_TOTAL_KB=0; [[ "$MEM_AVAIL_KB" =~ ^[0-9]+$ ]]||MEM_AVAIL_KB=0
[[ "$SWAP_TOTAL_KB" =~ ^[0-9]+$ ]]||SWAP_TOTAL_KB=0; [[ "$SWAP_FREE_KB" =~ ^[0-9]+$ ]]||SWAP_FREE_KB=0
RAM_TOTAL=$(LC_ALL=C free -h 2>/dev/null | awk '/^Mem:/{print $2}'); RAM_USED=$(LC_ALL=C free -h 2>/dev/null | awk '/^Mem:/{print $3}'); RAM_AVAIL=$(LC_ALL=C free -h 2>/dev/null | awk '/^Mem:/{print $7}')
[ -z "$RAM_TOTAL" ]&&RAM_TOTAL="?"; [ -z "$RAM_USED" ]&&RAM_USED="?"; [ -z "$RAM_AVAIL" ]&&RAM_AVAIL="?"
if ((MEM_TOTAL_KB>0)); then MEM_AVAIL_PCT=$((MEM_AVAIL_KB*100/MEM_TOTAL_KB)); else MEM_AVAIL_PCT=0; fi
if ((SWAP_TOTAL_KB>0)); then SWAP_USED_PCT=$(((SWAP_TOTAL_KB-SWAP_FREE_KB)*100/SWAP_TOTAL_KB)); else SWAP_USED_PCT=0; fi
RAM_TYPE="Не определено"; RAM_SPEED="-"; RAM_MODULES="?"
if command -v dmidecode >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
    DMI_MEM=$(LC_ALL=C dmidecode -t memory 2>/dev/null)
    RAM_MODULES=$(printf '%s\n' "$DMI_MEM" | awk -F: '/^[[:space:]]*Size:/{x=$2;gsub(/^[ \t]+|[ \t]+$/,"",x);if(x!=""&&x!~/No Module Installed/i&&x!~/^0 /&&x!~/Unknown/i)n++}END{print n+0}')
    RAM_TYPE=$(printf '%s\n' "$DMI_MEM" | awk -F: '/^[[:space:]]*Type:/{x=$2;gsub(/^[ \t]+|[ \t]+$/,"",x);if(x~/^DDR[0-9]/)print x}' | sort -u | paste -sd '/' -); [ -z "$RAM_TYPE" ]&&RAM_TYPE="Не определено"
    RAM_SPEED=$(printf '%s\n' "$DMI_MEM" | awk -F: '/^[[:space:]]*Configured Memory Speed:/{x=$2;gsub(/^[ \t]+|[ \t]+$/,"",x);if(x!=""&&x!~/Unknown/i&&x!~/^0 /){print x;exit}}')
    [ -z "$RAM_SPEED" ] && RAM_SPEED=$(printf '%s\n' "$DMI_MEM" | awk -F: '/^[[:space:]]*Speed:/{x=$2;gsub(/^[ \t]+|[ \t]+$/,"",x);if(x!=""&&x!~/Unknown/i&&x!~/^0 /){print x;exit}}')
    [ -z "$RAM_SPEED" ]&&RAM_SPEED="-"
fi

# -------------------- СЕТЬ --------------------
GW=$(ip -4 route show default 2>/dev/null | awk 'NR==1{print $3}'); [ -z "$GW" ]&&GW="-"
DNS=$(awk '/^[[:space:]]*nameserver[[:space:]]+/{print $2}' /etc/resolv.conf 2>/dev/null | sort -u | paste -sd ',' -)
if command -v resolvectl >/dev/null 2>&1; then
    DNS_REAL=$(resolvectl dns 2>/dev/null | awk -F: 'NF>1{print $2}' | xargs -n1 2>/dev/null | grep -E '^[0-9a-fA-F:.]+$' | sort -u | paste -sd ',' -); [ -n "$DNS_REAL" ]&&DNS="$DNS_REAL"
elif command -v nmcli >/dev/null 2>&1; then
    DNS_REAL=$(nmcli -t -f IP4.DNS device show 2>/dev/null | cut -d: -f2- | grep -v '^$' | sort -u | paste -sd ',' -); [ -n "$DNS_REAL" ]&&DNS="$DNS_REAL"
fi
[ -z "$DNS" ]&&DNS="-"
ACTIVE_NET=0
RX_ERRORS_TOTAL=0; TX_ERRORS_TOTAL=0
# rx_dropped сохраняем как диагностический счётчик, но сам по себе он не
# доказывает потерю полезного трафика: ядро может учитывать там L2/filter drops.
RX_DROPS_TOTAL=0; RX_MISSED_TOTAL=0; TX_DROPS_TOTAL=0
RX_PACKETS_TOTAL=0; TX_PACKETS_TOTAL=0
RXTX_ERRORS=0; SCORED_LOSSES_TOTAL=0; RXTX_PACKETS=0
NET_ROWS=(); NET_BAD_IFACES=()
for P in /sys/class/net/*; do
    IFACE=$(basename "$P"); [ "$IFACE" = lo ]&&continue
    STATE=$(cat "$P/operstate" 2>/dev/null); [ "$STATE" = up ]||continue
    IPADDR=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1); [ -z "$IPADDR" ]&&continue
    MAC=$(cat "$P/address" 2>/dev/null); [ -z "$MAC" ]&&MAC="-"
    SPEED=$(cat "$P/speed" 2>/dev/null); DUPLEX=$(cat "$P/duplex" 2>/dev/null)
    if [[ "$SPEED" =~ ^[0-9]+$ ]]&&((SPEED>0)); then LINK="${SPEED}M"; [ -n "$DUPLEX" ]&&LINK="$LINK/$DUPLEX"; else LINK="-"; fi
    NET_ROWS+=("$IFACE|$IPADDR|$MAC|$LINK"); ACTIVE_NET=$((ACTIVE_NET+1))
    # Для статистики ошибок используем физические устройства; VPN/tun не должны искажать балл.
    [ -e "$P/device" ] || continue
    RX=$(cat "$P/statistics/rx_errors" 2>/dev/null); TX=$(cat "$P/statistics/tx_errors" 2>/dev/null); RXD=$(cat "$P/statistics/rx_dropped" 2>/dev/null); RXM=$(cat "$P/statistics/rx_missed_errors" 2>/dev/null); TXD=$(cat "$P/statistics/tx_dropped" 2>/dev/null)
    RXP=$(cat "$P/statistics/rx_packets" 2>/dev/null); TXP=$(cat "$P/statistics/tx_packets" 2>/dev/null)
    for V in RX TX RXD RXM TXD RXP TXP; do eval 'X=${'"$V"'}'; [[ "$X" =~ ^[0-9]+$ ]]||eval "$V=0"; done
    RX_ERRORS_TOTAL=$((RX_ERRORS_TOTAL+RX)); TX_ERRORS_TOTAL=$((TX_ERRORS_TOTAL+TX))
    RX_DROPS_TOTAL=$((RX_DROPS_TOTAL+RXD)); RX_MISSED_TOTAL=$((RX_MISSED_TOTAL+RXM)); TX_DROPS_TOTAL=$((TX_DROPS_TOTAL+TXD))
    RX_PACKETS_TOTAL=$((RX_PACKETS_TOTAL+RXP)); TX_PACKETS_TOTAL=$((TX_PACKETS_TOTAL+TXP))
    RXTX_ERRORS=$((RX_ERRORS_TOTAL+TX_ERRORS_TOTAL)); SCORED_LOSSES_TOTAL=$((RX_MISSED_TOTAL+TX_DROPS_TOTAL)); RXTX_PACKETS=$((RX_PACKETS_TOTAL+TX_PACKETS_TOTAL))
    # В score входят errors + реальные пропуски host/NIC + TX drops. Общий
    # rx_dropped остаётся информационным и не создаёт WARN самостоятельно.
    IF_BAD=$((RX+TX+RXM+TXD)); IF_PKT=$((RXP+TXP)); IF_PPM=0; ((IF_PKT>0))&&IF_PPM=$((IF_BAD*1000000/IF_PKT)); ((IF_PPM>=1000))&&NET_BAD_IFACES+=("$IFACE:${IF_PPM}ppm")
done
NET_BAD_PPM=0
NET_ERROR_PPM=0
NET_DROP_PPM=0
NET_RX_DROP_PPM_RAW=0
NET_SCORED_LOSS_PPM=0
NET_BAD_PERCENT="0.0000"
if ((RXTX_PACKETS>0)); then
    NET_BAD_PPM=$(((RXTX_ERRORS+SCORED_LOSSES_TOTAL)*1000000/RXTX_PACKETS))
    NET_ERROR_PPM=$((RXTX_ERRORS*1000000/RXTX_PACKETS))
    NET_SCORED_LOSS_PPM=$((SCORED_LOSSES_TOTAL*1000000/RXTX_PACKETS))
    # drop_ppm сохраняется для совместимости schema v1, но начиная с 1.2.4
    # означает только учитываемые потери (rx_missed + tx_dropped).
    NET_DROP_PPM=$NET_SCORED_LOSS_PPM
    NET_BAD_PERCENT=$(awk -v bad="$((RXTX_ERRORS+SCORED_LOSSES_TOTAL))" -v pkt="$RXTX_PACKETS" 'BEGIN{if(pkt>0)printf "%.4f",bad*100/pkt;else print "0.0000"}')
fi
if ((RX_PACKETS_TOTAL>0)); then
    NET_RX_DROP_PPM_RAW=$((RX_DROPS_TOTAL*1000000/RX_PACKETS_TOTAL))
fi
if ((ACTIVE_NET==0)); then
    NET_STATUS="Нет подключения"
elif ((NET_ERROR_PPM>=NET_ERROR_CRIT_PPM || NET_DROP_PPM>=NET_DROP_CRIT_PPM)); then
    NET_STATUS="Проблема"
elif ((NET_ERROR_PPM>=NET_ERROR_WARN_PPM || NET_DROP_PPM>=NET_DROP_WARN_PPM)); then
    NET_STATUS="Требует внимания"
else
    NET_STATUS="Норма"
fi

# -------------------- ФАЙЛОВЫЕ СИСТЕМЫ --------------------
ROOT_DEV=$(findmnt -no SOURCE / 2>/dev/null); [ -z "$ROOT_DEV" ]&&ROOT_DEV="-"

# Физический накопитель, на котором находится корневая ФС, является приоритетным.
# Для LVM/dm-crypt/device-mapper идём по цепочке parents до TYPE=disk.
ROOT_BLOCK="$ROOT_DEV"
if [[ "$ROOT_BLOCK" == /dev/* ]]; then ROOT_BLOCK=$(readlink -f "$ROOT_BLOCK" 2>/dev/null || printf '%s' "$ROOT_BLOCK"); fi
SYSTEM_DISKS=""
if command -v lsblk >/dev/null 2>&1 && [[ "$ROOT_BLOCK" == /dev/* ]]; then
    SYSTEM_DISKS=$(lsblk -srno NAME,TYPE "$ROOT_BLOCK" 2>/dev/null | awk '$2=="disk"{print $1}' | sort -u)
fi
if [[ -z "$SYSTEM_DISKS" ]] && command -v lsblk >/dev/null 2>&1; then
    ROOT_MAJMIN=$(findmnt -no MAJ:MIN / 2>/dev/null || true)
    if [[ -n "$ROOT_MAJMIN" ]]; then
        ROOT_NODE=$(lsblk -rno NAME,TYPE,MAJ:MIN 2>/dev/null | awk -v mm="$ROOT_MAJMIN" '$3==mm{print "/dev/"$1; exit}')
        [[ -n "$ROOT_NODE" ]] && SYSTEM_DISKS=$(lsblk -srno NAME,TYPE "$ROOT_NODE" 2>/dev/null | awk '$2=="disk"{print $1}' | sort -u)
    fi
fi
SYSTEM_DISKS=$(printf '%s\n' "$SYSTEM_DISKS" | sed -E 's/^[^[:alnum:]_./-]+//' | sed '/^$/d' | sort -u)
SYSTEM_DISK_TEXT=$(printf '%s\n' "$SYSTEM_DISKS" | sed '/^$/d' | paste -sd ',' -)
[ -z "$SYSTEM_DISK_TEXT" ] && SYSTEM_DISK_TEXT="Не определён"

is_system_disk() {
    local n=$1
    printf '%s
' "$SYSTEM_DISKS" | grep -Fxq -- "$n"
}

disk_is_removable() {
    local n=$1 rmflag=0 tran=""
    is_system_disk "$n" && return 1
    [[ -r "/sys/class/block/$n/removable" ]] && rmflag=$(cat "/sys/class/block/$n/removable" 2>/dev/null || echo 0)
    if command -v lsblk >/dev/null 2>&1; then tran=$(lsblk -dn -o TRAN "/dev/$n" 2>/dev/null | tr -d '[:space:]'); fi
    [[ "$rmflag" == 1 || "$tran" == usb ]]
}

mount_is_removable() {
    local mnt=$1 src real d
    src=$(findmnt -no SOURCE --target "$mnt" 2>/dev/null || true)
    real="$src"; [[ "$real" == /dev/* ]] && real=$(readlink -f "$real" 2>/dev/null || printf '%s' "$real")
    if command -v lsblk >/dev/null 2>&1 && [[ "$real" == /dev/* ]]; then
        while read -r d; do
            [[ -n "$d" ]] || continue
            disk_is_removable "$d" && return 0
        done < <(lsblk -sno NAME,TYPE "$real" 2>/dev/null | awk '$2=="disk"{print $1}' | sort -u)
    fi
    # Fallback для типовых пользовательских автомонтирований, если topology недоступна.
    [[ "$mnt" == /run/media/* || "$mnt" == /media/* ]]
}

ROOT_USE=$(df -P / 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}'); ROOT_INODE_USE=$(df -Pi / 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}')
ROOT_SIZE=$(df -hP / 2>/dev/null | awk 'NR==2{print $2}'); ROOT_USED=$(df -hP / 2>/dev/null | awk 'NR==2{print $3}'); ROOT_FREE=$(df -hP / 2>/dev/null | awk 'NR==2{print $4}')
[[ "$ROOT_USE" =~ ^[0-9]+$ ]]||ROOT_USE=0; [[ "$ROOT_INODE_USE" =~ ^[0-9]+$ ]]||ROOT_INODE_USE=0
ROOT_RO=0; findmnt -no OPTIONS / 2>/dev/null | grep -Eq '(^|,)ro(,|$)'&&ROOT_RO=1
LOCAL_FS_COUNT=0; REMOVABLE_FS_COUNT=0; LOCAL_RO_COUNT=0; FS_WORST_USE=$ROOT_USE; FS_WORST_USE_MOUNT=/; FS_WORST_INODE=$ROOT_INODE_USE; FS_WORST_INODE_MOUNT=/; FS_RO_MOUNTS=(); LOCAL_FS_ROWS=()
while IFS= read -r MNT; do
    [ -n "$MNT" ]||continue
    USE=$(df -P "$MNT" 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}'); INO=$(df -Pi "$MNT" 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}')
    [[ "$USE" =~ ^[0-9]+$ ]]||USE=0; [[ "$INO" =~ ^[0-9]+$ ]]||INO=0
    RO=0; findmnt -no OPTIONS --target "$MNT" 2>/dev/null | grep -Eq '(^|,)ro(,|$)'&&RO=1
    if [ "$MNT" != / ] && mount_is_removable "$MNT"; then
        REMOVABLE_FS_COUNT=$((REMOVABLE_FS_COUNT+1))
        continue
    fi
    LOCAL_FS_COUNT=$((LOCAL_FS_COUNT+1)); ((USE>FS_WORST_USE))&&{ FS_WORST_USE=$USE; FS_WORST_USE_MOUNT="$MNT"; }; ((INO>FS_WORST_INODE))&&{ FS_WORST_INODE=$INO; FS_WORST_INODE_MOUNT="$MNT"; }
    ((RO==1))&&{ LOCAL_RO_COUNT=$((LOCAL_RO_COUNT+1)); FS_RO_MOUNTS+=("$MNT"); }
    if [ "$MNT" = / ] || ((USE>=70 || INO>=70 || RO==1)); then LOCAL_FS_ROWS+=("$MNT|${USE}%|${INO}%|$([ "$RO" -eq 1 ]&&echo RO||echo RW)"); fi
done < <(findmnt -rn -t ext2,ext3,ext4,xfs,btrfs,vfat,exfat,f2fs,jfs,reiserfs -o TARGET 2>/dev/null | sort -u)
((LOCAL_FS_COUNT==0))&&LOCAL_FS_COUNT=1

# -------------------- ЖУРНАЛ / СЛУЖБЫ --------------------
FAILED_NAMES=""; FAILED_COUNT=0; SYSTEMD_AVAILABLE=0
if command -v systemctl >/dev/null 2>&1; then
    SYSTEMD_AVAILABLE=1
    FAILED_NAMES=$(LC_ALL=C systemctl --failed --no-legend --plain --no-pager 2>/dev/null | awk '$1~/\.(service|socket|mount|target|timer|path|scope|slice|device|automount)$/{print $1}' | paste -sd ',' -)
    [ -n "$FAILED_NAMES" ]&&FAILED_COUNT=$(printf '%s' "$FAILED_NAMES" | awk -F, '{print NF}')
fi
JOURNAL_AVAILABLE=0; HW_ERR_COUNT=0; OOM_DETECTED=0; JOURNAL_ERR_COUNT=0
if command -v journalctl >/dev/null 2>&1 && journalctl -b -n 1 -q --no-pager >/dev/null 2>&1; then
    JOURNAL_AVAILABLE=1; KERNEL_LOG=$(journalctl -k -b -o cat -q --no-pager 2>/dev/null)
    HW_ERR_COUNT=$(printf '%s\n' "$KERNEL_LOG" | grep -Ei 'I/O error|Buffer I/O|blk_update_request|EXT[234]-fs error|XFS.*error|BTRFS.*error|nvme.*(critical|error)|ata[0-9.]*.*(error|failed|exception)|hardware error|Machine Check|MCE|EDAC.*(UE|uncorrect)' | sed '/^[[:space:]]*$/d' | sort -u | wc -l)
    if printf '%s\n' "$KERNEL_LOG" | grep -Eqi 'invoked oom-killer|oom-kill:|Out of memory: Killed process|Memory cgroup out of memory'; then OOM_DETECTED=1; fi
    JOURNAL_ERR_COUNT=$(journalctl -b -p err..alert -o cat -q --no-pager 2>/dev/null | sed '/^[[:space:]]*$/d' | sort -u | wc -l)
fi
[[ "$HW_ERR_COUNT" =~ ^[0-9]+$ ]]||HW_ERR_COUNT=0; [[ "$JOURNAL_ERR_COUNT" =~ ^[0-9]+$ ]]||JOURNAL_ERR_COUNT=0

# -------------------- ДОПОЛНИТЕЛЬНЫЕ ПРОВЕРКИ --------------------
# Синхронизация времени особенно важна для Kerberos/AD.
TIME_SYNC="Н/Д"
if command -v timedatectl >/dev/null 2>&1; then
    _nts=$(timedatectl show -p NTPSynchronized --value 2>/dev/null | tr '[:upper:]' '[:lower:]')
    [ "$_nts" = yes ] && TIME_SYNC="Да"
    [ "$_nts" = no ] && TIME_SYNC="Нет"
fi
if [ "$TIME_SYNC" = "Н/Д" ] && command -v chronyc >/dev/null 2>&1; then
    chronyc tracking 2>/dev/null | grep -qi 'Leap status.*Normal' && TIME_SYNC="Да"
fi

# Признаки аварийного завершения предыдущей загрузки: только индикатор, не абсолютный диагноз.
UNCLEAN_BOOT_SIGNS=0
if ((JOURNAL_AVAILABLE==1)); then
    _prev_kernel=$(journalctl -k -b -1 -o cat -q --no-pager 2>/dev/null || true)
    if [ -n "$_prev_kernel" ]; then
        UNCLEAN_BOOT_SIGNS=$(printf '%s\n' "$_prev_kernel" | grep -Ei 'kernel panic|watchdog.*(lockup|reset)|unclean shutdown|power failure|I/O error.*shutdown' | sort -u | wc -l)
    fi
fi
[[ "$UNCLEAN_BOOT_SIGNS" =~ ^[0-9]+$ ]] || UNCLEAN_BOOT_SIGNS=0

# Linux software RAID (md).
RAID_STATUS="Не обнаружен"; RAID_DEGRADED=0
if [ -r /proc/mdstat ] && grep -Eq '^md[0-9]+' /proc/mdstat; then
    if grep -Eq '\[[U_]*_[U_]*\]' /proc/mdstat; then RAID_STATUS="DEGRADED"; RAID_DEGRADED=1; else RAID_STATUS="OK"; fi
fi

# ECC/EDAC: исправленные и неисправимые ошибки, если драйвер публикует счётчики.
ECC_STATUS="Н/Д"; ECC_CE=0; ECC_UE=0
if compgen -G '/sys/devices/system/edac/mc/mc*/ce_count' >/dev/null; then
    ECC_STATUS="OK"
    for _f in /sys/devices/system/edac/mc/mc*/ce_count; do _v=$(cat "$_f" 2>/dev/null); [[ "$_v" =~ ^[0-9]+$ ]] && ECC_CE=$((ECC_CE+_v)); done
    for _f in /sys/devices/system/edac/mc/mc*/ue_count; do [ -r "$_f" ] || continue; _v=$(cat "$_f" 2>/dev/null); [[ "$_v" =~ ^[0-9]+$ ]] && ECC_UE=$((ECC_UE+_v)); done
    ((ECC_UE>0)) && ECC_STATUS="ОШИБКИ"
    ((ECC_UE==0 && ECC_CE>0)) && ECC_STATUS="Исправленные ошибки"
fi

# Батарея (актуально для ноутбуков).
BATTERY_STATUS="Не обнаружена"; BATTERY_CAPACITY="-"; BATTERY_HEALTH="-"
for _bat in /sys/class/power_supply/BAT*; do
    [ -d "$_bat" ] || continue
    BATTERY_STATUS=$(cat "$_bat/status" 2>/dev/null); [ -z "$BATTERY_STATUS" ] && BATTERY_STATUS="Н/Д"
    _cap=$(cat "$_bat/capacity" 2>/dev/null); [[ "$_cap" =~ ^[0-9]+$ ]] && BATTERY_CAPACITY="${_cap}%"
    _full=$(cat "$_bat/energy_full" 2>/dev/null); _design=$(cat "$_bat/energy_full_design" 2>/dev/null)
    [ -z "$_full" ] && _full=$(cat "$_bat/charge_full" 2>/dev/null)
    [ -z "$_design" ] && _design=$(cat "$_bat/charge_full_design" 2>/dev/null)
    if [[ "$_full" =~ ^[0-9]+$ && "$_design" =~ ^[0-9]+$ ]] && ((_design>0)); then BATTERY_HEALTH="$((_full*100/_design))%"; fi
    break
done

# Опциональные сервисы: не влияют на базовую аппаратную оценку, но дают контекст АРМ.
SSSD_STATUS="Не установлен"; SSSD_DOMAINS="-"
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files sssd.service --no-legend 2>/dev/null | grep -q '^sssd.service'; then
    SSSD_STATUS=$(systemctl is-active sssd 2>/dev/null || true); [ -z "$SSSD_STATUS" ] && SSSD_STATUS="неактивен"
    if command -v sssctl >/dev/null 2>&1; then SSSD_DOMAINS=$(sssctl domain-list 2>/dev/null | paste -sd ',' -); [ -z "$SSSD_DOMAINS" ] && SSSD_DOMAINS="-"; fi
fi
KRB_STATUS="Не установлен"
if command -v klist >/dev/null 2>&1; then if klist -s 2>/dev/null; then KRB_STATUS="Есть билет (текущий контекст)"; else KRB_STATUS="Билета нет (текущий контекст)"; fi; fi
CUPS_STATUS="Не установлен"; CUPS_QUEUES=0
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files cups.service --no-legend 2>/dev/null | grep -q '^cups.service'; then
    CUPS_STATUS=$(systemctl is-active cups 2>/dev/null || true); [ -z "$CUPS_STATUS" ] && CUPS_STATUS="неактивен"
    if command -v lpstat >/dev/null 2>&1; then CUPS_QUEUES=$(lpstat -p 2>/dev/null | grep -c '^printer '); fi
fi

# Совместимость дистрибутива.
DISTRO_ID=${ID:-unknown}; DISTRO_LIKE=${ID_LIKE:-}
case "$DISTRO_ID" in
    redos) SUPPORT_TIER="Основная поддержка" ;;
    rhel|centos|rocky|almalinux|fedora) SUPPORT_TIER="Совместимая RHEL/Fedora-система" ;;
    debian|ubuntu) SUPPORT_TIER="Экспериментальная совместимость" ;;
    *) case " $DISTRO_LIKE " in *' rhel '*|*' fedora '*) SUPPORT_TIER="Совместимая RHEL/Fedora-система" ;; *) SUPPORT_TIER="Не проверено" ;; esac ;;
esac

# -------------------- ДИСКИ / SMART --------------------
DISK_ROWS=(); DISK_SYSTEM_ROWS=(); DISK_FIXED_ROWS=(); DISK_REMOVABLE_ROWS=(); DISK_OPTICAL_ROWS=(); DISK_SELFTEST_ROWS=(); DISK_WORST_SCORE=100; SYSTEM_DISK_SCORE=100; SECONDARY_WORST_KNOWN_SCORE=100; FIXED_DISKS=0; SYSTEM_DISK_COUNT=0; SECONDARY_FIXED_DISKS=0; SECONDARY_KNOWN_COUNT=0; REMOVABLE_DISKS=0; MAX_DISK_HOURS=0; SYSTEM_MAX_DISK_HOURS=0; SMART_UNKNOWN_COUNT=0; SYSTEM_SMART_UNKNOWN_COUNT=0; SECONDARY_CRITICAL=0
while read -r NAME TYPE SIZE ROTA MODEL; do
    case "$TYPE" in disk|rom) ;; *) continue ;; esac
    DEV="/dev/$NAME"; MODEL=$(echo "$MODEL" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'); [ -z "$MODEL" ]&&MODEL="-"; [ "${#MODEL}" -gt 28 ]&&MODEL="${MODEL:0:27}…"
    if [[ "$TYPE" = rom || "$NAME" = sr* ]]; then DISK_OPTICAL_ROWS+=("$NAME|Оптический (вне индекса)|CD/DVD||$MODEL|-|-|-|-"); continue; fi
    TRAN=$(lsblk -dn -o TRAN "$DEV" 2>/dev/null | tr -d '[:space:]')
    if is_system_disk "$NAME"; then
        DISK_ROLE="Системный"; SYSTEM_DISK_COUNT=$((SYSTEM_DISK_COUNT+1))
    elif disk_is_removable "$NAME"; then
        DISK_ROLE="Съёмный (вне индекса)"; REMOVABLE_DISKS=$((REMOVABLE_DISKS+1))
        if [[ "$TRAN" == usb ]]; then DISK_TYPE="USB-накопитель"; else DISK_TYPE="Съёмный накопитель"; fi
        DISK_REMOVABLE_ROWS+=("$NAME|$DISK_ROLE|$DISK_TYPE|$SIZE|$MODEL|-|не учитывается|-|-")
        continue
    else
        DISK_ROLE="Дополнительный"; SECONDARY_FIXED_DISKS=$((SECONDARY_FIXED_DISKS+1))
    fi
    FIXED_DISKS=$((FIXED_DISKS+1)); DISK_SCORE=100; RESOURCE="-"; SMART="Н/Д"; TEMP="-"; HOURS="-"; REALLOC=0; PENDING=0; UNCORR=0; MEDIAERR=0; CRITWARN=0
    if [[ "$NAME" = nvme* ]]; then DISK_TYPE="NVMe SSD"; elif [ "$ROTA" = 0 ]; then DISK_TYPE=SSD; else DISK_TYPE=HDD; fi
    if command -v smartctl >/dev/null 2>&1; then
        SMART_ALL=$(run_smart -a "$DEV" 2>/dev/null); SMART_H=$(run_smart -H "$DEV" 2>/dev/null)
        SELFTEST="Н/Д"
        _st=$(run_smart -l selftest "$DEV" 2>/dev/null | awk '/^# *1[[:space:]]/{for(i=5;i<=NF;i++){printf "%s%s",$i,(i<NF?" ":"")} exit}')
        [ -n "$_st" ] && SELFTEST="$_st"
        DISK_SELFTEST_ROWS+=("$NAME|$SELFTEST")
        if echo "$SMART_H"|grep -Eqi 'PASSED|SMART.*OK'; then SMART=OK; elif echo "$SMART_H"|grep -Eqi 'FAILED|SMART.*BAD'; then SMART=FAIL; DISK_SCORE=0; else SMART="Н/Д"; SMART_UNKNOWN_COUNT=$((SMART_UNKNOWN_COUNT+1)); [[ "$DISK_ROLE" == "Системный" ]] && SYSTEM_SMART_UNKNOWN_COUNT=$((SYSTEM_SMART_UNKNOWN_COUNT+1)); fi
        if [[ "$NAME" = nvme* ]]; then
            USED=$(printf '%s\n' "$SMART_ALL" | awk -F: '/Percentage Used/{x=$2;gsub(/[% \t]/,"",x);print x;exit}'); if [[ "$USED" =~ ^[0-9]+$ ]]; then REMAIN=$((100-USED)); ((REMAIN<0))&&REMAIN=0; ((REMAIN>100))&&REMAIN=100; RESOURCE="${REMAIN}%"; ((REMAIN<DISK_SCORE))&&DISK_SCORE=$REMAIN; fi
            TEMP=$(printf '%s\n' "$SMART_ALL" | awk -F: '/^Temperature:/{x=$2;gsub(/[^0-9]/,"",x);if(x!=""){print x;exit}}'); HOURS=$(printf '%s\n' "$SMART_ALL" | awk -F: '/Power On Hours/{x=$2;gsub(/[^0-9]/,"",x);if(x!=""){print x;exit}}')
            CRITRAW=$(printf '%s\n' "$SMART_ALL" | awk -F: '/Critical Warning/{x=$2;gsub(/^[ \t]+|[ \t]+$/,"",x);print x;exit}'); if [[ "$CRITRAW" =~ ^0[xX][0-9a-fA-F]+$ ]]; then CRITWARN=$((CRITRAW)); else CRITWARN=$(printf '%s' "$CRITRAW"|tr -cd '0-9'); [[ "$CRITWARN" =~ ^[0-9]+$ ]]||CRITWARN=0; fi
            MEDIAERR=$(printf '%s\n' "$SMART_ALL" | awk -F: '/Media and Data Integrity Errors/{x=$2;gsub(/[^0-9]/,"",x);print x+0;exit}'); [[ "$MEDIAERR" =~ ^[0-9]+$ ]]||MEDIAERR=0
            SPARE=$(printf '%s\n' "$SMART_ALL" | awk -F: '/Available Spare:/{x=$2;gsub(/[^0-9]/,"",x);if(x!=""){print x;exit}}'); SPARE_THR=$(printf '%s\n' "$SMART_ALL" | awk -F: '/Available Spare Threshold:/{x=$2;gsub(/[^0-9]/,"",x);if(x!=""){print x;exit}}'); [[ "$SPARE" =~ ^[0-9]+$ ]]||SPARE=-1; [[ "$SPARE_THR" =~ ^[0-9]+$ ]]||SPARE_THR=-1
            ((CRITWARN>0))&&DISK_SCORE=$(min_score "$DISK_SCORE" 20); ((MEDIAERR>0))&&DISK_SCORE=$(min_score "$DISK_SCORE" 50); ((SPARE>=0 && SPARE_THR>=0 && SPARE<=SPARE_THR))&&DISK_SCORE=$(min_score "$DISK_SCORE" 40)
        else
            HOURS=$(printf '%s\n' "$SMART_ALL" | awk '/Power_On_Hours/{for(i=10;i<=NF;i++)if($i~/^[0-9]+$/){print $i+0;exit}}'); [[ "$HOURS" =~ ^[0-9]+$ ]]||HOURS="-"
            TEMP=$(printf '%s\n' "$SMART_ALL" | awk '/Temperature_Celsius|Airflow_Temperature_Cel/{for(i=10;i<=NF;i++)if($i~/^[0-9]+$/){print $i+0;exit}}'); [ -z "$TEMP" ]&&TEMP="-"
            REALLOC=$(printf '%s\n' "$SMART_ALL" | awk '/Reallocated_Sector_Ct/{for(i=10;i<=NF;i++)if($i~/^[0-9]+$/){print $i+0;exit}}'); PENDING=$(printf '%s\n' "$SMART_ALL" | awk '/Current_Pending_Sector/{for(i=10;i<=NF;i++)if($i~/^[0-9]+$/){print $i+0;exit}}'); UNCORR=$(printf '%s\n' "$SMART_ALL" | awk '/Offline_Uncorrectable/{for(i=10;i<=NF;i++)if($i~/^[0-9]+$/){print $i+0;exit}}'); [[ "$REALLOC" =~ ^[0-9]+$ ]]||REALLOC=0; [[ "$PENDING" =~ ^[0-9]+$ ]]||PENDING=0; [[ "$UNCORR" =~ ^[0-9]+$ ]]||UNCORR=0
            if [ "$DISK_TYPE" = SSD ]; then LIFE=$(printf '%s\n' "$SMART_ALL" | awk '$2~/Percent_Lifetime_Remain|SSD_Life_Left|Media_Wearout_Indicator|Remaining_Lifetime/{if($4~/^[0-9]+$/){print $4+0;exit}}'); if [[ "$LIFE" =~ ^[0-9]+$ ]]&&((LIFE<=100)); then RESOURCE="${LIFE}%"; ((LIFE<DISK_SCORE))&&DISK_SCORE=$LIFE; fi; fi
            if [ "$DISK_TYPE" = HDD ]&&[[ "$HOURS" =~ ^[0-9]+$ ]]; then if ((HOURS>=60000)); then DISK_SCORE=$(min_score "$DISK_SCORE" 55); elif ((HOURS>=40000)); then DISK_SCORE=$(min_score "$DISK_SCORE" 70); elif ((HOURS>=20000)); then DISK_SCORE=$(min_score "$DISK_SCORE" 88); fi; fi
            ((REALLOC>0))&&DISK_SCORE=$(min_score "$DISK_SCORE" 70); ((REALLOC>10))&&DISK_SCORE=$(min_score "$DISK_SCORE" 50); ((PENDING>0 || UNCORR>0))&&DISK_SCORE=$(min_score "$DISK_SCORE" 30)
        fi
        if [[ "$TEMP" =~ ^[0-9]+$ ]]; then
            if [ "$DISK_TYPE" = HDD ]; then ((TEMP>=HDD_TEMP_WARN))&&DISK_SCORE=$(min_score "$DISK_SCORE" 85); ((TEMP>=HDD_TEMP_HIGH))&&DISK_SCORE=$(min_score "$DISK_SCORE" 55); ((TEMP>=HDD_TEMP_CRIT))&&DISK_SCORE=$(min_score "$DISK_SCORE" 30)
            elif [ "$DISK_TYPE" = "NVMe SSD" ]; then ((TEMP>=NVME_TEMP_WARN))&&DISK_SCORE=$(min_score "$DISK_SCORE" 85); ((TEMP>=NVME_TEMP_HIGH))&&DISK_SCORE=$(min_score "$DISK_SCORE" 60); ((TEMP>=NVME_TEMP_CRIT))&&DISK_SCORE=$(min_score "$DISK_SCORE" 30)
            else ((TEMP>=SSD_TEMP_WARN))&&DISK_SCORE=$(min_score "$DISK_SCORE" 85); ((TEMP>=SSD_TEMP_HIGH))&&DISK_SCORE=$(min_score "$DISK_SCORE" 60); ((TEMP>=SSD_TEMP_CRIT))&&DISK_SCORE=$(min_score "$DISK_SCORE" 30); fi
        else TEMP="-"; fi
    fi
    DISK_SCORE=$(clamp_score "$DISK_SCORE")
    ((DISK_SCORE<DISK_WORST_SCORE))&&DISK_WORST_SCORE=$DISK_SCORE
    [[ "$HOURS" =~ ^[0-9]+$ ]]&&((HOURS>MAX_DISK_HOURS))&&MAX_DISK_HOURS=$HOURS
    if [[ "$DISK_ROLE" == "Системный" ]]; then
        ((DISK_SCORE<SYSTEM_DISK_SCORE))&&SYSTEM_DISK_SCORE=$DISK_SCORE
        [[ "$HOURS" =~ ^[0-9]+$ ]]&&((HOURS>SYSTEM_MAX_DISK_HOURS))&&SYSTEM_MAX_DISK_HOURS=$HOURS
        DISK_SYSTEM_ROWS+=("$NAME|$DISK_ROLE|$DISK_TYPE|$SIZE|$MODEL|$RESOURCE|$SMART|$TEMP|$HOURS")
    else
        if [[ "$SMART" != "Н/Д" ]]; then
            SECONDARY_KNOWN_COUNT=$((SECONDARY_KNOWN_COUNT+1))
            ((DISK_SCORE<SECONDARY_WORST_KNOWN_SCORE))&&SECONDARY_WORST_KNOWN_SCORE=$DISK_SCORE
        fi
        ((DISK_SCORE<30))&&SECONDARY_CRITICAL=1
        DISK_FIXED_ROWS+=("$NAME|$DISK_ROLE|$DISK_TYPE|$SIZE|$MODEL|$RESOURCE|$SMART|$TEMP|$HOURS")
    fi

    [ "$SMART" = FAIL ]&&add_rec "КРИТИЧНО" "Накопитель $NAME: SMART сообщает отказ" "Высокий риск внезапного отказа и потери данных." "Немедленно сохранить важные данные и заменить накопитель." "smartctl -a $DEV"
    ((REALLOC>0))&&add_rec "ВНИМАНИЕ" "Накопитель $NAME: переназначенные сектора — $REALLOC" "Носитель уже имеет дефектные области; рост счётчика означает деградацию." "Проверить резервное копирование и наблюдать SMART. При росте — заменить диск." "smartctl -A $DEV | grep -i Reallocated"
    ((PENDING>0))&&add_rec "КРИТИЧНО" "Накопитель $NAME: нестабильные сектора — $PENDING" "Возможны ошибки чтения, зависания и повреждение файлов." "Сначала сохранить данные, затем выполнить расширенный SMART-тест и планировать замену." "smartctl -A $DEV | grep -i Pending"
    ((UNCORR>0))&&add_rec "КРИТИЧНО" "Накопитель $NAME: неисправимые сектора — $UNCORR" "Часть данных может быть невосстановима; надёжность носителя снижена." "Обеспечить резервную копию и заменить накопитель." "smartctl -A $DEV | grep -i Uncorrect"
    ((CRITWARN>0))&&add_rec "КРИТИЧНО" "NVMe $NAME: Critical Warning=$CRITWARN" "Контроллер NVMe сообщает критическое состояние." "Сохранить данные и готовить замену накопителя." "smartctl -a $DEV"
    ((MEDIAERR>0))&&add_rec "ВНИМАНИЕ" "NVMe $NAME: ошибок целостности данных — $MEDIAERR" "Счётчик означает зафиксированные ошибки носителя/данных." "Проверить резервное копирование и динамику счётчика. При росте — заменить накопитель." "smartctl -a $DEV"
    if [[ "$RESOURCE" =~ ^([0-9]+)%$ ]]; then R=${BASH_REMATCH[1]}; if ((R<SSD_LIFE_CRIT)); then add_rec "КРИТИЧНО" "Накопитель $NAME: остаточный ресурс ${R}%" "Ресурс записи практически исчерпан." "Срочно сохранить данные и заменить накопитель." "smartctl -a $DEV"; elif ((R<SSD_LIFE_WARN)); then add_rec "ВНИМАНИЕ" "Накопитель $NAME: остаточный ресурс ${R}%" "Запас ресурса мал, накопитель заметно изношен." "Проверить резервное копирование и запланировать замену." "smartctl -a $DEV"; elif ((R<SSD_LIFE_PLAN)); then add_rec "ПЛАНОВО" "Накопитель $NAME: остаточный ресурс ${R}%" "Износ заметен, хотя накопитель ещё может работать штатно." "Усилить контроль SMART и включить замену в плановое обслуживание." "smartctl -a $DEV"; fi; fi
    if [[ "$HOURS" =~ ^[0-9]+$ ]]&&((HOURS>=40000)); then add_rec "ПЛАНОВО" "Накопитель $NAME: большая наработка — ${HOURS} ч" "Большая наработка сама по себе не означает отказ, но повышает возрастной риск." "Поддерживать актуальный бэкап и включить диск в плановый контроль." "smartctl -a $DEV"; fi
    if [[ "$TEMP" =~ ^[0-9]+$ ]]; then TW=0; [ "$DISK_TYPE" = HDD ]&&((TEMP>=HDD_TEMP_WARN))&&TW=1; [ "$DISK_TYPE" = SSD ]&&((TEMP>=SSD_TEMP_WARN))&&TW=1; [ "$DISK_TYPE" = "NVMe SSD" ]&&((TEMP>=NVME_TEMP_WARN))&&TW=1; ((TW==1))&&add_rec "ВНИМАНИЕ" "Накопитель $NAME: повышенная температура ${TEMP}°C" "Уменьшается тепловой запас, возможны троттлинг и ускорение износа." "Проверить пыль, вентиляцию корпуса и охлаждение накопителя." "smartctl -a $DEV | grep -i Temperature"; fi

done < <(lsblk -dn -o NAME,TYPE,SIZE,ROTA,MODEL 2>/dev/null)
DISK_ROWS=("${DISK_SYSTEM_ROWS[@]}" "${DISK_FIXED_ROWS[@]}" "${DISK_REMOVABLE_ROWS[@]}" "${DISK_OPTICAL_ROWS[@]}")
((FIXED_DISKS==0))&&DISK_WORST_SCORE=70

# Системный накопитель задаёт основную оценку storage. Известный дополнительный
# внутренний накопитель влияет только на 20% storage-группы. Съёмные носители
# показываются в отчёте, но не влияют на score, SMART completeness и возраст АРМ.
if ((SYSTEM_DISK_COUNT>0)); then
    STORAGE_SCORE=$SYSTEM_DISK_SCORE
    if ((SECONDARY_KNOWN_COUNT>0)); then STORAGE_SCORE=$(((SYSTEM_DISK_SCORE*80 + SECONDARY_WORST_KNOWN_SCORE*20)/100)); fi
else
    STORAGE_SCORE=$DISK_WORST_SCORE
fi
((RAID_DEGRADED==1)) && STORAGE_SCORE=$(min_score "$STORAGE_SCORE" 30)

# -------------------- БАЛЛЫ --------------------
FS_SCORE=100; FS_WORST=$FS_WORST_USE; ((FS_WORST_INODE>FS_WORST))&&FS_WORST=$FS_WORST_INODE
if ((FS_WORST>=FS_CRIT)); then FS_SCORE=10; elif ((FS_WORST>=FS_HIGH)); then FS_SCORE=40; elif ((FS_WORST>=FS_WARN)); then FS_SCORE=70; elif ((FS_WORST>=70)); then FS_SCORE=90; fi
((LOCAL_RO_COUNT>0))&&FS_SCORE=$(min_score "$FS_SCORE" 50); ((ROOT_RO==1))&&FS_SCORE=0

MEM_SCORE=100; MEM_REASONS=()
if ((MEM_AVAIL_PCT<8)); then
    MEM_SCORE=20; MEM_REASONS+=("критически мало доступной ОЗУ: ${MEM_AVAIL_PCT}%")
elif ((MEM_AVAIL_PCT<15)); then
    MEM_SCORE=45; MEM_REASONS+=("очень мало доступной ОЗУ: ${MEM_AVAIL_PCT}%")
elif ((MEM_AVAIL_PCT<25)); then
    MEM_SCORE=70; MEM_REASONS+=("малый запас доступной ОЗУ: ${MEM_AVAIL_PCT}%")
elif ((MEM_AVAIL_PCT<40)); then
    MEM_SCORE=90; MEM_REASONS+=("сниженный запас доступной ОЗУ: ${MEM_AVAIL_PCT}%")
fi
if ((SWAP_USED_PCT>=80 && MEM_AVAIL_PCT<25)); then
    MEM_SCORE=$(min_score "$MEM_SCORE" 60)
    MEM_REASONS+=("Swap использован на ${SWAP_USED_PCT}% при доступной ОЗУ ${MEM_AVAIL_PCT}%")
fi
if ((OOM_DETECTED==1)); then
    MEM_SCORE=$(min_score "$MEM_SCORE" 30)
    MEM_REASONS+=("за текущую загрузку срабатывал OOM-killer")
fi
MEM_SCORE=$(clamp_score "$MEM_SCORE")
if ((MEM_SCORE==100)); then
    MEM_STATUS="Норма"
elif ((MEM_SCORE>=90)); then
    MEM_STATUS="Незначительное отклонение"
elif ((MEM_SCORE>=70)); then
    MEM_STATUS="Требует внимания"
else
    MEM_STATUS="Неудовлетворительное состояние"
fi
MEM_REASON_TEXT=""
if ((${#MEM_REASONS[@]}>0)); then
    MEM_REASON_TEXT=$(IFS='; '; echo "${MEM_REASONS[*]}")
fi
SWAP_NOTE=""
if ((SWAP_USED_PCT>=70 && MEM_AVAIL_PCT>=40 && OOM_DETECTED==0)); then
    SWAP_NOTE="Высокое заполнение Swap не снижает оценку: доступной ОЗУ ${MEM_AVAIL_PCT}%"
fi

# Стабильность системы: прозрачная модель штрафов от 100 баллов.
# Это не оценка качества/целостности самой ОС: сюда входят runtime-сигналы
# systemd, kernel journal, OOM, время и ECC, то есть устойчивость АРМ в целом.
STAB_SCORE=100
STAB_PENALTY_FAILED=0
STAB_PENALTY_HW=0
STAB_PENALTY_JOURNAL=0
STAB_PENALTY_OOM=0
STAB_PENALTY_TIME=0
STAB_PENALTY_UNCLEAN=0
STAB_PENALTY_ECC_CE=0
STAB_ECC_UE_CAP=0

if ((FAILED_COUNT==1)); then STAB_PENALTY_FAILED=5
elif ((FAILED_COUNT>=2 && FAILED_COUNT<=3)); then STAB_PENALTY_FAILED=10
elif ((FAILED_COUNT>3)); then STAB_PENALTY_FAILED=20
fi

if ((HW_ERR_COUNT>=1 && HW_ERR_COUNT<=2)); then STAB_PENALTY_HW=10
elif ((HW_ERR_COUNT>=3 && HW_ERR_COUNT<=5)); then STAB_PENALTY_HW=20
elif ((HW_ERR_COUNT>5)); then STAB_PENALTY_HW=35
fi

if ((JOURNAL_ERR_COUNT>=6 && JOURNAL_ERR_COUNT<=15)); then STAB_PENALTY_JOURNAL=5
elif ((JOURNAL_ERR_COUNT>=16 && JOURNAL_ERR_COUNT<=30)); then STAB_PENALTY_JOURNAL=10
elif ((JOURNAL_ERR_COUNT>30)); then STAB_PENALTY_JOURNAL=15
fi

((OOM_DETECTED==1)) && STAB_PENALTY_OOM=10
[ "$TIME_SYNC" = "Нет" ] && STAB_PENALTY_TIME=5
((UNCLEAN_BOOT_SIGNS>0)) && STAB_PENALTY_UNCLEAN=5
((ECC_CE>0)) && STAB_PENALTY_ECC_CE=5

STAB_SCORE=$((STAB_SCORE - STAB_PENALTY_FAILED - STAB_PENALTY_HW - STAB_PENALTY_JOURNAL - STAB_PENALTY_OOM - STAB_PENALTY_TIME - STAB_PENALTY_UNCLEAN - STAB_PENALTY_ECC_CE))
if ((ECC_UE>0)); then
    STAB_ECC_UE_CAP=30
    STAB_SCORE=$(min_score "$STAB_SCORE" "$STAB_ECC_UE_CAP")
fi
STAB_SCORE=$(clamp_score "$STAB_SCORE")

if ((STAB_SCORE>=90)); then STAB_STATUS="Норма"
elif ((STAB_SCORE>=75)); then STAB_STATUS="Незначительные отклонения"
elif ((STAB_SCORE>=50)); then STAB_STATUS="Требует внимания"
else STAB_STATUS="Сниженная стабильность"
fi

CPU_SCORE=100; CPU_REASONS=()
if [[ "$CPU_TEMP" =~ ^[0-9]+$ ]]; then
    if ((CPU_TEMP>=CPU_TEMP_CRIT)); then
        CPU_SCORE=30; CPU_REASONS+=("критическая температура CPU: ${CPU_TEMP}°C")
    elif ((CPU_TEMP>=CPU_TEMP_VHIGH)); then
        CPU_SCORE=55; CPU_REASONS+=("высокая температура CPU: ${CPU_TEMP}°C")
    elif ((CPU_TEMP>=CPU_TEMP_HIGH)); then
        CPU_SCORE=75; CPU_REASONS+=("повышенная температура CPU: ${CPU_TEMP}°C")
    elif ((CPU_TEMP>=CPU_TEMP_WARN)); then
        CPU_SCORE=90; CPU_REASONS+=("температура CPU выше нормального рабочего диапазона: ${CPU_TEMP}°C")
    fi
fi
LOAD_STATE=0
if [[ "$THREADS" =~ ^[0-9]+$ ]]&&((THREADS>0)); then
    LOAD_STATE=$(awk -v l="$LOAD1" -v t="$THREADS" 'BEGIN{if(l>=2*t)print 2;else if(l>=t)print 1;else print 0}')
    if ((LOAD_STATE==2)); then
        CPU_SCORE=$(min_score "$CPU_SCORE" 60)
        CPU_REASONS+=("высокая системная нагрузка: Load1=$LOAD1 при $THREADS потоках")
    elif ((LOAD_STATE==1)); then
        CPU_SCORE=$(min_score "$CPU_SCORE" 85)
        CPU_REASONS+=("повышенная системная нагрузка: Load1=$LOAD1 при $THREADS потоках")
    fi
fi
CPU_SCORE=$(clamp_score "$CPU_SCORE")
if ((CPU_SCORE==100)); then
    CPU_STATUS="Норма"
elif ((CPU_SCORE>=90)); then
    CPU_STATUS="Незначительное отклонение"
elif ((CPU_SCORE>=70)); then
    CPU_STATUS="Требует внимания"
else
    CPU_STATUS="Неудовлетворительное состояние"
fi
CPU_REASON_TEXT=""
if ((${#CPU_REASONS[@]}>0)); then
    CPU_REASON_TEXT=$(IFS='; '; echo "${CPU_REASONS[*]}")
fi

AGE_DISK_HOURS=$MAX_DISK_HOURS; AGE_DISK_SOURCE="макс. наработка внутреннего накопителя"
if ((SYSTEM_MAX_DISK_HOURS>0)); then AGE_DISK_HOURS=$SYSTEM_MAX_DISK_HOURS; AGE_DISK_SOURCE="наработка системного накопителя"; fi
DISK_AGE_MONTHS=-1; DISK_AGE_YEARS=-1; ((AGE_DISK_HOURS>0))&&{ DISK_AGE_MONTHS=$((AGE_DISK_HOURS*12/8760)); DISK_AGE_YEARS=$((DISK_AGE_MONTHS/12)); }
OS_AGE_MONTHS=-1; ((AGE_DAYS>=0))&&OS_AGE_MONTHS=$((AGE_DAYS*12/365))
SYSTEM_AGE_MONTHS=-1; AGE_SOURCE="Не определён"
if ((DISK_AGE_MONTHS>=0 && OS_AGE_MONTHS>=0)); then if ((DISK_AGE_MONTHS>=OS_AGE_MONTHS)); then SYSTEM_AGE_MONTHS=$DISK_AGE_MONTHS; AGE_SOURCE="$AGE_DISK_SOURCE"; else SYSTEM_AGE_MONTHS=$OS_AGE_MONTHS; AGE_SOURCE="возраст текущей установки ОС"; fi
elif ((DISK_AGE_MONTHS>=0)); then SYSTEM_AGE_MONTHS=$DISK_AGE_MONTHS; AGE_SOURCE="$AGE_DISK_SOURCE"; elif ((OS_AGE_MONTHS>=0)); then SYSTEM_AGE_MONTHS=$OS_AGE_MONTHS; AGE_SOURCE="возраст текущей установки ОС"; fi
SYSTEM_AGE_TEXT="Не определён"; ((SYSTEM_AGE_MONTHS>=0))&&SYSTEM_AGE_TEXT=$(format_years_ru_from_months "$SYSTEM_AGE_MONTHS")
AGE_SCORE=90
if ((SYSTEM_AGE_MONTHS>=0)); then if ((SYSTEM_AGE_MONTHS<=36)); then AGE_SCORE=100; elif ((SYSTEM_AGE_MONTHS<=48)); then AGE_SCORE=97; elif ((SYSTEM_AGE_MONTHS<=60)); then AGE_SCORE=93; elif ((SYSTEM_AGE_MONTHS<=72)); then AGE_SCORE=88; elif ((SYSTEM_AGE_MONTHS<=84)); then AGE_SCORE=82; elif ((SYSTEM_AGE_MONTHS<=96)); then AGE_SCORE=75; elif ((SYSTEM_AGE_MONTHS<=108)); then AGE_SCORE=68; elif ((SYSTEM_AGE_MONTHS<=120)); then AGE_SCORE=60; else AGE_SCORE=52; fi; fi

NET_SCORE=100; ((ACTIVE_NET==0))&&NET_SCORE=20; [ "$GW" = - ]&&NET_SCORE=$(min_score "$NET_SCORE" 60); [ "$DNS" = - ]&&NET_SCORE=$(min_score "$NET_SCORE" 70)
if ((NET_ERROR_PPM>=NET_ERROR_CRIT_PPM || NET_DROP_PPM>=NET_DROP_CRIT_PPM)); then
    NET_SCORE=$(min_score "$NET_SCORE" 50)
elif ((NET_ERROR_PPM>=NET_ERROR_WARN_PPM || NET_DROP_PPM>=NET_DROP_HIGH_PPM)); then
    NET_SCORE=$(min_score "$NET_SCORE" 70)
elif ((NET_ERROR_PPM>=NET_ERROR_NOTICE_PPM || NET_DROP_PPM>=NET_DROP_WARN_PPM)); then
    NET_SCORE=$(min_score "$NET_SCORE" 90)
fi

# Итог считается только по тем группам, для которых есть достоверные данные.
# Неизвестный SMART не превращается в "100/100" — группа исключается из среднего,
# а полнота диагностики отдельно показывает ограничение.
STORAGE_KNOWN=1
if ((SYSTEM_DISK_COUNT>0)); then
    if ! command -v smartctl >/dev/null 2>&1 || ((SYSTEM_SMART_UNKNOWN_COUNT>0)); then STORAGE_KNOWN=0; fi
else
    if ! command -v smartctl >/dev/null 2>&1 && ((FIXED_DISKS>0)); then STORAGE_KNOWN=0; fi
    ((SMART_UNKNOWN_COUNT>0))&&STORAGE_KNOWN=0
fi
AGE_KNOWN=1; ((SYSTEM_AGE_MONTHS<0))&&AGE_KNOWN=0
TOTAL_NUM=$((FS_SCORE*15 + STAB_SCORE*15 + MEM_SCORE*10 + CPU_SCORE*10 + NET_SCORE*5))
TOTAL_DEN=55
if ((STORAGE_KNOWN==1)); then TOTAL_NUM=$((TOTAL_NUM + STORAGE_SCORE*40)); TOTAL_DEN=$((TOTAL_DEN+40)); fi
if ((AGE_KNOWN==1)); then TOTAL_NUM=$((TOTAL_NUM + AGE_SCORE*5)); TOTAL_DEN=$((TOTAL_DEN+5)); fi
if ((TOTAL_DEN>0)); then TOTAL_SCORE=$((TOTAL_NUM/TOTAL_DEN)); else TOTAL_SCORE=0; fi
TOTAL_SCORE=$(clamp_score "$TOTAL_SCORE")

# -------------------- ПОЛНОТА --------------------
CONFIDENCE=100; CONFIDENCE_NOTES=()
if ! command -v smartctl >/dev/null 2>&1 && ((FIXED_DISKS>0)); then
    CONFIDENCE=$((CONFIDENCE-25)); CONFIDENCE_NOTES+=("нет smartctl для внутренних накопителей")
elif ((SYSTEM_DISK_COUNT>0 && SYSTEM_SMART_UNKNOWN_COUNT>0)); then
    CONFIDENCE=$((CONFIDENCE-15)); CONFIDENCE_NOTES+=("SMART системного накопителя недоступен")
elif ((SYSTEM_DISK_COUNT==0 && SMART_UNKNOWN_COUNT>0)); then
    CONFIDENCE=$((CONFIDENCE-15)); CONFIDENCE_NOTES+=("SMART внутренних накопителей частично недоступен")
elif ((SMART_UNKNOWN_COUNT>0)); then
    CONFIDENCE_NOTES+=("SMART части дополнительных накопителей недоступен (без штрафа полноты)")
fi
[ "$CPU_TEMP" = - ]&&{ CONFIDENCE=$((CONFIDENCE-5)); CONFIDENCE_NOTES+=("нет температуры CPU"); }
((SYSTEM_AGE_MONTHS<0))&&{ CONFIDENCE=$((CONFIDENCE-5)); CONFIDENCE_NOTES+=("нет возраста/наработки"); }
((JOURNAL_AVAILABLE==0))&&{ CONFIDENCE=$((CONFIDENCE-10)); CONFIDENCE_NOTES+=("journal недоступен"); }
((SYSTEMD_AVAILABLE==0))&&{ CONFIDENCE=$((CONFIDENCE-5)); CONFIDENCE_NOTES+=("службы не проверены"); }
[ "$RAM_MODULES" = "?" ]&&{ CONFIDENCE=$((CONFIDENCE-5)); CONFIDENCE_NOTES+=("DMI ОЗУ недоступен"); }
[ "$(id -u)" -ne 0 ]&&{ CONFIDENCE=$((CONFIDENCE-10)); CONFIDENCE_NOTES+=("запуск не от root"); }
((CONFIDENCE<40))&&CONFIDENCE=40
CONFIDENCE_NOTE="-"; ((${#CONFIDENCE_NOTES[@]}>0))&&CONFIDENCE_NOTE=$(printf '%s, ' "${CONFIDENCE_NOTES[@]}"); CONFIDENCE_NOTE=${CONFIDENCE_NOTE%, }

if ((TOTAL_SCORE>=90)); then STATE="ОТЛИЧНОЕ"; elif ((TOTAL_SCORE>=80)); then STATE="ХОРОШЕЕ"; elif ((TOTAL_SCORE>=65)); then STATE="ТРЕБУЕТ ВНИМАНИЯ"; elif ((TOTAL_SCORE>=50)); then STATE="ПЛОХОЕ"; else STATE="КРИТИЧЕСКОЕ"; fi
if ((ROOT_RO==1 || (SYSTEM_DISK_COUNT>0 && SYSTEM_DISK_SCORE<30) || (SYSTEM_DISK_COUNT==0 && STORAGE_SCORE<30) || ROOT_USE>=98 || RAID_DEGRADED==1 || ECC_UE>0)); then STATE="КРИТИЧЕСКОЕ"; elif ((SECONDARY_CRITICAL==1 || OOM_DETECTED==1 || HW_ERR_COUNT>0 || ROOT_USE>=95 || ACTIVE_NET==0)); then [ "$STATE" = "ОТЛИЧНОЕ" ]||[ "$STATE" = "ХОРОШЕЕ" ]&&STATE="ТРЕБУЕТ ВНИМАНИЯ"; fi
STATE_DISPLAY="$STATE"; ((CONFIDENCE<80))&&STATE_DISPLAY="ПРЕДВАРИТЕЛЬНО: $STATE"

# -------------------- РЕКОМЕНДАЦИИ --------------------
printf -v FS_WORST_USE_Q '%q' "$FS_WORST_USE_MOUNT"
printf -v FS_WORST_INODE_Q '%q' "$FS_WORST_INODE_MOUNT"
if ! command -v smartctl >/dev/null 2>&1 && ((FIXED_DISKS>0)); then add_rec "ПРОВЕРКА" "SMART внутренних накопителей не проверен" "Без SMART нельзя достоверно оценить системный SSD/NVMe/HDD." "Установить smartmontools и повторить диагностику." "dnf install smartmontools"; elif ((SYSTEM_SMART_UNKNOWN_COUNT>0)); then add_rec "ПРОВЕРКА" "SMART системного накопителя недоступен" "Основной накопитель АРМ оценён не полностью; съёмные носители на этот статус не влияют." "Проверить поддержку SMART системного устройства и повторить диагностику." "smartctl --scan-open"; elif ((SMART_UNKNOWN_COUNT>0)); then add_rec "ПРОВЕРКА" "SMART дополнительных накопителей частично недоступен" "Системный накопитель имеет приоритет; неполные данные относятся к дополнительным внутренним дискам." "При необходимости проверить дополнительные диски отдельно." "smartctl --scan-open"; fi
if ((FS_WORST_USE>=FS_CRIT)); then add_rec "КРИТИЧНО" "ФС $FS_WORST_USE_MOUNT заполнена на ${FS_WORST_USE}%" "Может прекратиться запись журналов, временных файлов и работа служб." "Срочно освободить минимум 10–15% объёма." "du -xhd1 $FS_WORST_USE_Q 2>/dev/null | sort -h | tail -20"; elif ((FS_WORST_USE>=FS_HIGH)); then add_rec "ВНИМАНИЕ" "ФС $FS_WORST_USE_MOUNT заполнена на ${FS_WORST_USE}%" "Мало места для обновлений, журналов и рабочих файлов." "Освободить место до уровня ниже 80%." "du -xhd1 $FS_WORST_USE_Q 2>/dev/null | sort -h | tail -20"; elif ((FS_WORST_USE>=FS_WARN)); then add_rec "ПЛАНОВО" "ФС $FS_WORST_USE_MOUNT заполнена на ${FS_WORST_USE}%" "Снижается резерв свободного места." "Выполнить плановую очистку и держать заполнение ниже 80%." "df -h $FS_WORST_USE_Q"; fi
((FS_WORST_INODE>=INODE_WARN))&&add_rec "ВНИМАНИЕ" "Inode на $FS_WORST_INODE_MOUNT использованы на ${FS_WORST_INODE}%" "При исчерпании inode новые файлы создать нельзя даже при наличии свободного места." "Найти каталоги с большим количеством мелких файлов и очистить ненужные кэши/временные данные." "df -i $FS_WORST_INODE_Q; du --inodes -x -d1 $FS_WORST_INODE_Q 2>/dev/null | sort -n | tail -20"
((ROOT_RO==1))&&add_rec "КРИТИЧНО" "Корневая ФС смонтирована read-only" "Запись данных, обновления и часть служб могут не работать." "Проверить журнал ядра; fsck выполнять только на размонтированной ФС из rescue/live." "findmnt -no SOURCE,FSTYPE,OPTIONS /; journalctl -k -b -p warning..alert --no-pager"
if ((MEM_AVAIL_PCT<15)); then add_rec "ВНИМАНИЕ" "Мало доступной ОЗУ — ${MEM_AVAIL_PCT}%" "Возможны торможения, swap и OOM." "Определить крупнейшие процессы; при постоянном дефиците увеличить RAM." "free -h; ps -eo pid,ppid,user,stat,%mem,%cpu,comm --sort=-%mem | head -20; vmstat 1 5"; elif ((MEM_AVAIL_PCT<25)); then add_rec "ПЛАНОВО" "Небольшой запас ОЗУ — ${MEM_AVAIL_PCT}%" "При росте нагрузки система может активнее использовать swap." "Проверить крупнейшие процессы и наблюдать динамику." "free -h"; fi
((OOM_DETECTED==1))&&add_rec "КРИТИЧНО" "За текущую загрузку срабатывал OOM-killer" "Ядро принудительно завершало процесс из-за нехватки памяти." "Определить процесс-виновник и устранить дефицит/утечку; при необходимости увеличить RAM или swap." "journalctl -k -b | grep -Ei 'oom-kill|out of memory'"
((FAILED_COUNT>0))&&add_rec "ВНИМАНИЕ" "Есть failed-службы: $FAILED_NAMES" "Функции этих служб могут быть недоступны или работать частично." "Проверить каждую службу, устранить первичную ошибку и перезапустить." "systemctl --failed; systemctl status UNIT_NAME --no-pager -l; journalctl -u UNIT_NAME -b --no-pager | tail -120"
((HW_ERR_COUNT>0))&&add_rec "КРИТИЧНО" "В ядре обнаружены аппаратные/дисковые ошибки — $HW_ERR_COUNT" "Возможны I/O-сбои, зависания и повреждение данных." "Сопоставить сообщение с устройством, проверить SMART, кабели и питание." "journalctl -k -b -p warning..alert --no-pager; smartctl -a DEVICE_PATH"
if ((JOURNAL_AVAILABLE==1 && JOURNAL_ERR_COUNT>30)); then add_rec "ВНИМАНИЕ" "Много уникальных ошибок journal — $JOURNAL_ERR_COUNT" "Возможна нестабильная служба, драйвер или повторяющаяся системная проблема." "Сгруппировать ошибки по источнику и устранить первичную причину." "journalctl -b -p err..alert -o short-iso --no-pager"; elif ((JOURNAL_AVAILABLE==1 && JOURNAL_ERR_COUNT>=6)); then add_rec "ПРОВЕРКА" "В journal есть уникальные ошибки — $JOURNAL_ERR_COUNT" "Не все error-сообщения критичны, но их нужно сопоставить с используемыми службами." "Просмотреть ошибки и проверить повторяемость." "journalctl -b -p err..alert -o short-iso --no-pager"; fi
if [[ "$CPU_TEMP" =~ ^[0-9]+$ ]]&&((CPU_TEMP>=CPU_TEMP_VHIGH)); then add_rec "КРИТИЧНО" "Высокая температура CPU — ${CPU_TEMP}°C" "Возможен троттлинг и аварийное выключение." "Очистить охлаждение, проверить вентилятор/радиатор и термоинтерфейс." "sensors"; elif [[ "$CPU_TEMP" =~ ^[0-9]+$ ]]&&((CPU_TEMP>=CPU_TEMP_WARN)); then add_rec "ВНИМАНИЕ" "Повышенная температура CPU — ${CPU_TEMP}°C" "Тепловой запас снижен; под нагрузкой возможен троттлинг." "Проверить пыль, вентилятор и температуру при типовой нагрузке." "sensors"; fi
if ((LOAD_STATE==2)); then add_rec "ВНИМАНИЕ" "Высокая системная нагрузка: Load1=$LOAD1" "Очередь задач/ожидания I/O велика, возможны задержки." "Найти процесс или I/O-источник постоянной нагрузки." "top -b -n1 | head -30"; elif ((LOAD_STATE==1)); then add_rec "ПРОВЕРКА" "Повышенная системная нагрузка: Load1=$LOAD1" "Система близка к полной загрузке CPU или имеет очередь I/O." "Если нагрузка не кратковременная — найти источник." "top -b -n1 | head -30"; fi
if ((SYSTEM_AGE_MONTHS>=96)); then add_rec "ПЛАНОВО" "Эксплуатационный ориентир — около ${SYSTEM_AGE_TEXT}" "Возраст сам по себе не означает неисправность, но повышает риск отказа вентиляторов, БП и контактов." "Обеспечить резервное копирование, профилактику и план обновления по фактическому состоянию." "$ARM_INFO_SELF_CMD"; elif ((SYSTEM_AGE_MONTHS>=72)); then add_rec "ПЛАНОВО" "Эксплуатационный ориентир — около ${SYSTEM_AGE_TEXT}" "Возрастной риск постепенно растёт." "Усилить контроль SMART, охлаждения и резервного копирования." "$ARM_INFO_SELF_CMD"; fi
((ACTIVE_NET==0))&&add_rec "КРИТИЧНО" "Не найден активный IPv4-интерфейс" "Сетевые ресурсы, домен и обновления могут быть недоступны." "Проверить линк, кабель и сетевой профиль." "ip -br addr; nmcli device status"
[ "$GW" = - ]&&add_rec "ВНИМАНИЕ" "Не найден маршрут по умолчанию" "Доступ за пределы локальной подсети может отсутствовать." "Проверить маршрут и шлюз активного профиля." "ip -4 route"
[ "$DNS" = - ]&&add_rec "ВНИМАНИЕ" "DNS-серверы не определены" "Имена узлов и доменные сервисы могут не разрешаться." "Проверить /etc/resolv.conf и DNS в NetworkManager/systemd-resolved." "cat /etc/resolv.conf; nmcli -f GENERAL.CONNECTION,IP4.DNS,IP4.DOMAIN device show; resolvectl status 2>/dev/null"
if ((NET_ERROR_PPM>=NET_ERROR_WARN_PPM || NET_DROP_PPM>=NET_DROP_WARN_PPM)); then
    BAD_IF_TEXT=$(IFS=,;echo "${NET_BAD_IFACES[*]}")
    add_rec "ВНИМАНИЕ" "Повышенная доля сетевых ошибок/учитываемых потерь" "Ошибки: ${NET_ERROR_PPM} ppm; учитываемые потери: ${NET_SCORED_LOSS_PPM} ppm. RX dropped: ${NET_RX_DROP_PPM_RAW} ppm (информационно, сам по себе не снижает оценку)." "Проверить кабель/порт, драйвер и детальные счётчики NIC: rx_missed_errors, CRC/frame/FIFO/carrier и tx_dropped. ${BAD_IF_TEXT}" "ip -s -s link; ethtool -S IFACE_NAME 2>/dev/null"
fi

[ "$TIME_SYNC" = "Нет" ] && add_rec "ВНИМАНИЕ" "Системное время не синхронизировано" "Ошибки времени нарушают TLS и особенно Kerberos/AD-аутентификацию." "Проверить chronyd/systemd-timesyncd, NTP-серверы и сетевую доступность." "timedatectl; chronyc tracking 2>/dev/null; chronyc sources -v 2>/dev/null"
((UNCLEAN_BOOT_SIGNS>0)) && add_rec "ПРОВЕРКА" "Есть признаки аварийного завершения предыдущей загрузки" "Нештатное выключение может указывать на питание, зависание ядра или аппаратный сбой." "Изучить журнал предыдущей загрузки и сопоставить со временем инцидента." "journalctl --list-boots; journalctl -b -1 -p warning..alert --no-pager"
((RAID_DEGRADED==1)) && add_rec "КРИТИЧНО" "Software RAID находится в DEGRADED" "Отказ ещё одного диска может привести к потере массива и данных." "Срочно проверить /proc/mdstat, определить неисправный член массива и восстановить резервирование." "cat /proc/mdstat; mdadm --detail MD_DEVICE"
((ECC_UE>0)) && add_rec "КРИТИЧНО" "ECC: обнаружены неисправимые ошибки памяти ($ECC_UE)" "Неисправимые ошибки памяти могут приводить к повреждению данных и аварийному завершению процессов." "Провести аппаратный тест ОЗУ и заменить неисправный модуль/слот." "grep -R . /sys/devices/system/edac/mc/mc*/ue_count 2>/dev/null"
((ECC_UE==0 && ECC_CE>0)) && add_rec "ПРОВЕРКА" "ECC: исправленных ошибок памяти — $ECC_CE" "ECC исправил ошибки, но рост счётчика может указывать на деградацию памяти." "Зафиксировать значения и проверить их рост при повторной диагностике." "grep -R . /sys/devices/system/edac/mc/mc*/ce_count 2>/dev/null"
if [[ "$BATTERY_HEALTH" =~ ^([0-9]+)%$ ]] && ((BASH_REMATCH[1]<60)); then add_rec "ПЛАНОВО" "Износ батареи: остаточная ёмкость около ${BATTERY_HEALTH}" "Снижается автономность; при дальнейшем износе возможны внезапные отключения без питания." "Проверить батарею и запланировать замену при неудовлетворительной автономности." "grep -H . /sys/class/power_supply/BAT*/{capacity,energy_full,energy_full_design,charge_full,charge_full_design,cycle_count} 2>/dev/null"; fi
if [ "$SSSD_STATUS" != "Не установлен" ] && [ "$SSSD_STATUS" != "active" ]; then add_rec "ВНИМАНИЕ" "SSSD установлен, но состояние: $SSSD_STATUS" "Может не работать доменная аутентификация, разрешение пользователей и групп." "Проверить службу SSSD, конфигурацию и журнал." "systemctl status sssd --no-pager -l; journalctl -u sssd -b --no-pager | tail -150; sssctl config-check"; fi
if [ "$CUPS_STATUS" != "Не установлен" ] && [ "$CUPS_STATUS" != "active" ] && ((CUPS_QUEUES>0)); then add_rec "ВНИМАНИЕ" "CUPS не активен при наличии очередей печати" "Локальная печать через CUPS недоступна." "Запустить CUPS и проверить причину остановки." "systemctl status cups --no-pager -l; journalctl -u cups -b --no-pager | tail -150; lpstat -r"; fi

# -------------------- ЗАКЛЮЧЕНИЕ --------------------
if ((TOTAL_SCORE>=80))&&[[ "$STATE" != КРИТИЧЕСКОЕ ]]; then if ((CONFIDENCE>=80)); then CONCLUSION="По результатам диагностики техническое состояние АРМ соответствует требованиям, предъявляемым к выполнению текущих задач."; else CONCLUSION="По доступным данным техническое состояние АРМ соответствует требованиям текущих задач, однако полнота проверки составляет ${CONFIDENCE}%; требуется устранить ограничения диагностики."; fi
elif ((TOTAL_SCORE>=65))&&[[ "$STATE" != КРИТИЧЕСКОЕ ]]; then CONCLUSION="АРМ работоспособен и может использоваться для текущих задач, однако выявлены факторы, требующие планового обслуживания."
elif ((TOTAL_SCORE>=50))&&[[ "$STATE" != КРИТИЧЕСКОЕ ]]; then CONCLUSION="Работоспособность АРМ сохранена, но техническое состояние неудовлетворительно; рекомендуется устранить выявленные замечания."
else CONCLUSION="Техническое состояние АРМ не позволяет считать его надёжно работоспособным; требуется диагностика и устранение критических замечаний."; fi

# -------------------- ПРИВАТНОСТЬ / ФОРМАТЫ --------------------
mask_ipv4() {
    local ip=$1
    if [[ "$ip" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        printf '%s.%s.x.x' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
        printf 'скрыто'
    fi
}
json_escape() {
    local v=${1-}
    v=${v//\\/\\\\}
    v=${v//\"/\\\"}
    v=${v//$'\n'/\\n}
    v=${v//$'\r'/\\r}
    v=${v//$'\t'/\\t}
    printf '%s' "$v"
}
if ((PRIVACY_MODE==1)); then
    HOST_DISPLAY="ARM-REDACTED"
    GW_DISPLAY=$([ "$GW" = - ] && echo - || mask_ipv4 "$GW")
    DNS_DISPLAY=$([ "$DNS" = - ] && echo - || echo "скрыто")
else
    HOST_DISPLAY="$HOST"; GW_DISPLAY="$GW"; DNS_DISPLAY="$DNS"
fi

# -------------------- ВЫВОД --------------------
if ((JSON_MODE==0)); then
echo "ДИАГНОСТИЧЕСКИЙ ОТЧЁТ АРМ"
echo "Дата: $(date '+%d.%m.%Y %H:%M:%S')"
if ((SAVE_REPORT==1)); then echo "Отчёт: $REPORT_FILE"; fi

section "СИСТЕМА"
{
 echo "Хост|$HOST_DISPLAY"; echo "ОС|$OS"; echo "Модель системы|$SYSTEM_VENDOR $SYSTEM_PRODUCT"; echo "Ядро|$KERNEL"; echo "Архитектура|$ARCH"; echo "Установка ОС|$INSTALL_DATE"; echo "BIOS|$BIOS_VERSION; дата $BIOS_DATE (справочно)"; ((MAX_DISK_HOURS>0))&&echo "Макс. наработка диска|${MAX_DISK_HOURS} ч"; ((SYSTEM_AGE_MONTHS>=0))&&echo "Эксплуатационный ориентир|≈ ${SYSTEM_AGE_TEXT} ($AGE_SOURCE)"; echo "Время работы|$UPTIME"
} | table

section "ПРОЦЕССОР"
{
 echo "Модель|$CPU_MODEL"
 echo "Сокетов|$SOCKETS"
 echo "Ядер / потоков|$CORES / $THREADS"
 echo "Load 1 мин|$LOAD1"
 if [[ "$CPU_TEMP" =~ ^[0-9]+$ ]]; then
     echo "Температура CPU|${CPU_TEMP}°C (медиана)"
 else
     echo "Температура CPU|Не определена"
 fi
 echo "Оценка CPU|$CPU_SCORE / 100"
 if [ "$CPU_TEMP" = "-" ] && ((CPU_SCORE==100)); then
     echo "Состояние|Норма по доступным данным"
 else
     echo "Состояние|$CPU_STATUS"
 fi
 [ -n "$CPU_REASON_TEXT" ] && echo "Причина снижения|$CPU_REASON_TEXT"
} | table

section "ОПЕРАТИВНАЯ ПАМЯТЬ"
{
 echo "Тип / частота|$RAM_TYPE / $RAM_SPEED"
 echo "Модулей установлено|$RAM_MODULES"
 echo "Всего / занято / доступно|$RAM_TOTAL / $RAM_USED / $RAM_AVAIL"
 echo "Доступно|${MEM_AVAIL_PCT}%"
 echo "Swap использовано|${SWAP_USED_PCT}%"
 echo "Оценка ОЗУ|$MEM_SCORE / 100"
 echo "Состояние|$MEM_STATUS"
 [ -n "$MEM_REASON_TEXT" ] && echo "Причина снижения|$MEM_REASON_TEXT"
 [ -n "$SWAP_NOTE" ] && echo "Примечание|$SWAP_NOTE"
} | table

section "СТАБИЛЬНОСТЬ СИСТЕМЫ"
{
 echo "Оценка|$STAB_SCORE / 100|вес в общем индексе 15%"
 echo "Состояние|$STAB_STATUS|-"
 echo "Failed-службы|$FAILED_COUNT|$STAB_PENALTY_FAILED"
 echo "Ошибки ядра HW/storage|$HW_ERR_COUNT|$STAB_PENALTY_HW"
 echo "Уникальные journal err..alert|$JOURNAL_ERR_COUNT|$STAB_PENALTY_JOURNAL"
 echo "OOM-killer|$([ "$OOM_DETECTED" -eq 1 ] && echo Да || echo Нет)|$STAB_PENALTY_OOM"
 echo "Синхронизация времени|$TIME_SYNC|$STAB_PENALTY_TIME"
 echo "Признаки аварийной загрузки|$UNCLEAN_BOOT_SIGNS|$STAB_PENALTY_UNCLEAN"
 echo "ECC corrected / uncorrectable|$ECC_CE / $ECC_UE|$STAB_PENALTY_ECC_CE"
 if ((STAB_ECC_UE_CAP>0)); then echo "Ограничение из-за ECC UE|оценка не выше $STAB_ECC_UE_CAP|критический фактор"; fi
} | { printf 'Показатель|Значение|Штраф, баллов\n'; cat; } | table

echo "Примечание: показатель отражает устойчивость работы АРМ по системным событиям;"
echo "он не означает, что сама установленная ОС повреждена или неисправна."

section "СЕТЬ"
if ((${#NET_ROWS[@]})); then
    NET_NUM=0
    for NET_ROW in "${NET_ROWS[@]}"; do
        NET_NUM=$((NET_NUM+1))
        IFS='|' read -r N_IFACE N_IP N_MAC N_LINK <<< "$NET_ROW"
        if ((PRIVACY_MODE==1)); then
            N_IFACE="net${NET_NUM}"
            N_IP=$(mask_ipv4 "$N_IP")
            N_MAC="xx:xx:xx:xx:xx:xx"
        fi

        # Вертикальный вывод не съезжает на узких терминалах
        # и сохраняет полное имя сетевого интерфейса.
        {
            if ((${#NET_ROWS[@]}>1)); then
                echo "Интерфейс ${NET_NUM}|$N_IFACE"
            else
                echo "Интерфейс|$N_IFACE"
            fi
            echo "IP-адрес|$N_IP"
            echo "MAC|$N_MAC"
            if [ "$N_LINK" = "-" ]; then
                echo "Линк|Не определён"
            else
                N_LINK_TEXT=${N_LINK/M/Mbit/s}
                N_LINK_TEXT=${N_LINK_TEXT/\/unknown/ / duplex Н/Д}
                N_LINK_TEXT=${N_LINK_TEXT/\/full/ / full duplex}
                N_LINK_TEXT=${N_LINK_TEXT/\/half/ / half duplex}
                echo "Линк|$N_LINK_TEXT"
            fi
        } | table
        ((${#NET_ROWS[@]}>1 && NET_NUM<${#NET_ROWS[@]})) && echo
    done
else
    { echo "Интерфейс|IPv4 не найден"; echo "IP-адрес|-"; echo "MAC|-"; echo "Линк|-"; } | table
fi

{
 echo "Шлюз|$GW_DISPLAY"
 if [ "$DNS_DISPLAY" = "-" ]; then
     echo "DNS|-"
 elif ((PRIVACY_MODE==1)); then
     echo "DNS|скрыто"
 else
     DNS_FIRST=1
     IFS=',' read -ra DNS_ITEMS <<< "$DNS_DISPLAY"
     for DNS_ITEM in "${DNS_ITEMS[@]}"; do
         [ -n "$DNS_ITEM" ] || continue
         if ((DNS_FIRST)); then
             echo "DNS|$DNS_ITEM"
             DNS_FIRST=0
         else
             echo "|$DNS_ITEM"
         fi
     done
 fi
} | table

echo
{
 echo "RX ошибки|$RX_ERRORS_TOTAL"
 echo "TX ошибки|$TX_ERRORS_TOTAL"
 echo "RX dropped (информационно)|$RX_DROPS_TOTAL"
 echo "RX missed (учитывается)|$RX_MISSED_TOTAL"
 echo "TX dropped (учитывается)|$TX_DROPS_TOTAL"
 echo "Пакетов RX / TX|$RX_PACKETS_TOTAL / $TX_PACKETS_TOTAL"
 echo "Доля ошибок|${NET_ERROR_PPM} ppm"
 echo "RX dropped (информационно)|${NET_RX_DROP_PPM_RAW} ppm"
 echo "Учитываемые потери|${NET_SCORED_LOSS_PPM} ppm"
 echo "Общая учитываемая доля|${NET_BAD_PPM} ppm (${NET_BAD_PERCENT}%)"
 echo "Состояние|$NET_STATUS"
} | table

section "ДОПОЛНИТЕЛЬНЫЕ ПРОВЕРКИ"
{
 echo "Синхронизация времени|$TIME_SYNC"
 echo "Признаки аварийной прошлой загрузки|$UNCLEAN_BOOT_SIGNS"
 echo "Software RAID|$RAID_STATUS"
 echo "ECC / EDAC|$ECC_STATUS (CE=$ECC_CE; UE=$ECC_UE)"
 echo "Батарея|$BATTERY_STATUS; заряд $BATTERY_CAPACITY; здоровье $BATTERY_HEALTH"
 echo "Поддержка дистрибутива|$SUPPORT_TIER"
} | table

section "ОПЦИОНАЛЬНЫЕ СЕРВИСЫ"
{
 echo "SSSD|$SSSD_STATUS"
 if ((PRIVACY_MODE==1)) && [ "$SSSD_DOMAINS" != "-" ]; then echo "Домены SSSD|скрыто"; else echo "Домены SSSD|$SSSD_DOMAINS"; fi
 echo "Kerberos|$KRB_STATUS"
 echo "CUPS|$CUPS_STATUS; очередей $CUPS_QUEUES"
} | table

section "НАКОПИТЕЛИ"
echo "Системный накопитель: $SYSTEM_DISK_TEXT"
{ echo "Диск|Роль|Тип|Размер|Модель|Ресурс|SMART|°C|Часы"; if ((${#DISK_ROWS[@]})); then printf '%s\n' "${DISK_ROWS[@]}"; else echo "-|-|-|-|Не найдены|-|-|-|-"; fi; } | table
if ((${#DISK_SELFTEST_ROWS[@]}>0)); then echo; { echo "Диск|Последний SMART self-test"; printf '%s\n' "${DISK_SELFTEST_ROWS[@]}"; } | table; fi

section "ФАЙЛОВЫЕ СИСТЕМЫ"
{ echo "Корневой раздел|$ROOT_DEV"; echo "Размер / занято / свободно|$ROOT_SIZE / $ROOT_USED / $ROOT_FREE"; echo "Корень: место / inode|${ROOT_USE}% / ${ROOT_INODE_USE}%"; echo "Локальных ФС проверено|$LOCAL_FS_COUNT"; echo "Съёмных ФС вне индекса|$REMOVABLE_FS_COUNT"; echo "Макс. заполнение|${FS_WORST_USE}% на $FS_WORST_USE_MOUNT"; echo "Использование inode|${FS_WORST_INODE}% на $FS_WORST_INODE_MOUNT"; } | table
if ((${#LOCAL_FS_ROWS[@]}>1)); then echo; { echo "Точка|Место|Inode|Режим"; printf '%s\n' "${LOCAL_FS_ROWS[@]}"; } | table; fi

section "СВОДКА СОСТОЯНИЯ"
{ echo "Общее состояние|$STATE_DISPLAY"; echo "Индекс по доступным данным|$TOTAL_SCORE / 100"; echo "Полнота проверки|$CONFIDENCE%"; [ "$CONFIDENCE_NOTE" != - ]&&echo "Ограничения проверки|$CONFIDENCE_NOTE"; } | table
echo
STORAGE_SCORE_TEXT="$STORAGE_SCORE / 100"; ((STORAGE_KNOWN==0))&&STORAGE_SCORE_TEXT="Н/Д"
AGE_SCORE_TEXT="$AGE_SCORE / 100"; ((AGE_KNOWN==0))&&AGE_SCORE_TEXT="Н/Д"
{ echo "Показатель|Состояние|Вес в индексе"; echo "Накопители / износ|$STORAGE_SCORE_TEXT|40%"; echo "Файловая система|$FS_SCORE / 100|15%"; echo "Стабильность системы|$STAB_SCORE / 100|15%"; echo "Оперативная память|$MEM_SCORE / 100|10%"; echo "Процессор / температура|$CPU_SCORE / 100|10%"; echo "Возраст / наработка|$AGE_SCORE_TEXT|5%"; echo "Сеть|$NET_SCORE / 100|5%"; } | table

section "КЛЮЧЕВЫЕ ПОКАЗАТЕЛИ"
SMART_SUMMARY=OK; if ((FIXED_DISKS==0)); then SMART_SUMMARY="Н/Д"; elif ! command -v smartctl >/dev/null 2>&1; then SMART_SUMMARY="Н/Д (smartctl отсутствует)"; elif ((SYSTEM_DISK_COUNT>0 && SYSTEM_DISK_SCORE==0)); then SMART_SUMMARY=FAIL; elif ((SYSTEM_DISK_COUNT>0 && SYSTEM_SMART_UNKNOWN_COUNT>0)); then SMART_SUMMARY="Н/Д (системный)"; elif ((SYSTEM_DISK_COUNT==0 && SMART_UNKNOWN_COUNT>0)); then SMART_SUMMARY="Частично / Н/Д"; fi
((OOM_DETECTED==1))&&OOM_TEXT="ОБНАРУЖЕНО"||OOM_TEXT="Не обнаружено"
{ echo "SMART системного накопителя|$SMART_SUMMARY"; echo "Съёмных накопителей вне индекса|$REMOVABLE_DISKS"; echo "Файловые системы|макс. ${FS_WORST_USE}% на $FS_WORST_USE_MOUNT; inode ${FS_WORST_INODE}% на $FS_WORST_INODE_MOUNT"; echo "ОЗУ доступно|${MEM_AVAIL_PCT}%"; echo "Swap использовано|${SWAP_USED_PCT}%"; echo "Failed-служб|$FAILED_COUNT"; echo "Аппаратных/дисковых ошибок|$HW_ERR_COUNT"; if ((JOURNAL_AVAILABLE==1)); then echo "Уникальных journal error+|$JOURNAL_ERR_COUNT"; else echo "Journal текущей загрузки|Н/Д"; fi; echo "OOM за текущую загрузку|$OOM_TEXT"; echo "Синхронизация времени|$TIME_SYNC"; echo "Software RAID|$RAID_STATUS"; echo "ECC / EDAC|$ECC_STATUS"; [[ "$CPU_TEMP" =~ ^[0-9]+$ ]]&&echo "CPU температура|${CPU_TEMP}°C"; } | table

section "ЗАКЛЮЧЕНИЕ"
echo "$CONCLUSION"

section "РЕКОМЕНДАЦИИ"
if ((${#REC_TITLES[@]}==0)); then echo "Дополнительных действий не требуется."
else
 REC_NUM=0
 for LEVEL_WANTED in КРИТИЧНО ВНИМАНИЕ ПРОВЕРКА ПЛАНОВО; do
  for ((i=0;i<${#REC_TITLES[@]};i++)); do
   [ "${REC_LEVELS[$i]}" = "$LEVEL_WANTED" ]||continue
   REC_NUM=$((REC_NUM+1)); echo; print_wrapped "$REC_NUM. [${REC_LEVELS[$i]}]" "${REC_TITLES[$i]}"
   print_wrapped "Возможные причины:" "${REC_CAUSES[$i]}"
   print_wrapped "Влияние:" "${REC_IMPACTS[$i]}"
   print_wrapped "Что проверить:" "${REC_DIAGNOSTICS[$i]}"
   print_wrapped "Действие:" "${REC_ACTIONS[$i]}"
   if [ -n "${REC_CHECKS[$i]}" ]; then
       base_print_rec_commands "${REC_CHECKS[$i]}"
   fi
   print_wrapped "Контроль результата:" "${REC_VERIFICATIONS[$i]}"
  done
 done
fi

if ! command -v smartctl >/dev/null 2>&1; then echo; echo "Примечание: smartctl не установлен — оценка накопителей ограничена."; echo "Установка: dnf install smartmontools"; fi
[ "$(id -u)" -ne 0 ]&&{ echo; echo "Примечание: для полного SMART/dmidecode запускайте скрипт от root."; }

echo; line
echo "Индекс отражает текущее техническое состояние, износ накопителей, заполненность,"
echo "стабильность, ресурсную нагрузку и эксплуатационный ориентир. Вес — вклад показателя"
echo "в общий балл, а не процент износа. Индекс не прогнозирует срок службы."
if ((SAVE_REPORT==1)); then echo "Отчёт сохранён: $REPORT_FILE"; fi
else
    # JSON предназначен для автоматизации. В privacy-режиме сетевые идентификаторы обезличены.
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "arm_info_version": "%s",\n' "$(json_escape "$ARM_INFO_VERSION")"
    printf '  "generated_at": "%s",\n' "$(date --iso-8601=seconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
    printf '  "privacy": %s,\n' "$([ "$PRIVACY_MODE" -eq 1 ] && echo true || echo false)"
    printf '  "system": {"hostname":"%s","os":"%s","kernel":"%s","arch":"%s","install_date":"%s"},\n' \
        "$(json_escape "$HOST_DISPLAY")" "$(json_escape "$OS")" "$(json_escape "$KERNEL")" "$(json_escape "$ARCH")" "$(json_escape "$INSTALL_DATE")"
    printf '  "cpu": {"model":"%s","cores":"%s","threads":"%s","load1":%s,"temperature_c":%s,"score":%s},\n' \
        "$(json_escape "$CPU_MODEL")" "$(json_escape "$CORES")" "$(json_escape "$THREADS")" "${LOAD1:-0}" \
        "$([[ "$CPU_TEMP" =~ ^[0-9]+$ ]] && echo "$CPU_TEMP" || echo null)" "$CPU_SCORE"
    printf '  "memory": {"available_percent":%s,"swap_used_percent":%s,"oom_detected":%s,"score":%s},\n' \
        "$MEM_AVAIL_PCT" "$SWAP_USED_PCT" "$([ "$OOM_DETECTED" -eq 1 ] && echo true || echo false)" "$MEM_SCORE"
    printf '  "storage": {"score":%s,"known":%s,"system_disks":%s,"fixed_disks":%s,"secondary_fixed_disks":%s,"removable_disks":%s,"smart_unknown":%s,"system_smart_unknown":%s},\n' \
        "$STORAGE_SCORE" "$([ "$STORAGE_KNOWN" -eq 1 ] && echo true || echo false)" "$SYSTEM_DISK_COUNT" "$FIXED_DISKS" "$SECONDARY_FIXED_DISKS" "$REMOVABLE_DISKS" "$SMART_UNKNOWN_COUNT" "$SYSTEM_SMART_UNKNOWN_COUNT"
    printf '  "filesystem": {"root_use_percent":%s,"max_use_percent":%s,"max_use_mount":"%s","max_inode_percent":%s,"score":%s},\n' \
        "$ROOT_USE" "$FS_WORST_USE" "$(json_escape "$FS_WORST_USE_MOUNT")" "$FS_WORST_INODE" "$FS_SCORE"
    printf '  "network": {"active_interfaces":%s,"gateway":"%s","dns":"%s","rx_dropped":%s,"rx_missed":%s,"tx_dropped":%s,"error_ppm":%s,"rx_drop_ppm_raw":%s,"scored_loss_ppm":%s,"drop_ppm":%s,"score":%s},\n' \
        "$ACTIVE_NET" "$(json_escape "$GW_DISPLAY")" "$(json_escape "$DNS_DISPLAY")" "$RX_DROPS_TOTAL" "$RX_MISSED_TOTAL" "$TX_DROPS_TOTAL" "$NET_ERROR_PPM" "$NET_RX_DROP_PPM_RAW" "$NET_SCORED_LOSS_PPM" "$NET_DROP_PPM" "$NET_SCORE"
    printf '  "stability": {"failed_units":%s,"hardware_errors":%s,"journal_errors":%s,"oom_detected":%s,"time_sync":"%s","unclean_boot_signs":%s,"ecc_ce":%s,"ecc_ue":%s,"penalty_failed_units":%s,"penalty_hardware":%s,"penalty_journal":%s,"penalty_oom":%s,"penalty_time":%s,"penalty_unclean_boot":%s,"penalty_ecc_ce":%s,"ecc_ue_score_cap":%s,"score":%s},\n' \
        "$FAILED_COUNT" "$HW_ERR_COUNT" "$JOURNAL_ERR_COUNT" "$([ "$OOM_DETECTED" -eq 1 ] && echo true || echo false)" "$(json_escape "$TIME_SYNC")" "$UNCLEAN_BOOT_SIGNS" "$ECC_CE" "$ECC_UE" \
        "$STAB_PENALTY_FAILED" "$STAB_PENALTY_HW" "$STAB_PENALTY_JOURNAL" "$STAB_PENALTY_OOM" "$STAB_PENALTY_TIME" "$STAB_PENALTY_UNCLEAN" "$STAB_PENALTY_ECC_CE" "$STAB_ECC_UE_CAP" "$STAB_SCORE"
    printf '  "diagnostics": {"time_sync":"%s","unclean_boot_signs":%s,"raid":"%s","ecc":"%s","battery_health":"%s","sssd":"%s","kerberos":"%s","cups":"%s","support_tier":"%s"},\n' \
        "$(json_escape "$TIME_SYNC")" "$UNCLEAN_BOOT_SIGNS" "$(json_escape "$RAID_STATUS")" "$(json_escape "$ECC_STATUS")" "$(json_escape "$BATTERY_HEALTH")" \
        "$(json_escape "$SSSD_STATUS")" "$(json_escape "$KRB_STATUS")" "$(json_escape "$CUPS_STATUS")" "$(json_escape "$SUPPORT_TIER")"
    printf '  "summary": {"state":"%s","score":%s,"confidence":%s,"conclusion":"%s"},\n' \
        "$(json_escape "$STATE_DISPLAY")" "$TOTAL_SCORE" "$CONFIDENCE" "$(json_escape "$CONCLUSION")"
    printf '  "recommendations": ['
    _first=1
    for ((i=0;i<${#REC_TITLES[@]};i++)); do
        ((_first==0)) && printf ','
        printf '\n    {"level":"%s","title":"%s","possible_causes":"%s","impact":"%s","checks":"%s","action":"%s","command":"%s","verification":"%s"}' \
            "$(json_escape "${REC_LEVELS[$i]}")" "$(json_escape "${REC_TITLES[$i]}")" "$(json_escape "${REC_CAUSES[$i]}")" \
            "$(json_escape "${REC_IMPACTS[$i]}")" "$(json_escape "${REC_DIAGNOSTICS[$i]}")" "$(json_escape "${REC_ACTIONS[$i]}")" \
            "$(json_escape "${REC_CHECKS[$i]}")" "$(json_escape "${REC_VERIFICATIONS[$i]}")"
        _first=0
    done
    ((_first==0)) && printf '\n  '
    printf ']\n}\n'
fi

if ((SAVE_REPORT==1)); then
    chmod 0644 "$REPORT_FILE" 2>/dev/null || true
    if [[ "${SUDO_UID:-}" =~ ^[0-9]+$ ]]&&[[ "${SUDO_GID:-}" =~ ^[0-9]+$ ]]; then chown "$SUDO_UID:$SUDO_GID" "$REPORT_FILE" 2>/dev/null || true; fi
fi

# Коды завершения: критика > предупреждения > неполнота > норма.
if [[ "$STATE" = "КРИТИЧЕСКОЕ" ]]; then EXIT_CODE=2
elif ((TOTAL_SCORE<80)) || [[ "$STATE" = "ТРЕБУЕТ ВНИМАНИЯ" || "$STATE" = "ПЛОХОЕ" ]]; then EXIT_CODE=1
elif ((CONFIDENCE<80)); then EXIT_CODE=3
else EXIT_CODE=0
fi
exit "$EXIT_CODE"
)
