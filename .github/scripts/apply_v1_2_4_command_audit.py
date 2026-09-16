from pathlib import Path
import re

ROOT = Path('.')
ARM = ROOT / 'arm_info.sh'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, got {count}')
    return text.replace(old, new, 1)


s = ARM.read_text(encoding='utf-8')
s = s.replace('1.2.3', '1.2.4')

# A stable self-invocation command makes repeat-diagnostics recommendations work
# both for an installed command and for the usual /tmp/arm_info.sh workflow.
needle = 'ARM_INFO_VERSION="1.2.4"\n\n'
insert = '''ARM_INFO_VERSION="1.2.4"\n\nARM_INFO_SELF_SOURCE=${BASH_SOURCE[0]:-$0}\nif [[ -f $ARM_INFO_SELF_SOURCE ]]; then\n    ARM_INFO_SELF_PATH=$(readlink -f -- "$ARM_INFO_SELF_SOURCE" 2>/dev/null || printf '%s' "$ARM_INFO_SELF_SOURCE")\n    printf -v ARM_INFO_SELF_Q '%q' "$ARM_INFO_SELF_PATH"\n    ARM_INFO_SELF_CMD="bash $ARM_INFO_SELF_Q"\nelse\n    ARM_INFO_SELF_CMD="arm_info"\nfi\n\n'''
s = replace_once(s, needle, insert, 'self command')

# Enterprise recommendation commands: remove commands that are guaranteed to fail,
# avoid invalid nmcli field combinations, add timeouts, and make user-context checks explicit.
replacements = {
    'REC_COMMAND="journalctl -b -p warning..alert --no-pager | tail -100|arm_info --profile $PROFILE"':
        'REC_COMMAND="journalctl -b -p warning..alert --no-pager | tail -100|$ARM_INFO_SELF_CMD --profile $PROFILE"',
    'REC_COMMAND="adcli testjoin|timedatectl|dig +short _kerberos._tcp.<DOMAIN> SRV|dig +short _ldap._tcp.<DOMAIN> SRV|journalctl -u sssd -b --no-pager | tail -150"':
        'REC_COMMAND="adcli testjoin --verbose|timedatectl|dig +short _kerberos._tcp.DOMAIN_FQDN SRV|dig +short _ldap._tcp.DOMAIN_FQDN SRV|journalctl -u sssd -b --no-pager | tail -150"',
    'REC_COMMAND="klist -A|find /tmp -maxdepth 1 -type f -name \'krb5cc_*\' -ls 2>/dev/null|timedatectl"':
        'REC_COMMAND="klist -l|klist -A|sudo -u \'USER_NAME\' klist -A|timedatectl"',
    'REC_COMMAND="cat /etc/resolv.conf|resolvectl status|nmcli -f GENERAL.CONNECTION,IP4.DNS,IP4.DOMAIN device show|ip route"':
        'REC_COMMAND="cat /etc/resolv.conf|resolvectl status|systemd-resolve --status|nmcli -f GENERAL.CONNECTION,IP4.DNS,IP4.DOMAIN device show|ip -4 route"',
    'REC_COMMAND="grep -E \'^(search|domain|nameserver)\' /etc/resolv.conf|nmcli -f NAME,IP4.DOMAIN,IP4.DNS connection show --active"':
        'REC_COMMAND="grep -E \'^(search|domain|nameserver)\' /etc/resolv.conf|nmcli -f GENERAL.CONNECTION,IP4.DNS,IP4.DOMAIN device show"',
    'REC_COMMAND="dig +short _kerberos._tcp.<DOMAIN> SRV|dig +short _ldap._tcp.<DOMAIN> SRV|host -t SRV _kerberos._tcp.<DOMAIN>|host -t SRV _ldap._tcp.<DOMAIN>"':
        'REC_COMMAND="dig +short _kerberos._tcp.DOMAIN_FQDN SRV|dig +short _ldap._tcp.DOMAIN_FQDN SRV|host -t SRV _kerberos._tcp.DOMAIN_FQDN|host -t SRV _ldap._tcp.DOMAIN_FQDN"',
    'REC_COMMAND="dig +short _kerberos._tcp.<DOMAIN> SRV|dig +short _ldap._tcp.<DOMAIN> SRV|nc -vz <DC> 88|nc -vz <DC> 389|ip route get <DC_IP>"':
        'REC_COMMAND="dig +short _kerberos._tcp.DOMAIN_FQDN SRV|dig +short _ldap._tcp.DOMAIN_FQDN SRV|timeout 5 nc -vz DC_FQDN 88|timeout 5 nc -vz DC_FQDN 389|ip route get DC_IP"',
    'REC_COMMAND="nmcli -f NAME,TYPE,802-1x.eap,802-1x.ca-cert,802-1x.client-cert connection show|openssl x509 -in \\\"<CERT>\\\" -noout -dates|openssl x509 -in \\\"<CERT>\\\" -noout -subject -issuer|journalctl -u NetworkManager -b --no-pager | grep -Ei \'802.1x|eap|supplicant|certificate\' | tail -120"':
        'REC_COMMAND="nmcli -f NAME,UUID,TYPE connection show|nmcli connection show \'PROFILE_NAME\' | grep -E \'^802-1x\\.(eap|identity|ca-cert|client-cert|phase2-ca-cert|phase2-client-cert|private-key|system-ca-certs):\'|openssl x509 -in \\\"CERT_PATH\\\" -noout -subject -issuer -dates|journalctl -u NetworkManager -b --no-pager | grep -Ei \'802.1x|eap|supplicant|certificate\' | tail -120"',
    'REC_COMMAND="findmnt -t cifs -o TARGET,SOURCE,OPTIONS|timeout 5 stat -f <MOUNT>|journalctl -k -b --no-pager | grep -Ei \'cifs|smb\' | tail -120|klist -A"':
        'REC_COMMAND="findmnt -t cifs -o TARGET,SOURCE,OPTIONS|timeout 5 stat -f \'MOUNT_PATH\'|journalctl -k -b --no-pager | grep -Ei \'cifs|smb\' | tail -120|sudo -u \'USER_NAME\' klist -A"',
    'REC_COMMAND="gio mount -l|ps -ef | grep -E \'caja|gvfsd\' | grep -v grep|find /run/user/*/gvfs -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null"':
        'REC_COMMAND="loginctl list-sessions --no-legend|ps -ef | grep -E \'caja|gvfsd\' | grep -v grep|find /run/user/*/gvfs -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null"',
    'REC_COMMAND="lpstat -p -d -v|lpstat -W not-completed -o|journalctl -u cups -b --no-pager | tail -150|cupsenable <QUEUE>   # после устранения причины|cupsaccept <QUEUE>  # если очередь не принимает задания"':
        'REC_COMMAND="lpstat -a -p -d -v|lpstat -W not-completed -o|journalctl -u cups -b --no-pager | tail -150|cupsenable QUEUE_NAME|cupsaccept QUEUE_NAME"',
    'REC_COMMAND="lpstat -W not-completed -o|lpstat -p -v|du -sh /var/spool/cups 2>/dev/null|cancel <JOB_ID>  # только при подтверждённой необходимости"':
        'REC_COMMAND="lpstat -W not-completed -o|lpstat -p -v|du -sh /var/spool/cups 2>/dev/null|cancel JOB_ID"',
    'REC_COMMAND="command -v lpstat|rpm -qf \\\"$(command -v lpstat 2>/dev/null)\\\" 2>/dev/null|dnf provides \'*/lpstat\'"':
        'REC_COMMAND="command -v lpstat|rpm -q cups-client|dnf provides \'/usr/bin/lpstat\'"',
    'REC_COMMAND="command -v rpm|rpm --version|dnf --version"':
        'REC_COMMAND="command -v rpm|command -v dnf|dnf provides \'/usr/bin/rpm\'"',
    'REC_COMMAND="ps -eo pid,ppid,stat,lstart,comm,args | awk \'$3 ~ /^Z/\'|ps -fp <PPID>|journalctl _PID=<PPID> -b --no-pager | tail -100"':
        'REC_COMMAND="ps -eo pid,ppid,stat,lstart,comm,args | awk \'$3 ~ /^Z/\'|ps -fp PARENT_PID|journalctl _PID=PARENT_PID -b --no-pager | tail -100"',
}
for old, new in replacements.items():
    if old not in s:
        raise SystemExit(f'enterprise replacement not found: {old[:90]}')
    s = s.replace(old, new, 1)

# Command descriptions are deliberately explicit: what the command returns, whether
# it changes state, and whether a placeholder must be substituted before execution.
new_command_description = r'''command_description() {
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

    if [[ $cmd =~ (DOMAIN_FQDN|DC_FQDN|DC_IP|USER_NAME|PROFILE_NAME|CERT_PATH|MOUNT_PATH|QUEUE_NAME|JOB_ID|PARENT_PID|UNIT_NAME|DEVICE_PATH|MD_DEVICE|IFACE_NAME) ]]; then
        desc="$desc Перед выполнением замените служебный маркер на фактическое значение из отчёта/системы."
    fi
    case "$cmd" in
        cupsenable*|cupsaccept*|cancel*|dnf\ install*) desc="ИЗМЕНЯЕТ СОСТОЯНИЕ: $desc" ;;
    esac
    printf '%s' "$desc"
}'''
pattern = r'command_description\(\) \{\n.*?\n\}\n\nsplit_rec_commands\(\) \{'
new_s, n = re.subn(pattern, new_command_description + '\n\nsplit_rec_commands() {', s, count=1, flags=re.S)
if n != 1:
    raise SystemExit(f'command_description replacement count={n}')
s = new_s

# Base recommendations: split semicolon-separated independent commands and describe
# every command individually. Pipelines remain one command and therefore copy safely.
new_base_description = r'''base_command_description() {
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
                [[ -n $current ]] && printf '%s\n' "$current"
                current=""
                ;;
            *) current+=$ch ;;
        esac
    done
    current=$(printf '%s' "$current" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -n $current ]] && printf '%s\n' "$current"
}

base_print_rec_commands() {
    local text=$1 cmd desc idx=0
    while IFS= read -r cmd; do
        [[ -n $cmd ]] || continue
        idx=$((idx+1))
        desc=$(base_command_description "$cmd")
        base_print_command_line "Команда $idx:" "$cmd" "$desc"
    done < <(base_split_commands "$text")
}'''
pattern = r'base_command_description\(\) \{\n.*?\n\}\n\n'
new_s, n = re.subn(pattern, new_base_description + '\n\n', s, count=1, flags=re.S)
if n != 1:
    raise SystemExit(f'base_command_description replacement count={n}')
s = new_s

old_render = '''   if [ -n "${REC_CHECKS[$i]}" ]; then
       _rec_cmd_desc=$(base_command_description "${REC_CHECKS[$i]}")
       base_print_command_line "Команда 1:" "${REC_CHECKS[$i]}" "$_rec_cmd_desc"
   fi'''
new_render = '''   if [ -n "${REC_CHECKS[$i]}" ]; then
       base_print_rec_commands "${REC_CHECKS[$i]}"
   fi'''
s = replace_once(s, old_render, new_render, 'base command renderer')

# Quote dynamic mount paths before embedding them into copyable commands.
rec_marker = '# -------------------- РЕКОМЕНДАЦИИ --------------------\n'
quote_block = '''# -------------------- РЕКОМЕНДАЦИИ --------------------
printf -v FS_WORST_USE_Q '%q' "$FS_WORST_USE_MOUNT"
printf -v FS_WORST_INODE_Q '%q' "$FS_WORST_INODE_MOUNT"
'''
s = replace_once(s, rec_marker, quote_block, 'mount command quoting')

base_replacements = {
    '"du -xhd1 \'$FS_WORST_USE_MOUNT\' 2>/dev/null | sort -h"': '"du -xhd1 $FS_WORST_USE_Q 2>/dev/null | sort -h | tail -20"',
    '"df -h \'$FS_WORST_USE_MOUNT\'"': '"df -h $FS_WORST_USE_Q"',
    '"df -i \'$FS_WORST_INODE_MOUNT\'"': '"df -i $FS_WORST_INODE_Q; du --inodes -x -d1 $FS_WORST_INODE_Q 2>/dev/null | sort -n | tail -20"',
    '"journalctl -k -b -p warning..alert"': '"findmnt -no SOURCE,FSTYPE,OPTIONS /; journalctl -k -b -p warning..alert --no-pager"',
    '"ps aux --sort=-%mem | head -15"': '"free -h; ps -eo pid,ppid,user,stat,%mem,%cpu,comm --sort=-%mem | head -20; vmstat 1 5"',
    '"systemctl --failed"': '"systemctl --failed; systemctl status UNIT_NAME --no-pager -l; journalctl -u UNIT_NAME -b --no-pager | tail -120"',
    '"journalctl -k -b -p warning..alert --no-pager"': '"journalctl -k -b -p warning..alert --no-pager; smartctl -a DEVICE_PATH"',
    '"top"': '"top -b -n1 | head -30"',
    '"Повторять диагностику планово"': '"$ARM_INFO_SELF_CMD --no-save"',
    '"ip -br a"': '"ip -br addr; nmcli device status"',
    '"ip route"': '"ip -4 route"',
    '"nmcli dev show 2>/dev/null | grep -i DNS"': '"cat /etc/resolv.conf; nmcli -f GENERAL.CONNECTION,IP4.DNS,IP4.DOMAIN device show; resolvectl status 2>/dev/null"',
    '"ip -s link"': '"ip -s link; ethtool IFACE_NAME 2>/dev/null"',
    '"timedatectl; chronyc tracking 2>/dev/null"': '"timedatectl; chronyc tracking 2>/dev/null; chronyc sources -v 2>/dev/null"',
    '"journalctl -b -1 -p warning..alert"': '"journalctl --list-boots; journalctl -b -1 -p warning..alert --no-pager"',
    '"cat /proc/mdstat; mdadm --detail /dev/md0 2>/dev/null"': '"cat /proc/mdstat; mdadm --detail MD_DEVICE"',
    '"upower -i $(upower -e 2>/dev/null | grep BAT | head -1) 2>/dev/null"': '"grep -H . /sys/class/power_supply/BAT*/{capacity,energy_full,energy_full_design,charge_full,charge_full_design,cycle_count} 2>/dev/null"',
    '"systemctl status sssd --no-pager; journalctl -u sssd -b"': '"systemctl status sssd --no-pager -l; journalctl -u sssd -b --no-pager | tail -150; sssctl config-check"',
    '"systemctl status cups --no-pager; journalctl -u cups -b"': '"systemctl status cups --no-pager -l; journalctl -u cups -b --no-pager | tail -150; lpstat -r"',
}
for old, new in base_replacements.items():
    count = s.count(old)
    if count == 0:
        raise SystemExit(f'base replacement not found: {old}')
    s = s.replace(old, new)

# Explain that 802.1X DER needs -inform DER in the recommendation itself.
s = s.replace(
    'REC_CHECK="Проверить EAP-метод, CA/client certificate, срок действия и ошибки NetworkManager/supplicant."',
    'REC_CHECK="Проверить EAP-метод, CA/client certificate, срок действия и ошибки NetworkManager/supplicant. Если сертификат DER, для ручного openssl добавьте -inform DER."',
    1,
)

ARM.write_text(s, encoding='utf-8')

# Version sources.
(ROOT / 'VERSION').write_text('1.2.4\n', encoding='utf-8')

spec = (ROOT / 'packaging/arm_info.spec').read_text(encoding='utf-8')
spec = replace_once(spec, 'Version:        1.2.3', 'Version:        1.2.4', 'rpm version')
changelog_anchor = '%changelog\n'
spec_entry = '''%changelog
* Wed Sep 16 2026 NewMishka - 1.2.4-1
- Audit and correct all administrator recommendation commands
- Add per-command descriptions, explicit state-change warnings and safe placeholders
- Fix NetworkManager 802.1X/DNS, CUPS package, Kerberos user-context and RAID diagnostics

'''
spec = replace_once(spec, changelog_anchor, spec_entry, 'rpm changelog')
(ROOT / 'packaging/arm_info.spec').write_text(spec, encoding='utf-8')

# Makefile/CI: new permanent recommendation-command contract test.
mk = (ROOT / 'Makefile').read_text(encoding='utf-8')
mk = mk.replace('tests/test_cli.sh tests/test_enterprise.sh packaging/build-rpm.sh', 'tests/test_cli.sh tests/test_enterprise.sh tests/test_recommendation_commands.sh packaging/build-rpm.sh')
mk = replace_once(mk, '\tbash tests/test_enterprise.sh\n', '\tbash tests/test_enterprise.sh\n\tbash tests/test_recommendation_commands.sh\n', 'make recommendation test')
(ROOT / 'Makefile').write_text(mk, encoding='utf-8')

ci = (ROOT / '.github/workflows/ci.yml').read_text(encoding='utf-8')
ci = ci.replace('tests/test_cli.sh tests/test_enterprise.sh packaging/build-rpm.sh', 'tests/test_cli.sh tests/test_enterprise.sh tests/test_recommendation_commands.sh packaging/build-rpm.sh')
ci = replace_once(ci, '      - name: Enterprise profile tests\n        run: bash tests/test_enterprise.sh\n', '      - name: Enterprise profile tests\n        run: bash tests/test_enterprise.sh\n      - name: Recommendation command audit tests\n        run: bash tests/test_recommendation_commands.sh\n', 'ci recommendation step')
(ROOT / '.github/workflows/ci.yml').write_text(ci, encoding='utf-8')

# Static regression tests focus on the errors found by the audit and on safe rendering.
test = r'''#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/arm_info.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

grep -q 'base_print_rec_commands' "$SCRIPT" || fail 'base command splitter missing'
grep -q 'ИЗМЕНЯЕТ СОСТОЯНИЕ' "$SCRIPT" || fail 'state-changing command warning missing'
grep -q 'DOMAIN_FQDN' "$SCRIPT" || fail 'safe domain placeholder missing'
grep -q 'PROFILE_NAME' "$SCRIPT" || fail '802.1X profile placeholder missing'
grep -q 'CERT_PATH' "$SCRIPT" || fail 'certificate placeholder missing'
grep -q 'MD_DEVICE' "$SCRIPT" || fail 'RAID placeholder missing'
grep -q 'UNIT_NAME' "$SCRIPT" || fail 'systemd unit placeholder missing'
grep -q 'DEVICE_PATH' "$SCRIPT" || fail 'device placeholder missing'
grep -q 'USER_NAME' "$SCRIPT" || fail 'user-context placeholder missing'

! grep -Fq 'nmcli -f NAME,IP4.DOMAIN,IP4.DNS connection show --active' "$SCRIPT" || fail 'invalid nmcli active-list fields remain'
! grep -Fq 'nmcli -f NAME,TYPE,802-1x.eap,802-1x.ca-cert,802-1x.client-cert connection show' "$SCRIPT" || fail 'invalid nmcli 802.1X list fields remain'
! grep -Fq 'rpm -qf "$(command -v lpstat' "$SCRIPT" || fail 'guaranteed-fail lpstat rpm query remains'
! grep -Fq 'mdadm --detail /dev/md0' "$SCRIPT" || fail 'hard-coded md0 remains'
! grep -Fq "find /tmp -maxdepth 1 -type f -name 'krb5cc_*'" "$SCRIPT" || fail 'FILE-cache-only Kerberos recommendation remains'
! grep -Fq '<DOMAIN>' "$SCRIPT" || fail 'shell-redirection-style DOMAIN placeholder remains'
! grep -Fq '<MOUNT>' "$SCRIPT" || fail 'shell-redirection-style MOUNT placeholder remains'
! grep -Fq '<QUEUE>' "$SCRIPT" || fail 'shell-redirection-style QUEUE placeholder remains'
! grep -Fq '<JOB_ID>' "$SCRIPT" || fail 'shell-redirection-style JOB placeholder remains'

# Representative copy/paste commands must be valid Bash after replacing service markers.
commands=(
  "nmcli -f GENERAL.CONNECTION,IP4.DNS,IP4.DOMAIN device show"
  "nmcli connection show 'PROFILE_NAME' | grep -E '^802-1x\\.(eap|identity|ca-cert|client-cert|phase2-ca-cert|phase2-client-cert|private-key|system-ca-certs):'"
  "openssl x509 -in \"CERT_PATH\" -noout -subject -issuer -dates"
  "timeout 5 nc -vz DC_FQDN 88"
  "findmnt -t cifs -o TARGET,SOURCE,OPTIONS"
  "lpstat -W not-completed -o"
  "dnf provides '/usr/bin/lpstat'"
  "systemctl status UNIT_NAME --no-pager -l"
  "journalctl -u UNIT_NAME -b --no-pager | tail -120"
  "mdadm --detail MD_DEVICE"
  "top -b -n1 | head -30"
)
for cmd in "${commands[@]}"; do
  bash -n -c "$cmd" || fail "invalid command syntax: $cmd"
done

echo 'recommendation command audit tests: OK'
'''
(ROOT / 'tests/test_recommendation_commands.sh').write_text(test, encoding='utf-8')

# README and docs.
readme = (ROOT / 'README.md').read_text(encoding='utf-8')
readme = readme.replace('стабильности ОС,', 'стабильности системы,', 1)
readme = readme.replace('| Стабильность ОС | 15% |', '| Стабильность системы | 15% |')
readme = readme.replace('`arm_info 1.2.3` содержит', '`arm_info 1.2.4` содержит')
readme = readme.replace('Текущая версия: **1.2.3**.', 'Текущая версия: **1.2.4**.')
insert_before = '\nЕсли отчёт нужно передать вне внутреннего контура или использовать для сравнения АРМ:\n'
audit_note = '\nВ **1.2.4** проведена ревизия всех команд из рекомендаций: исправлены некорректные варианты `nmcli`, исключены заведомо бесполезные проверки отсутствующих утилит, добавлены пользовательский контекст Kerberos, таймауты сетевых проверок, безопасные маркеры (`DOMAIN_FQDN`, `PROFILE_NAME`, `MOUNT_PATH` и т. п.) и явное предупреждение `ИЗМЕНЯЕТ СОСТОЯНИЕ` для команд, меняющих конфигурацию/очередь. Каждая выводимая команда получает отдельное описание результата.\n'
readme = replace_once(readme, insert_before, audit_note + insert_before, 'README 1.2.4 paragraph')
readme = readme.replace('- [Тестирование](docs/TESTING.md)\n', '- [Тестирование](docs/TESTING.md)\n- [Команды рекомендаций](docs/COMMANDS.md)\n')
(ROOT / 'README.md').write_text(readme, encoding='utf-8')

ch = (ROOT / 'CHANGELOG.md').read_text(encoding='utf-8')
entry = '''# Changelog

## 1.2.4 — 2026-09-16

### Changed
- Проведена полная ревизия команд, предлагаемых в стандартных и корпоративных рекомендациях.
- Исправлены некорректные/нестабильные варианты `nmcli` для DNS и 802.1X: профиль сначала выбирается из списка, затем его `802-1x.*` свойства читаются отдельно.
- Kerberos-проверки явно учитывают контекст пользователя (`klist -l/-A`, `sudo -u USER_NAME klist -A`), вместо предположения, что FILE-cache обязательно находится в `/tmp`.
- TCP-проверки DC ограничены `timeout`, чтобы диагностическая команда сама не зависала.
- Для отсутствующего `lpstat` больше не предлагается гарантированно бесполезный `rpm -qf` пустого пути; используются `rpm -q cups-client` и `dnf provides /usr/bin/lpstat`.
- RAID-рекомендация больше не предполагает `/dev/md0`: используется явный `MD_DEVICE`.
- Стандартные рекомендации умеют выводить несколько независимых команд отдельно; pipelines не дробятся.
- Команды с динамическими путями ФС получают shell-safe quoting через `%q`.
- Служебные маркеры вида `<DOMAIN>`/`<MOUNT>` заменены безопасными именованными токенами (`DOMAIN_FQDN`, `MOUNT_PATH`, `QUEUE_NAME`, `UNIT_NAME` и др.), которые не интерпретируются shell как redirection.
- Команды, изменяющие состояние (`dnf install`, `cupsenable`, `cupsaccept`, `cancel`), получают явную пометку `ИЗМЕНЯЕТ СОСТОЯНИЕ`.
- Каждая команда в текстовой рекомендации имеет отдельное описание ожидаемого результата.
- Добавлен постоянный CI-тест `tests/test_recommendation_commands.sh` для защиты командного контракта.

'''
if not ch.startswith('# Changelog\n\n## 1.2.3'):
    raise SystemExit('unexpected CHANGELOG head')
ch = ch.replace('# Changelog\n\n', entry, 1)
(ROOT / 'CHANGELOG.md').write_text(ch, encoding='utf-8')

commands_doc = '''# Команды в рекомендациях

`arm_info` **никогда не выполняет команды из рекомендаций автоматически**. Они печатаются как проверяемый план действий администратора.

## Правила 1.2.4

1. Каждая команда выводится отдельно и получает пояснение в скобках: что именно она покажет или изменит.
2. Shell pipeline (`|`) остаётся одной физической командой и при копировании не разрывается.
3. Несколько независимых команд стандартного отчёта выводятся как `Команда 1`, `Команда 2` и т. д.
4. Маркеры `DOMAIN_FQDN`, `DC_FQDN`, `DC_IP`, `USER_NAME`, `PROFILE_NAME`, `CERT_PATH`, `MOUNT_PATH`, `QUEUE_NAME`, `JOB_ID`, `PARENT_PID`, `UNIT_NAME`, `DEVICE_PATH`, `MD_DEVICE`, `IFACE_NAME` нужно заменить фактическими значениями перед запуском.
5. Маркеры специально не используют `<...>`: символы `<`/`>` имеют специальное значение в shell и могут превратить случайно скопированную строку в redirection.
6. Команды, изменяющие состояние, помечаются `ИЗМЕНЯЕТ СОСТОЯНИЕ`. Сейчас это установка пакета, включение/разрешение CUPS-очереди и отмена задания. Их выполняют только после подтверждения причины.
7. Команды Kerberos/GVFS, зависящие от пользовательской session, должны выполняться в контексте затронутого пользователя; root-cache не эквивалентен cache интерактивного пользователя.
8. Необязательные утилиты (`chronyc`, `resolvectl`, `ethtool`, `nc`, `openssl`, `sssctl` и др.) могут отсутствовать. Это не повод автоматически устанавливать их; сначала оценивается необходимость и политика репозитория.

## Проверенные семейства команд

- systemd/journal: `systemctl status`, `systemctl --failed`, `journalctl -b`, `journalctl -k`, `journalctl --list-boots`;
- storage/FS: `smartctl -a/-A/--scan-open`, `findmnt`, `df`, `du`, `/proc/mdstat`, `mdadm --detail`;
- память/CPU: `free`, `vmstat`, `ps`, `top -b -n1`, `sensors`, EDAC sysfs;
- сеть/DNS: `ip`, `nmcli`, `resolvectl`/`systemd-resolve`, `dig`, `host`, `getent`, `nc` под `timeout`, `ethtool`;
- AD/SSSD/Kerberos: `realm list`, `sssctl domain-list/config-check`, `adcli testjoin --verbose`, `klist -l/-A`;
- 802.1X/X.509: `nmcli connection show PROFILE_NAME`, `openssl x509 ... -subject -issuer -dates`;
- CIFS/GVFS: `findmnt -t cifs`, `timeout stat`, `loginctl`, `/run/user/*/gvfs`;
- CUPS: `lpstat`, `cupsctl`, `cupsenable`, `cupsaccept`, `cancel`;
- packages: `command -v`, `rpm -q`, `dnf provides`, `dnf install`.

## Важные ограничения

`openssl x509 -in CERT_PATH ...` по умолчанию ожидает PEM. Для DER-файла добавьте `-inform DER`; сам 802.1X-анализ `arm_info` пытается определить формат автоматически.

`klist -A` показывает коллекцию credentials **текущего пользователя**. Если диагностика запущена от root, билет рабочего пользователя проверяйте отдельно, например `sudo -u 'USER_NAME' klist -A`.

`mdadm --detail MD_DEVICE` требует реальное имя массива из `/proc/mdstat`; скрипт больше не предполагает, что это всегда `/dev/md0`.

`cupsenable`, `cupsaccept` и `cancel` меняют состояние CUPS. До их запуска сначала изучите `lpstat` и `journalctl -u cups`.
'''
(ROOT / 'docs/COMMANDS.md').write_text(commands_doc, encoding='utf-8')

usage = (ROOT / 'docs/USAGE.md').read_text(encoding='utf-8')
usage += '''\n\n## Команды рекомендаций в 1.2.4\n\nВсе команды проходят отдельный command-audit contract. Каждая команда в TXT имеет описание ожидаемого результата; state-changing команды явно помечаются. Служебные значения задаются безопасными токенами (`DOMAIN_FQDN`, `PROFILE_NAME`, `MOUNT_PATH`, `UNIT_NAME` и т. п.), которые нужно заменить перед запуском. Подробно: [COMMANDS.md](COMMANDS.md).\n'''
(ROOT / 'docs/USAGE.md').write_text(usage, encoding='utf-8')

tech = (ROOT / 'docs/TECHNICAL.md').read_text(encoding='utf-8')
tech = tech.replace('7. Shell pipeline и регулярные выражения с `|` в enterprise-рекомендациях сохраняются как единая команда, а не дробятся по каждому символу `|`.', '7. Shell pipeline и регулярные выражения с `|` сохраняются как единая команда; несколько независимых команд выводятся отдельно и получают собственное описание.\n8. Служебные placeholder-токены не используют `<...>`, чтобы случайное копирование не превращалось в shell redirection; state-changing команды маркируются явно.')
tech = tech.replace('8. Privacy применяется', '9. Privacy применяется').replace('9. Конфигурация парсится', '10. Конфигурация парсится')
(ROOT / 'docs/TECHNICAL.md').write_text(tech, encoding='utf-8')

testing = (ROOT / 'docs/TESTING.md').read_text(encoding='utf-8')
testing = testing.replace('- `tests/test_enterprise.sh` — enterprise CLI, schema v2, privacy, `--compare`, single-file policy и контракт корпоративного отчёта.\n', '- `tests/test_enterprise.sh` — enterprise CLI, schema v2, privacy, `--compare`, single-file policy и контракт корпоративного отчёта;\n- `tests/test_recommendation_commands.sh` — статический аудит рекомендованных команд: безопасные placeholder-токены, отсутствие известных некорректных форм, синтаксис representative commands и предупреждения для state-changing действий.\n')
testing = testing.replace('- enterprise profiles/compare/recommendations tests;\n', '- enterprise profiles/compare/recommendations tests;\n- recommendation-command audit tests;\n')
(ROOT / 'docs/TESTING.md').write_text(testing, encoding='utf-8')

pre = (ROOT / 'docs/PRE_RELEASE_CHECKLIST.md').read_text(encoding='utf-8')
pre = pre.replace('- [ ] Enterprise profiles/compare/recommendations tests.\n', '- [ ] Enterprise profiles/compare/recommendations tests.\n- [ ] `tests/test_recommendation_commands.sh`: проверка всех известных проблемных форм команд и copy/paste-контракта.\n')
pre = pre.replace('- [ ] Enterprise-рекомендации содержат источник, причины, влияние, проверки, действия, команды и контроль результата; shell pipelines/regex с `|` не разрываются на отдельные команды.\n', '- [ ] Enterprise-рекомендации содержат источник, причины, влияние, проверки, действия, команды и контроль результата; shell pipelines/regex с `|` не разрываются на отдельные команды.\n- [ ] Каждая рекомендуемая команда имеет понятное описание результата; state-changing команды маркированы; placeholders не используют `<...>` и требуют явной замены.\n')
(ROOT / 'docs/PRE_RELEASE_CHECKLIST.md').write_text(pre, encoding='utf-8')

compat = (ROOT / 'docs/COMPATIBILITY.md').read_text(encoding='utf-8')
compat += '\n\n## Команды рекомендаций 1.2.4\n\nКомандный набор ориентирован на РЕД ОС 7/8 и RHEL-подобное окружение. Для различий systemd-resolved предусмотрены `resolvectl` и старый `systemd-resolve`; необязательные команды не считаются гарантированно установленными. Диагностические команды не выполняются автоматически.\n'
(ROOT / 'docs/COMPATIBILITY.md').write_text(compat, encoding='utf-8')

release = '''# arm_info 1.2.4\n\nВерсия 1.2.4 посвящена качеству команд, которые `arm_info` предлагает администратору в рекомендациях.\n\n## Что изменено\n\n- проведена полная ревизия стандартных и корпоративных recommendation commands;\n- исправлены некорректные варианты `nmcli` для DNS/802.1X;\n- Kerberos-команды учитывают пользовательский credential-cache, а не предполагают только `/tmp/krb5cc_*`;\n- DC TCP-проверки получили timeout;\n- CUPS package diagnostics и software/RPM fallback исправлены;\n- RAID больше не предполагает `/dev/md0`;\n- динамические пути файловых систем shell-экранируются;\n- несколько независимых команд стандартного отчёта выводятся отдельно, pipelines остаются цельными;\n- `<...>` placeholders заменены безопасными именованными токенами;\n- state-changing команды получают явное предупреждение;\n- каждая команда имеет описание ожидаемого результата;\n- добавлен постоянный CI-тест командного контракта и `docs/COMMANDS.md`.\n\nЭто pre-release ветка до полевого подтверждения на РЕД ОС; production release не должен публиковаться до отдельного решения.\n'''
(ROOT / 'docs/releases/v1.2.4.md').write_text(release, encoding='utf-8')
