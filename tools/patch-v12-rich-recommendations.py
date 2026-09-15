from pathlib import Path

root = Path('.')
p = root / 'arm_info-enterprise.sh'
s = p.read_text(encoding='utf-8')

anchor = '''add_check() {
    local section=$1 key=$2 label=$3 value=$4 severity=${5:-ok} detail=${6:-}
    KEYS+=("$key"); LABELS+=("$label"); VALUES+=("$value"); SEVERITIES+=("$severity"); SECTIONS+=("$section"); DETAILS+=("$detail")
    case "$severity" in warn) WARN_COUNT=$((WARN_COUNT+1));; crit) CRIT_COUNT=$((CRIT_COUNT+1));; unknown) UNKNOWN_COUNT=$((UNKNOWN_COUNT+1));; esac
}
'''

rich = r'''

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
    REC_COMMAND="journalctl -b -p warning..alert --no-pager | tail -100|arm_info --profile $PROFILE"
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
            REC_COMMAND="adcli testjoin|timedatectl|dig +short _kerberos._tcp.<DOMAIN> SRV|dig +short _ldap._tcp.<DOMAIN> SRV|journalctl -u sssd -b --no-pager | tail -150"
            ;;
        kerberos.ticket)
            REC_CAUSE="Действующий Kerberos ticket не найден либо klist недоступен. При запуске от root билет интерактивного пользователя может находиться в другом credential cache."
            REC_IMPACT="SSO к доменным ресурсам, CIFS, LDAP и приложениям с GSSAPI может запрашивать пароль или завершаться ошибкой."
            REC_CHECK="Проверить все доступные cache, срок действия TGT, principal и время на АРМ."
            REC_ACTION="Для нужного пользователя получить/обновить билет штатным способом; не удалять cache до фиксации причины."
            REC_COMMAND="klist -A|find /tmp -maxdepth 1 -type f -name 'krb5cc_*' -ls 2>/dev/null|timedatectl"
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
            REC_COMMAND="cat /etc/resolv.conf|resolvectl status|nmcli -f GENERAL.CONNECTION,IP4.DNS,IP4.DOMAIN device show|ip route"
            ;;
        dns.search)
            REC_CAUSE="DNS search/domain suffix не определён."
            REC_IMPACT="Короткие доменные имена и автоматический поиск доменных сервисов могут разрешаться не так, как ожидается."
            REC_CHECK="Проверить search/domain в resolv.conf и параметры активного сетевого соединения."
            REC_ACTION="Настроить корректный DNS search domain через штатную сетевую конфигурацию организации."
            REC_COMMAND="grep -E '^(search|domain|nameserver)' /etc/resolv.conf|nmcli -f NAME,IP4.DOMAIN,IP4.DNS connection show --active"
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
            REC_COMMAND="dig +short _kerberos._tcp.<DOMAIN> SRV|dig +short _ldap._tcp.<DOMAIN> SRV|host -t SRV _kerberos._tcp.<DOMAIN>|host -t SRV _ldap._tcp.<DOMAIN>"
            ;;
        domain.dc.ports)
            REC_CAUSE="Не все найденные KDC/LDAP endpoints доступны по проверяемым TCP-портам. Возможны маршрут, firewall, DNS или недоступный DC."
            REC_IMPACT="Аутентификация и LDAP-запросы могут зависеть от случайно выбранного DC и работать непредсказуемо."
            REC_CHECK="Определить все SRV targets, проверить разрешение их имён, маршрут и TCP 88/389 по каждому узлу."
            REC_ACTION="Восстановить сетевую доступность либо вывести неисправный DC из клиентского DNS discovery на стороне инфраструктуры."
            REC_COMMAND="dig +short _kerberos._tcp.<DOMAIN> SRV|dig +short _ldap._tcp.<DOMAIN> SRV|nc -vz <DC> 88|nc -vz <DC> 389|ip route get <DC_IP>"
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
            REC_CHECK="Проверить EAP-метод, CA/client certificate, срок действия и ошибки NetworkManager/supplicant."
            REC_ACTION="Заранее обновить истекающий сертификат или исправить профиль 802.1X согласно политике организации."
            REC_COMMAND="nmcli -f NAME,TYPE,802-1x.eap,802-1x.ca-cert,802-1x.client-cert connection show|openssl x509 -in <CERT> -noout -subject -issuer -dates|journalctl -u NetworkManager -b --no-pager | grep -Ei '802.1x|eap|supplicant|certificate' | tail -120"
            ;;
        network.cifs)
            REC_CAUSE="Один или несколько CIFS mount не отвечают в короткий timeout. Возможны недоступная шара, сеть, Kerberos/учётные данные или зависший mount."
            REC_IMPACT="Caja/приложения могут зависать при открытии, сохранении, удалении и обходе каталогов."
            REC_CHECK="Определить конкретные mount points, проверить stat с timeout, kernel CIFS messages и Kerberos ticket."
            REC_ACTION="Устранить сетевую/аутентификационную причину; зависший mount размонтировать только после проверки открытых файлов и процессов."
            REC_COMMAND="findmnt -t cifs -o TARGET,SOURCE,OPTIONS|timeout 5 stat -f <MOUNT>|journalctl -k -b --no-pager | grep -Ei 'cifs|smb' | tail -120|klist -A"
            ;;
        network.gvfs)
            REC_CAUSE="Один или несколько GVFS mount не отвечают. Возможны недоступный SMB-ресурс или зависшие пользовательские gvfs-процессы."
            REC_IMPACT="Файловый менеджер может долго открывать сетевые папки, зависать при удалении/копировании и удерживать старые подключения."
            REC_CHECK="Проверить gio mounts, процессы gvfs/caja и доступность конкретного каталога с timeout."
            REC_ACTION="После фиксации диагностики перезапустить только проблемные пользовательские gvfs/caja процессы либо переподключить ресурс."
            REC_COMMAND="gio mount -l|ps -ef | grep -E 'caja|gvfsd' | grep -v grep|find /run/user/*/gvfs -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null"
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
            REC_COMMAND="lpstat -p -d -v|lpstat -W not-completed -o|journalctl -u cups -b --no-pager | tail -150|cupsenable <QUEUE>   # после устранения причины|cupsaccept <QUEUE>  # если очередь не принимает задания"
            ;;
        print.jobs)
            REC_CAUSE="В очередях накопилось много незавершённых заданий. Возможны остановленная очередь, недоступный backend или проблемное задание."
            REC_IMPACT="Новые задания задерживаются; spool может расти."
            REC_CHECK="Определить очередь и самое старое/проблемное задание, затем проверить состояние принтера и backend."
            REC_ACTION="Устранить причину очереди. Удалять задания только осознанно после согласования, чтобы не потерять пользовательскую печать."
            REC_COMMAND="lpstat -W not-completed -o|lpstat -p -v|du -sh /var/spool/cups 2>/dev/null|cancel <JOB_ID>  # только при подтверждённой необходимости"
            ;;
        print.lpstat)
            REC_CAUSE="Утилита lpstat отсутствует, поэтому состояние очередей CUPS не проверено."
            REC_IMPACT="Диагностика печати неполная; это не означает неисправность CUPS."
            REC_CHECK="Проверить наличие cups-client/пакета, предоставляющего lpstat."
            REC_ACTION="Установить штатный клиент CUPS из разрешённого репозитория, если диагностика печати нужна на этом АРМ."
            REC_COMMAND="command -v lpstat|rpm -qf \"$(command -v lpstat 2>/dev/null)\" 2>/dev/null|dnf provides '*/lpstat'"
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
            REC_COMMAND="command -v rpm|rpm --version|dnf --version"
            ;;
        software.zombies)
            REC_CAUSE="Обнаружены zombie-процессы. Zombie уже завершён; запись остаётся, пока родительский процесс не заберёт exit status."
            REC_IMPACT="Единичный zombie обычно не критичен, но постоянный рост указывает на проблему родительского процесса/приложения."
            REC_CHECK="Определить PID/PPID zombie, затем исследовать состояние и журнал родителя."
            REC_ACTION="Не пытаться kill zombie напрямую. Исправлять/перезапускать родительский процесс только после определения влияния на пользователя."
            REC_COMMAND="ps -eo pid,ppid,stat,lstart,comm,args | awk '$3 ~ /^Z/'|ps -fp <PPID>|journalctl _PID=<PPID> -b --no-pager | tail -100"
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

print_rec_field() {
    local label=$1 text=$2
    printf '   %-18s %s\n' "$label" "$text"
}

print_rec_commands() {
    local text=$1 cmd first=1
    while IFS='|' read -r cmd; do
        [[ -n $cmd ]] || continue
        if ((first)); then printf '   %-18s %s\n' 'Команды:' "$cmd"; first=0
        else printf '   %-18s %s\n' '' "$cmd"; fi
    done <<<"${text//|/$'\n'}"
}
'''

if 'build_recommendations()' not in s:
    if anchor not in s:
        raise SystemExit('add_check anchor not found')
    s = s.replace(anchor, anchor + rich, 1)

old_emit = '''emit_text() {
    local current="" i sevmark
    printf 'ARM_INFO ENTERPRISE %s\\n' "$VERSION"
    printf 'Профиль: %s\\n' "$PROFILE"
    printf 'Дата: %s\\n' "$(date '+%d.%m.%Y %H:%M:%S')"
    ((PRIVACY)) && printf 'Privacy: включён\\n'
    for i in "${!KEYS[@]}"; do
        if [[ ${SECTIONS[i]} != "$current" ]]; then current=${SECTIONS[i]}; printf '\\n%s\\n' "$current"; printf '%*s\\n' 92 '' | tr ' ' '-'; fi
        case "${SEVERITIES[i]}" in ok) sevmark='OK';; info) sevmark='INFO';; warn) sevmark='WARN';; crit) sevmark='CRIT';; *) sevmark='N/A';; esac
        printf '%-31s %-7s %s\\n' "${LABELS[i]}" "[$sevmark]" "${VALUES[i]}"
        [[ -n ${DETAILS[i]} ]] && printf '  %-29s %s\\n' 'Примечание:' "${DETAILS[i]}"
    done
    printf '\\nСВОДКА\\n'; printf '%*s\\n' 92 '' | tr ' ' '-'
    printf '%-31s %s\\n' 'Критично' "$CRIT_COUNT"
    printf '%-31s %s\\n' 'Предупреждения' "$WARN_COUNT"
    printf '%-31s %s\\n' 'Неполные проверки' "$UNKNOWN_COUNT"
}
'''
new_emit = r'''emit_text() {
    local current="" i sevmark n=0
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

    printf '\nРЕКОМЕНДАЦИИ\n'; printf '%*s\n' 92 '' | tr ' ' '-'
    if ((${#REC_KEYS[@]}==0)); then
        printf 'Дополнительных действий по выбранному профилю не требуется.\n'
    else
        for i in "${!REC_KEYS[@]}"; do
            n=$((n+1))
            printf '\n%d. [%s] %s\n' "$n" "${REC_LEVELS[i]}" "${REC_TITLES[i]}"
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
'''
if old_emit not in s:
    raise SystemExit('emit_text block not found')
s = s.replace(old_emit, new_emit, 1)

old_json_tail = '''    printf '\\n  ]\\n}\\n'
}
'''
new_json_tail = r'''    printf '\n  ],\n'
    printf '  "recommendations": [\n'
    comma=""
    for i in "${!REC_KEYS[@]}"; do
        printf '%s    {"key":"%s","level":"%s","title":"%s","source":"%s","possible_causes":"%s","impact":"%s","checks":"%s","action":"%s","commands":[' \
          "$comma" "$(json_escape "${REC_KEYS[i]}")" "$(json_escape "${REC_LEVELS[i]}")" "$(json_escape "${REC_TITLES[i]}")" "$(json_escape "${REC_SOURCES[i]}")" \
          "$(json_escape "${REC_CAUSES[i]}")" "$(json_escape "${REC_IMPACTS[i]}")" "$(json_escape "${REC_CHECKS[i]}")" "$(json_escape "${REC_ACTIONS[i]}")"
        local cmd ccomma=""
        while IFS='|' read -r cmd; do
            [[ -n $cmd ]] || continue
            printf '%s"%s"' "$ccomma" "$(json_escape "$cmd")"
            ccomma=','
        done <<<"${REC_COMMANDS[i]//|/$'\n'}"
        printf '],"verification":"%s"}' "$(json_escape "${REC_VERIFIES[i]}")"
        comma=$',\n'
    done
    printf '\n  ]\n}\n'
}
'''
if old_json_tail not in s:
    raise SystemExit('emit_json tail not found')
s = s.replace(old_json_tail, new_json_tail, 1)

call_anchor = '''case "$PROFILE" in
    domain) check_domain ;;
    network) check_network ;;
    print) check_print ;;
    software) check_software ;;
    enterprise) check_domain; check_network; check_print ;;
esac

if ((JSON_MODE)); then emit_json; else emit_text; fi
'''
call_new = '''case "$PROFILE" in
    domain) check_domain ;;
    network) check_network ;;
    print) check_print ;;
    software) check_software ;;
    enterprise) check_domain; check_network; check_print ;;
esac

build_recommendations
if ((JSON_MODE)); then emit_json; else emit_text; fi
'''
if call_anchor not in s:
    raise SystemExit('profile dispatch anchor not found')
s = s.replace(call_anchor, call_new, 1)
p.write_text(s, encoding='utf-8')

# Tests: recommendation schema/content and global inventory policy.
p = root / 'tests/test_enterprise.sh'
t = p.read_text(encoding='utf-8')
t = t.replace("assert isinstance(d['checks'], list) and d['checks']\n", "assert isinstance(d['checks'], list) and d['checks']\nassert isinstance(d.get('recommendations'), list)\nfor r in d['recommendations']:\n    for k in ('key','level','title','source','possible_causes','impact','checks','action','commands','verification'):\n        assert k in r, (k,r)\n    assert isinstance(r['commands'], list)\n", 1)
if 'recommendations structure' not in t:
    t += '''\n# Recommendations must be present in text output when diagnostics are incomplete/warn/crit.\nTXT=$(mktemp)\ntrap 'rm -f "$TMP1" "$TMP2" "$DIFF" "$TXT"' EXIT\nset +e\nbash "$SCRIPT" --profile domain --privacy >"$TXT"\nRC=$?\nset -e\n((RC>=0 && RC<=3)) || die "domain text exit code $RC"\ngrep -q '^РЕКОМЕНДАЦИИ$' "$TXT" || die "recommendations structure"\ngrep -Eq 'Возможные причины:|Дополнительных действий' "$TXT" || die "recommendations detail"\n'''
p.write_text(t, encoding='utf-8')

# Documentation.
p = root / 'docs/ENTERPRISE_PROFILES.md'
d = p.read_text(encoding='utf-8')
marker = '## Privacy\n'
section = '''## Рекомендации\n\nДля каждого `WARN`, `CRIT` и `N/A` профиль формирует расширенную рекомендацию. Она содержит: исходную проверку и значение, возможные причины, влияние на АРМ, что проверить, безопасный порядок действий, набор диагностических/восстановительных команд и критерий контроля результата.\n\nКоманды с изменением состояния (например, возобновление CUPS-очереди или отмена задания) помечаются контекстом и должны выполняться только после подтверждения первичной причины. В privacy-режиме в рекомендациях используются placeholders `<DOMAIN>`, `<DC>`, `<MOUNT>`, `<QUEUE>` вместо инфраструктурных значений.\n\nРекомендации также присутствуют в JSON как массив `recommendations[]`, поэтому их можно использовать в helpdesk/автоматизации без разбора текстового отчёта.\n\n'''
if '## Рекомендации' not in d:
    if marker not in d:
        raise SystemExit('enterprise docs marker not found')
    d = d.replace(marker, section + marker, 1)
p.write_text(d, encoding='utf-8')

p = root / 'README.md'
r = p.read_text(encoding='utf-8')
old = '`arm_info 1.2.0` добавляет отдельные профили для типовых проблем корпоративных АРМ РЕД ОС. Они **не смешиваются с аппаратным health score** и выводят самостоятельные статусы `OK/WARN/CRIT/N/A`.\n'
new = old + '\nДля `WARN/CRIT/N/A` формируется максимально подробный блок рекомендаций: возможные причины → влияние → что проверить → действие → команды → контроль результата. В JSON те же данные доступны в `recommendations[]`.\n'
if 'максимально подробный блок рекомендаций' not in r:
    if old not in r:
        raise SystemExit('README enterprise intro not found')
    r = r.replace(old, new, 1)
p.write_text(r, encoding='utf-8')

p = root / 'CHANGELOG.md'
c = p.read_text(encoding='utf-8')
line = '- Enterprise-профили формируют расширенные рекомендации с причинами, влиянием, проверками, действиями, командами и контролем результата; JSON содержит `recommendations[]`.\n'
if line not in c:
    pos = c.find('## 1.2.0')
    if pos < 0:
        raise SystemExit('CHANGELOG 1.2.0 not found')
    addpos = c.find('\n', c.find('### Changed', pos)) + 1
    c = c[:addpos] + line + c[addpos:]
p.write_text(c, encoding='utf-8')

# Permanent pre-release checks in CI (no release/tag is created).
p = root / '.github/workflows/ci.yml'
ci = p.read_text(encoding='utf-8')
if 'release-readiness:' not in ci:
    ci += r'''

  release-readiness:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Version consistency
        run: |
          V=$(tr -d '[:space:]' < VERSION)
          test "$V" = "$(sed -n 's/^ARM_INFO_VERSION="\([^"]*\)"/\1/p' arm_info.sh | head -1)"
          test "$V" = "$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' arm_info-enterprise.sh | head -1)"
          test "$V" = "$(awk '/^Version:/{print $2; exit}' packaging/arm_info.spec)"
          grep -q "Текущая версия: \*\*$V\*\*" README.md
      - name: Installer smoke test
        run: |
          D=$(mktemp -d)
          bash install.sh --destdir "$D"
          test -x "$D/usr/local/sbin/arm_info"
          test -x "$D/usr/local/libexec/arm_info/arm_info-enterprise.sh"
          "$D/usr/local/sbin/arm_info" --version
          "$D/usr/local/sbin/arm_info" --profile domain --help >/dev/null
          bash install.sh --destdir "$D" --uninstall
          test ! -e "$D/usr/local/sbin/arm_info"
          test ! -e "$D/usr/local/libexec/arm_info/arm_info-enterprise.sh"
      - name: Public repository policy checks
        run: |
          ! grep -Eiq '(r7|remmina|freerdp|icaclient|citrix|basis|workplace|bsscrypto|cryptopro|cprocsp|jacarta|snx)' arm_info-enterprise.sh
          ! grep -Eq 'Kerberos 6/7/15|c6=|c7=|c15=' arm_info-enterprise.sh
          ! grep -RIE '(password|passwd|token|secret)[[:space:]]*=[[:space:]]*[^${<[:space:]]+' --exclude='*.md' --exclude-dir='.git' . || true
      - name: RPM build smoke test
        run: |
          docker run --rm -v "$PWD:/src:ro" fedora:latest bash -lc '
            dnf -q -y install rpm-build coreutils >/dev/null &&
            cd /src &&
            RPM_TOPDIR=/tmp/rpmbuild bash packaging/build-rpm.sh &&
            RPM=$(find /tmp/rpmbuild/RPMS -type f -name "arm-info-*.rpm" | head -1) &&
            test -n "$RPM" &&
            rpm -qpl "$RPM" | grep -q "/usr/sbin/arm_info" &&
            rpm -qpl "$RPM" | grep -q "arm_info-enterprise.sh"
          '
'''
p.write_text(ci, encoding='utf-8')
