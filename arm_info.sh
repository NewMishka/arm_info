#!/bin/bash

(
# ============================================================
# arm_info 1.1.0 — диагностика АРМ для РЕД ОС 7 / 8
# Запуск: через bash-файл или целиком вставить в root-терминал.
# Результат одновременно выводится на экран и сохраняется в TXT.
# ============================================================

if [ -z "${BASH_VERSION:-}" ]; then
    echo "Ошибка: скрипт необходимо запускать через bash." >&2
    exit 1
fi

ARM_INFO_VERSION="1.1.0"

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
SAVE_REPORT=1
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
  --privacy               обезличить hostname, IP, MAC, DNS и имена интерфейсов
  --no-save               не сохранять отчёт в файл
  -o, --output PATH       сохранить отчёт в указанный файл или каталог
  -q, --quiet             не выводить отчёт в терминал (имеет смысл с сохранением)
  --json                  вывести отчёт в JSON вместо текстового формата
  --config PATH           использовать другой конфигурационный файл

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
        --privacy) PRIVACY_MODE=1; shift ;;
        --no-save) SAVE_REPORT=0; shift ;;
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

WIDTH=92
line() { printf '%*s\n' "$WIDTH" '' | tr ' ' '-'; }
section() { echo; echo "$1"; line; }
table() {
    if command -v column >/dev/null 2>&1; then column -t -s '|'; else tr '|' ' '; fi
}
min_score() { (( $2 < $1 )) && echo "$2" || echo "$1"; }
clamp_score() { local v="$1"; ((v<0))&&v=0; ((v>100))&&v=100; echo "$v"; }

REC_LEVELS=(); REC_TITLES=(); REC_IMPACTS=(); REC_ACTIONS=(); REC_CHECKS=()
add_rec() {
    REC_LEVELS+=("$1"); REC_TITLES+=("$2"); REC_IMPACTS+=("$3");
    REC_ACTIONS+=("$4"); REC_CHECKS+=("${5:-}")
}
print_wrapped() {
    local label="$1" text="$2" w=$((WIDTH-17)) first=1 ln
    while IFS= read -r ln; do
        if ((first)); then printf '   %-12s %s\n' "$label" "$ln"; first=0
        else printf '   %-12s %s\n' '' "$ln"; fi
    done < <(printf '%s\n' "$text" | fold -s -w "$w")
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
UPTIME=$(LC_ALL=C uptime -p 2>/dev/null | sed 's/^up //'); [ -z "$UPTIME" ] && UPTIME="Не определено"
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
RX_DROPS_TOTAL=0; TX_DROPS_TOTAL=0
RX_PACKETS_TOTAL=0; TX_PACKETS_TOTAL=0
RXTX_ERRORS=0; RXTX_DROPS=0; RXTX_PACKETS=0
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
    RX=$(cat "$P/statistics/rx_errors" 2>/dev/null); TX=$(cat "$P/statistics/tx_errors" 2>/dev/null); RXD=$(cat "$P/statistics/rx_dropped" 2>/dev/null); TXD=$(cat "$P/statistics/tx_dropped" 2>/dev/null)
    RXP=$(cat "$P/statistics/rx_packets" 2>/dev/null); TXP=$(cat "$P/statistics/tx_packets" 2>/dev/null)
    for V in RX TX RXD TXD RXP TXP; do eval 'X=${'"$V"'}'; [[ "$X" =~ ^[0-9]+$ ]]||eval "$V=0"; done
    RX_ERRORS_TOTAL=$((RX_ERRORS_TOTAL+RX)); TX_ERRORS_TOTAL=$((TX_ERRORS_TOTAL+TX))
    RX_DROPS_TOTAL=$((RX_DROPS_TOTAL+RXD)); TX_DROPS_TOTAL=$((TX_DROPS_TOTAL+TXD))
    RX_PACKETS_TOTAL=$((RX_PACKETS_TOTAL+RXP)); TX_PACKETS_TOTAL=$((TX_PACKETS_TOTAL+TXP))
    RXTX_ERRORS=$((RX_ERRORS_TOTAL+TX_ERRORS_TOTAL)); RXTX_DROPS=$((RX_DROPS_TOTAL+TX_DROPS_TOTAL)); RXTX_PACKETS=$((RX_PACKETS_TOTAL+TX_PACKETS_TOTAL))
    IF_BAD=$((RX+TX+RXD+TXD)); IF_PKT=$((RXP+TXP)); IF_PPM=0; ((IF_PKT>0))&&IF_PPM=$((IF_BAD*1000000/IF_PKT)); ((IF_PPM>=1000))&&NET_BAD_IFACES+=("$IFACE:${IF_PPM}ppm")
done
NET_BAD_PPM=0
NET_ERROR_PPM=0
NET_DROP_PPM=0
NET_BAD_PERCENT="0.0000"
if ((RXTX_PACKETS>0)); then
    NET_BAD_PPM=$(((RXTX_ERRORS+RXTX_DROPS)*1000000/RXTX_PACKETS))
    NET_ERROR_PPM=$((RXTX_ERRORS*1000000/RXTX_PACKETS))
    NET_DROP_PPM=$((RXTX_DROPS*1000000/RXTX_PACKETS))
    NET_BAD_PERCENT=$(awk -v bad="$((RXTX_ERRORS+RXTX_DROPS))" -v pkt="$RXTX_PACKETS" 'BEGIN{if(pkt>0)printf "%.4f",bad*100/pkt;else print "0.0000"}')
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
ROOT_USE=$(df -P / 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}'); ROOT_INODE_USE=$(df -Pi / 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}')
ROOT_SIZE=$(df -hP / 2>/dev/null | awk 'NR==2{print $2}'); ROOT_USED=$(df -hP / 2>/dev/null | awk 'NR==2{print $3}'); ROOT_FREE=$(df -hP / 2>/dev/null | awk 'NR==2{print $4}')
[[ "$ROOT_USE" =~ ^[0-9]+$ ]]||ROOT_USE=0; [[ "$ROOT_INODE_USE" =~ ^[0-9]+$ ]]||ROOT_INODE_USE=0
ROOT_RO=0; findmnt -no OPTIONS / 2>/dev/null | grep -Eq '(^|,)ro(,|$)'&&ROOT_RO=1
LOCAL_FS_COUNT=0; LOCAL_RO_COUNT=0; FS_WORST_USE=$ROOT_USE; FS_WORST_USE_MOUNT=/; FS_WORST_INODE=$ROOT_INODE_USE; FS_WORST_INODE_MOUNT=/; FS_RO_MOUNTS=(); LOCAL_FS_ROWS=()
while IFS= read -r MNT; do
    [ -n "$MNT" ]||continue
    USE=$(df -P "$MNT" 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}'); INO=$(df -Pi "$MNT" 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}')
    [[ "$USE" =~ ^[0-9]+$ ]]||USE=0; [[ "$INO" =~ ^[0-9]+$ ]]||INO=0
    RO=0; findmnt -no OPTIONS --target "$MNT" 2>/dev/null | grep -Eq '(^|,)ro(,|$)'&&RO=1
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
DISK_ROWS=(); DISK_SELFTEST_ROWS=(); DISK_WORST_SCORE=100; FIXED_DISKS=0; MAX_DISK_HOURS=0; SMART_UNKNOWN_COUNT=0
while read -r NAME TYPE SIZE ROTA MODEL; do
    case "$TYPE" in disk|rom) ;; *) continue ;; esac
    DEV="/dev/$NAME"; MODEL=$(echo "$MODEL" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'); [ -z "$MODEL" ]&&MODEL="-"; [ "${#MODEL}" -gt 28 ]&&MODEL="${MODEL:0:27}…"
    if [[ "$TYPE" = rom || "$NAME" = sr* ]]; then DISK_ROWS+=("$NAME|CD/DVD||$MODEL|-|-|-|-"); continue; fi
    FIXED_DISKS=$((FIXED_DISKS+1)); DISK_SCORE=100; RESOURCE="-"; SMART="Н/Д"; TEMP="-"; HOURS="-"; REALLOC=0; PENDING=0; UNCORR=0; MEDIAERR=0; CRITWARN=0
    if [[ "$NAME" = nvme* ]]; then DISK_TYPE="NVMe SSD"; elif [ "$ROTA" = 0 ]; then DISK_TYPE=SSD; else DISK_TYPE=HDD; fi
    if command -v smartctl >/dev/null 2>&1; then
        SMART_ALL=$(run_smart -a "$DEV" 2>/dev/null); SMART_H=$(run_smart -H "$DEV" 2>/dev/null)
        SELFTEST="Н/Д"
        _st=$(run_smart -l selftest "$DEV" 2>/dev/null | awk '/^# *1[[:space:]]/{for(i=5;i<=NF;i++){printf "%s%s",$i,(i<NF?" ":"")} exit}')
        [ -n "$_st" ] && SELFTEST="$_st"
        DISK_SELFTEST_ROWS+=("$NAME|$SELFTEST")
        if echo "$SMART_H"|grep -Eqi 'PASSED|SMART.*OK'; then SMART=OK; elif echo "$SMART_H"|grep -Eqi 'FAILED|SMART.*BAD'; then SMART=FAIL; DISK_SCORE=0; else SMART="Н/Д"; SMART_UNKNOWN_COUNT=$((SMART_UNKNOWN_COUNT+1)); fi
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
    DISK_SCORE=$(clamp_score "$DISK_SCORE"); ((DISK_SCORE<DISK_WORST_SCORE))&&DISK_WORST_SCORE=$DISK_SCORE; [[ "$HOURS" =~ ^[0-9]+$ ]]&&((HOURS>MAX_DISK_HOURS))&&MAX_DISK_HOURS=$HOURS
    DISK_ROWS+=("$NAME|$DISK_TYPE|$SIZE|$MODEL|$RESOURCE|$SMART|$TEMP|$HOURS")

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
((FIXED_DISKS==0))&&DISK_WORST_SCORE=70
((RAID_DEGRADED==1)) && DISK_WORST_SCORE=$(min_score "$DISK_WORST_SCORE" 30)

# -------------------- БАЛЛЫ --------------------
STORAGE_SCORE=$DISK_WORST_SCORE
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

STAB_SCORE=100
if ((FAILED_COUNT==1)); then STAB_SCORE=$((STAB_SCORE-5)); elif ((FAILED_COUNT<=3 && FAILED_COUNT>=2)); then STAB_SCORE=$((STAB_SCORE-10)); elif ((FAILED_COUNT>3)); then STAB_SCORE=$((STAB_SCORE-20)); fi
if ((HW_ERR_COUNT<=2 && HW_ERR_COUNT>=1)); then STAB_SCORE=$((STAB_SCORE-10)); elif ((HW_ERR_COUNT<=5 && HW_ERR_COUNT>=3)); then STAB_SCORE=$((STAB_SCORE-20)); elif ((HW_ERR_COUNT>5)); then STAB_SCORE=$((STAB_SCORE-35)); fi
if ((JOURNAL_ERR_COUNT>=6 && JOURNAL_ERR_COUNT<=15)); then STAB_SCORE=$((STAB_SCORE-5)); elif ((JOURNAL_ERR_COUNT>=16 && JOURNAL_ERR_COUNT<=30)); then STAB_SCORE=$((STAB_SCORE-10)); elif ((JOURNAL_ERR_COUNT>30)); then STAB_SCORE=$((STAB_SCORE-15)); fi
((OOM_DETECTED==1))&&STAB_SCORE=$((STAB_SCORE-10))
[ "$TIME_SYNC" = "Нет" ] && STAB_SCORE=$((STAB_SCORE-5))
((UNCLEAN_BOOT_SIGNS>0)) && STAB_SCORE=$((STAB_SCORE-5))
((ECC_CE>0)) && STAB_SCORE=$((STAB_SCORE-5))
((ECC_UE>0)) && STAB_SCORE=$(min_score "$STAB_SCORE" 30)
STAB_SCORE=$(clamp_score "$STAB_SCORE")

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

DISK_AGE_MONTHS=-1; DISK_AGE_YEARS=-1; ((MAX_DISK_HOURS>0))&&{ DISK_AGE_MONTHS=$((MAX_DISK_HOURS*12/8760)); DISK_AGE_YEARS=$((DISK_AGE_MONTHS/12)); }
OS_AGE_MONTHS=-1; ((AGE_DAYS>=0))&&OS_AGE_MONTHS=$((AGE_DAYS*12/365))
SYSTEM_AGE_MONTHS=-1; AGE_SOURCE="Не определён"
if ((DISK_AGE_MONTHS>=0 && OS_AGE_MONTHS>=0)); then if ((DISK_AGE_MONTHS>=OS_AGE_MONTHS)); then SYSTEM_AGE_MONTHS=$DISK_AGE_MONTHS; AGE_SOURCE="макс. наработка накопителя"; else SYSTEM_AGE_MONTHS=$OS_AGE_MONTHS; AGE_SOURCE="возраст текущей установки ОС"; fi
elif ((DISK_AGE_MONTHS>=0)); then SYSTEM_AGE_MONTHS=$DISK_AGE_MONTHS; AGE_SOURCE="макс. наработка накопителя"; elif ((OS_AGE_MONTHS>=0)); then SYSTEM_AGE_MONTHS=$OS_AGE_MONTHS; AGE_SOURCE="возраст текущей установки ОС"; fi
SYSTEM_AGE_TEXT="Не определён"; ((SYSTEM_AGE_MONTHS>=0))&&SYSTEM_AGE_TEXT=$(awk -v m="$SYSTEM_AGE_MONTHS" 'BEGIN{printf "%.1f",m/12}')
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
if ! command -v smartctl >/dev/null 2>&1 && ((FIXED_DISKS>0)); then STORAGE_KNOWN=0; fi
((SMART_UNKNOWN_COUNT>0))&&STORAGE_KNOWN=0
AGE_KNOWN=1; ((SYSTEM_AGE_MONTHS<0))&&AGE_KNOWN=0
TOTAL_NUM=$((FS_SCORE*15 + STAB_SCORE*15 + MEM_SCORE*10 + CPU_SCORE*10 + NET_SCORE*5))
TOTAL_DEN=55
if ((STORAGE_KNOWN==1)); then TOTAL_NUM=$((TOTAL_NUM + STORAGE_SCORE*40)); TOTAL_DEN=$((TOTAL_DEN+40)); fi
if ((AGE_KNOWN==1)); then TOTAL_NUM=$((TOTAL_NUM + AGE_SCORE*5)); TOTAL_DEN=$((TOTAL_DEN+5)); fi
if ((TOTAL_DEN>0)); then TOTAL_SCORE=$((TOTAL_NUM/TOTAL_DEN)); else TOTAL_SCORE=0; fi
TOTAL_SCORE=$(clamp_score "$TOTAL_SCORE")

# -------------------- ПОЛНОТА --------------------
CONFIDENCE=100; CONFIDENCE_NOTES=()
if ! command -v smartctl >/dev/null 2>&1 && ((FIXED_DISKS>0)); then CONFIDENCE=$((CONFIDENCE-25)); CONFIDENCE_NOTES+=("нет smartctl"); elif ((SMART_UNKNOWN_COUNT>0)); then CONFIDENCE=$((CONFIDENCE-15)); CONFIDENCE_NOTES+=("SMART частично недоступен"); fi
[ "$CPU_TEMP" = - ]&&{ CONFIDENCE=$((CONFIDENCE-5)); CONFIDENCE_NOTES+=("нет температуры CPU"); }
((SYSTEM_AGE_MONTHS<0))&&{ CONFIDENCE=$((CONFIDENCE-5)); CONFIDENCE_NOTES+=("нет возраста/наработки"); }
((JOURNAL_AVAILABLE==0))&&{ CONFIDENCE=$((CONFIDENCE-10)); CONFIDENCE_NOTES+=("journal недоступен"); }
((SYSTEMD_AVAILABLE==0))&&{ CONFIDENCE=$((CONFIDENCE-5)); CONFIDENCE_NOTES+=("службы не проверены"); }
[ "$RAM_MODULES" = "?" ]&&{ CONFIDENCE=$((CONFIDENCE-5)); CONFIDENCE_NOTES+=("DMI ОЗУ недоступен"); }
[ "$(id -u)" -ne 0 ]&&{ CONFIDENCE=$((CONFIDENCE-10)); CONFIDENCE_NOTES+=("запуск не от root"); }
((CONFIDENCE<40))&&CONFIDENCE=40
CONFIDENCE_NOTE="-"; ((${#CONFIDENCE_NOTES[@]}>0))&&CONFIDENCE_NOTE=$(printf '%s, ' "${CONFIDENCE_NOTES[@]}"); CONFIDENCE_NOTE=${CONFIDENCE_NOTE%, }

if ((TOTAL_SCORE>=90)); then STATE="ОТЛИЧНОЕ"; elif ((TOTAL_SCORE>=80)); then STATE="ХОРОШЕЕ"; elif ((TOTAL_SCORE>=65)); then STATE="ТРЕБУЕТ ВНИМАНИЯ"; elif ((TOTAL_SCORE>=50)); then STATE="ПЛОХОЕ"; else STATE="КРИТИЧЕСКОЕ"; fi
if ((ROOT_RO==1 || STORAGE_SCORE<30 || ROOT_USE>=98 || RAID_DEGRADED==1 || ECC_UE>0)); then STATE="КРИТИЧЕСКОЕ"; elif ((OOM_DETECTED==1 || HW_ERR_COUNT>0 || ROOT_USE>=95 || ACTIVE_NET==0)); then [ "$STATE" = "ОТЛИЧНОЕ" ]||[ "$STATE" = "ХОРОШЕЕ" ]&&STATE="ТРЕБУЕТ ВНИМАНИЯ"; fi
STATE_DISPLAY="$STATE"; ((CONFIDENCE<80))&&STATE_DISPLAY="ПРЕДВАРИТЕЛЬНО: $STATE"

# -------------------- РЕКОМЕНДАЦИИ --------------------
if ! command -v smartctl >/dev/null 2>&1 && ((FIXED_DISKS>0)); then add_rec "ПРОВЕРКА" "SMART накопителей не проверен" "Без SMART нельзя достоверно оценить износ SSD/NVMe и признаки деградации HDD." "Установить smartmontools и повторить диагностику." "dnf install smartmontools"; elif ((SMART_UNKNOWN_COUNT>0)); then add_rec "ПРОВЕРКА" "SMART частично недоступен" "Состояние части накопителей оценено не полностью." "Проверить контроллер/поддержку SMART." "smartctl --scan-open"; fi
if ((FS_WORST_USE>=FS_CRIT)); then add_rec "КРИТИЧНО" "ФС $FS_WORST_USE_MOUNT заполнена на ${FS_WORST_USE}%" "Может прекратиться запись журналов, временных файлов и работа служб." "Срочно освободить минимум 10–15% объёма." "du -xhd1 '$FS_WORST_USE_MOUNT' 2>/dev/null | sort -h"; elif ((FS_WORST_USE>=FS_HIGH)); then add_rec "ВНИМАНИЕ" "ФС $FS_WORST_USE_MOUNT заполнена на ${FS_WORST_USE}%" "Мало места для обновлений, журналов и рабочих файлов." "Освободить место до уровня ниже 80%." "du -xhd1 '$FS_WORST_USE_MOUNT' 2>/dev/null | sort -h"; elif ((FS_WORST_USE>=FS_WARN)); then add_rec "ПЛАНОВО" "ФС $FS_WORST_USE_MOUNT заполнена на ${FS_WORST_USE}%" "Снижается резерв свободного места." "Выполнить плановую очистку и держать заполнение ниже 80%." "df -h '$FS_WORST_USE_MOUNT'"; fi
((FS_WORST_INODE>=INODE_WARN))&&add_rec "ВНИМАНИЕ" "Inode на $FS_WORST_INODE_MOUNT использованы на ${FS_WORST_INODE}%" "При исчерпании inode новые файлы создать нельзя даже при наличии свободного места." "Найти каталоги с большим количеством мелких файлов и очистить ненужные кэши/временные данные." "df -i '$FS_WORST_INODE_MOUNT'"
((ROOT_RO==1))&&add_rec "КРИТИЧНО" "Корневая ФС смонтирована read-only" "Запись данных, обновления и часть служб могут не работать." "Проверить журнал ядра; fsck выполнять только на размонтированной ФС из rescue/live." "journalctl -k -b -p warning..alert"
if ((MEM_AVAIL_PCT<15)); then add_rec "ВНИМАНИЕ" "Мало доступной ОЗУ — ${MEM_AVAIL_PCT}%" "Возможны торможения, swap и OOM." "Определить крупнейшие процессы; при постоянном дефиците увеличить RAM." "ps aux --sort=-%mem | head -15"; elif ((MEM_AVAIL_PCT<25)); then add_rec "ПЛАНОВО" "Небольшой запас ОЗУ — ${MEM_AVAIL_PCT}%" "При росте нагрузки система может активнее использовать swap." "Проверить крупнейшие процессы и наблюдать динамику." "free -h"; fi
((OOM_DETECTED==1))&&add_rec "КРИТИЧНО" "За текущую загрузку срабатывал OOM-killer" "Ядро принудительно завершало процесс из-за нехватки памяти." "Определить процесс-виновник и устранить дефицит/утечку; при необходимости увеличить RAM или swap." "journalctl -k -b | grep -Ei 'oom-kill|out of memory'"
((FAILED_COUNT>0))&&add_rec "ВНИМАНИЕ" "Есть failed-службы: $FAILED_NAMES" "Функции этих служб могут быть недоступны или работать частично." "Проверить каждую службу, устранить первичную ошибку и перезапустить." "systemctl --failed"
((HW_ERR_COUNT>0))&&add_rec "КРИТИЧНО" "В ядре обнаружены аппаратные/дисковые ошибки — $HW_ERR_COUNT" "Возможны I/O-сбои, зависания и повреждение данных." "Сопоставить сообщение с устройством, проверить SMART, кабели и питание." "journalctl -k -b -p warning..alert --no-pager"
if ((JOURNAL_AVAILABLE==1 && JOURNAL_ERR_COUNT>30)); then add_rec "ВНИМАНИЕ" "Много уникальных ошибок journal — $JOURNAL_ERR_COUNT" "Возможна нестабильная служба, драйвер или повторяющаяся системная проблема." "Сгруппировать ошибки по источнику и устранить первичную причину." "journalctl -b -p err..alert -o short-iso --no-pager"; elif ((JOURNAL_AVAILABLE==1 && JOURNAL_ERR_COUNT>=6)); then add_rec "ПРОВЕРКА" "В journal есть уникальные ошибки — $JOURNAL_ERR_COUNT" "Не все error-сообщения критичны, но их нужно сопоставить с используемыми службами." "Просмотреть ошибки и проверить повторяемость." "journalctl -b -p err..alert -o short-iso --no-pager"; fi
if [[ "$CPU_TEMP" =~ ^[0-9]+$ ]]&&((CPU_TEMP>=CPU_TEMP_VHIGH)); then add_rec "КРИТИЧНО" "Высокая температура CPU — ${CPU_TEMP}°C" "Возможен троттлинг и аварийное выключение." "Очистить охлаждение, проверить вентилятор/радиатор и термоинтерфейс." "sensors"; elif [[ "$CPU_TEMP" =~ ^[0-9]+$ ]]&&((CPU_TEMP>=CPU_TEMP_WARN)); then add_rec "ВНИМАНИЕ" "Повышенная температура CPU — ${CPU_TEMP}°C" "Тепловой запас снижен; под нагрузкой возможен троттлинг." "Проверить пыль, вентилятор и температуру при типовой нагрузке." "sensors"; fi
if ((LOAD_STATE==2)); then add_rec "ВНИМАНИЕ" "Высокая системная нагрузка: Load1=$LOAD1" "Очередь задач/ожидания I/O велика, возможны задержки." "Найти процесс или I/O-источник постоянной нагрузки." "top"; elif ((LOAD_STATE==1)); then add_rec "ПРОВЕРКА" "Повышенная системная нагрузка: Load1=$LOAD1" "Система близка к полной загрузке CPU или имеет очередь I/O." "Если нагрузка не кратковременная — найти источник." "top"; fi
if ((SYSTEM_AGE_MONTHS>=96)); then add_rec "ПЛАНОВО" "Эксплуатационный ориентир — около ${SYSTEM_AGE_TEXT} лет" "Возраст сам по себе не означает неисправность, но повышает риск отказа вентиляторов, БП и контактов." "Обеспечить резервное копирование, профилактику и план обновления по фактическому состоянию." "Повторять диагностику планово"; elif ((SYSTEM_AGE_MONTHS>=72)); then add_rec "ПЛАНОВО" "Эксплуатационный ориентир — около ${SYSTEM_AGE_TEXT} лет" "Возрастной риск постепенно растёт." "Усилить контроль SMART, охлаждения и резервного копирования." "Повторять диагностику планово"; fi
((ACTIVE_NET==0))&&add_rec "КРИТИЧНО" "Не найден активный IPv4-интерфейс" "Сетевые ресурсы, домен и обновления могут быть недоступны." "Проверить линк, кабель и сетевой профиль." "ip -br a"
[ "$GW" = - ]&&add_rec "ВНИМАНИЕ" "Не найден маршрут по умолчанию" "Доступ за пределы локальной подсети может отсутствовать." "Проверить маршрут и шлюз активного профиля." "ip route"
[ "$DNS" = - ]&&add_rec "ВНИМАНИЕ" "DNS-серверы не определены" "Имена узлов и доменные сервисы могут не разрешаться." "Проверить /etc/resolv.conf и DNS в NetworkManager/systemd-resolved." "nmcli dev show 2>/dev/null | grep -i DNS"
if ((NET_ERROR_PPM>=NET_ERROR_WARN_PPM || NET_DROP_PPM>=NET_DROP_WARN_PPM)); then
    BAD_IF_TEXT=$(IFS=,;echo "${NET_BAD_IFACES[*]}")
    add_rec "ВНИМАНИЕ" "Повышенная доля сетевых ошибок/дропов" "Ошибки: ${NET_ERROR_PPM} ppm; дропы: ${NET_DROP_PPM} ppm. Возможны потери пакетов, медленная сеть и разрывы соединений." "Проверить кабель, порт коммутатора, согласование скорости/duplex и драйвер. ${BAD_IF_TEXT}" "ip -s link"
fi

[ "$TIME_SYNC" = "Нет" ] && add_rec "ВНИМАНИЕ" "Системное время не синхронизировано" "Ошибки времени нарушают TLS и особенно Kerberos/AD-аутентификацию." "Проверить chronyd/systemd-timesyncd, NTP-серверы и сетевую доступность." "timedatectl; chronyc tracking 2>/dev/null"
((UNCLEAN_BOOT_SIGNS>0)) && add_rec "ПРОВЕРКА" "Есть признаки аварийного завершения предыдущей загрузки" "Нештатное выключение может указывать на питание, зависание ядра или аппаратный сбой." "Изучить журнал предыдущей загрузки и сопоставить со временем инцидента." "journalctl -b -1 -p warning..alert"
((RAID_DEGRADED==1)) && add_rec "КРИТИЧНО" "Software RAID находится в DEGRADED" "Отказ ещё одного диска может привести к потере массива и данных." "Срочно проверить /proc/mdstat, определить неисправный член массива и восстановить резервирование." "cat /proc/mdstat; mdadm --detail /dev/md0 2>/dev/null"
((ECC_UE>0)) && add_rec "КРИТИЧНО" "ECC: обнаружены неисправимые ошибки памяти ($ECC_UE)" "Неисправимые ошибки памяти могут приводить к повреждению данных и аварийному завершению процессов." "Провести аппаратный тест ОЗУ и заменить неисправный модуль/слот." "grep -R . /sys/devices/system/edac/mc/mc*/ue_count 2>/dev/null"
((ECC_UE==0 && ECC_CE>0)) && add_rec "ПРОВЕРКА" "ECC: исправленных ошибок памяти — $ECC_CE" "ECC исправил ошибки, но рост счётчика может указывать на деградацию памяти." "Зафиксировать значения и проверить их рост при повторной диагностике." "grep -R . /sys/devices/system/edac/mc/mc*/ce_count 2>/dev/null"
if [[ "$BATTERY_HEALTH" =~ ^([0-9]+)%$ ]] && ((BASH_REMATCH[1]<60)); then add_rec "ПЛАНОВО" "Износ батареи: остаточная ёмкость около ${BATTERY_HEALTH}" "Снижается автономность; при дальнейшем износе возможны внезапные отключения без питания." "Проверить батарею и запланировать замену при неудовлетворительной автономности." "upower -i $(upower -e 2>/dev/null | grep BAT | head -1) 2>/dev/null"; fi
if [ "$SSSD_STATUS" != "Не установлен" ] && [ "$SSSD_STATUS" != "active" ]; then add_rec "ВНИМАНИЕ" "SSSD установлен, но состояние: $SSSD_STATUS" "Может не работать доменная аутентификация, разрешение пользователей и групп." "Проверить службу SSSD, конфигурацию и журнал." "systemctl status sssd --no-pager; journalctl -u sssd -b"; fi
if [ "$CUPS_STATUS" != "Не установлен" ] && [ "$CUPS_STATUS" != "active" ] && ((CUPS_QUEUES>0)); then add_rec "ВНИМАНИЕ" "CUPS не активен при наличии очередей печати" "Локальная печать через CUPS недоступна." "Запустить CUPS и проверить причину остановки." "systemctl status cups --no-pager; journalctl -u cups -b"; fi

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
if ((SAVE_REPORT==1)); then echo "Отчёт: $REPORT_FILE"; else echo "Сохранение: отключено (--no-save)"; fi

section "СИСТЕМА"
{
 echo "Хост|$HOST_DISPLAY"; echo "ОС|$OS"; echo "Модель системы|$SYSTEM_VENDOR $SYSTEM_PRODUCT"; echo "Ядро|$KERNEL"; echo "Архитектура|$ARCH"; echo "Установка ОС|$INSTALL_DATE"; ((AGE_YEARS>=0))&&echo "Возраст установки|≈ ${AGE_YEARS} лет"; echo "BIOS|$BIOS_VERSION; дата $BIOS_DATE (справочно)"; ((MAX_DISK_HOURS>0))&&echo "Макс. наработка диска|${MAX_DISK_HOURS} ч"; ((SYSTEM_AGE_MONTHS>=0))&&echo "Эксплуатационный ориентир|≈ ${SYSTEM_AGE_TEXT} лет ($AGE_SOURCE)"; echo "Время работы|$UPTIME"
} | table

section "ПРОЦЕССОР"
{
 echo "Модель|$CPU_MODEL"
 echo "Сокетов|$SOCKETS"
 echo "Ядер / потоков|$CORES / $THREADS"
 echo "Load 1 мин|$LOAD1"
 if [[ "$CPU_TEMP" =~ ^[0-9]+$ ]]; then
     echo "Температура CPU|${CPU_TEMP}°C (медиана; максимум ${CPU_TEMP_MAX}°C)"
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
 echo "RX дропы|$RX_DROPS_TOTAL"
 echo "TX дропы|$TX_DROPS_TOTAL"
 echo "Пакетов RX / TX|$RX_PACKETS_TOTAL / $TX_PACKETS_TOTAL"
 echo "Доля ошибок|${NET_ERROR_PPM} ppm"
 echo "Доля дропов|${NET_DROP_PPM} ppm"
 echo "Общая доля ошибок/дропов|${NET_BAD_PPM} ppm (${NET_BAD_PERCENT}%)"
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
{ echo "Диск|Тип|Размер|Модель|Ресурс|SMART|°C|Часы"; if ((${#DISK_ROWS[@]})); then printf '%s\n' "${DISK_ROWS[@]}"; else echo "-|-|-|Не найдены|-|-|-|-"; fi; } | table
if ((${#DISK_SELFTEST_ROWS[@]}>0)); then echo; { echo "Диск|Последний SMART self-test"; printf '%s\n' "${DISK_SELFTEST_ROWS[@]}"; } | table; fi

section "ФАЙЛОВЫЕ СИСТЕМЫ"
{ echo "Корневой раздел|$ROOT_DEV"; echo "Размер / занято / свободно|$ROOT_SIZE / $ROOT_USED / $ROOT_FREE"; echo "Корень: место / inode|${ROOT_USE}% / ${ROOT_INODE_USE}%"; echo "Локальных ФС проверено|$LOCAL_FS_COUNT"; echo "Макс. заполнение|${FS_WORST_USE}% на $FS_WORST_USE_MOUNT"; echo "Использование inode|${FS_WORST_INODE}% на $FS_WORST_INODE_MOUNT"; } | table
if ((${#LOCAL_FS_ROWS[@]}>1)); then echo; { echo "Точка|Место|Inode|Режим"; printf '%s\n' "${LOCAL_FS_ROWS[@]}"; } | table; fi

section "СВОДКА СОСТОЯНИЯ"
{ echo "Общее состояние|$STATE_DISPLAY"; echo "Индекс по доступным данным|$TOTAL_SCORE / 100"; echo "Полнота проверки|$CONFIDENCE%"; [ "$CONFIDENCE_NOTE" != - ]&&echo "Ограничения проверки|$CONFIDENCE_NOTE"; } | table
echo
STORAGE_SCORE_TEXT="$STORAGE_SCORE / 100"; ((STORAGE_KNOWN==0))&&STORAGE_SCORE_TEXT="Н/Д"
AGE_SCORE_TEXT="$AGE_SCORE / 100"; ((AGE_KNOWN==0))&&AGE_SCORE_TEXT="Н/Д"
{ echo "Показатель|Состояние|Вес в индексе"; echo "Накопители / износ|$STORAGE_SCORE_TEXT|40%"; echo "Файловая система|$FS_SCORE / 100|15%"; echo "Стабильность ОС|$STAB_SCORE / 100|15%"; echo "Оперативная память|$MEM_SCORE / 100|10%"; echo "Процессор / температура|$CPU_SCORE / 100|10%"; echo "Возраст / наработка|$AGE_SCORE_TEXT|5%"; echo "Сеть|$NET_SCORE / 100|5%"; } | table

section "КЛЮЧЕВЫЕ ПОКАЗАТЕЛИ"
SMART_SUMMARY=OK; if ((FIXED_DISKS==0)); then SMART_SUMMARY="Н/Д"; elif ! command -v smartctl >/dev/null 2>&1; then SMART_SUMMARY="Н/Д (smartctl отсутствует)"; elif ((STORAGE_SCORE==0)); then SMART_SUMMARY=FAIL; elif ((SMART_UNKNOWN_COUNT>0)); then SMART_SUMMARY="Частично / Н/Д"; fi
((OOM_DETECTED==1))&&OOM_TEXT="ОБНАРУЖЕНО"||OOM_TEXT="Не обнаружено"
{ echo "SMART накопителей|$SMART_SUMMARY"; echo "Файловые системы|макс. ${FS_WORST_USE}% на $FS_WORST_USE_MOUNT; inode ${FS_WORST_INODE}% на $FS_WORST_INODE_MOUNT"; echo "ОЗУ доступно|${MEM_AVAIL_PCT}%"; echo "Swap использовано|${SWAP_USED_PCT}%"; echo "Failed-служб|$FAILED_COUNT"; echo "Аппаратных/дисковых ошибок|$HW_ERR_COUNT"; if ((JOURNAL_AVAILABLE==1)); then echo "Уникальных journal error+|$JOURNAL_ERR_COUNT"; else echo "Journal текущей загрузки|Н/Д"; fi; echo "OOM за текущую загрузку|$OOM_TEXT"; echo "Синхронизация времени|$TIME_SYNC"; echo "Software RAID|$RAID_STATUS"; echo "ECC / EDAC|$ECC_STATUS"; [[ "$CPU_TEMP" =~ ^[0-9]+$ ]]&&echo "CPU температура|${CPU_TEMP}°C"; } | table

section "ЗАКЛЮЧЕНИЕ"
echo "$CONCLUSION"

section "РЕКОМЕНДАЦИИ"
if ((${#REC_TITLES[@]}==0)); then echo "Дополнительных действий не требуется."
else
 REC_NUM=0
 for LEVEL_WANTED in КРИТИЧНО ВНИМАНИЕ ПРОВЕРКА ПЛАНОВО; do
  for ((i=0;i<${#REC_TITLES[@]};i++)); do
   [ "${REC_LEVELS[$i]}" = "$LEVEL_WANTED" ]||continue
   REC_NUM=$((REC_NUM+1)); echo; echo "$REC_NUM. [${REC_LEVELS[$i]}] ${REC_TITLES[$i]}"
   print_wrapped "Влияние:" "${REC_IMPACTS[$i]}"; print_wrapped "Действие:" "${REC_ACTIONS[$i]}"; [ -n "${REC_CHECKS[$i]}" ]&&print_wrapped "Команда:" "${REC_CHECKS[$i]}"
  done
 done
fi

if ! command -v smartctl >/dev/null 2>&1; then echo; echo "Примечание: smartctl не установлен — оценка накопителей ограничена."; echo "Установка: dnf install smartmontools"; fi
[ "$(id -u)" -ne 0 ]&&{ echo; echo "Примечание: для полного SMART/dmidecode запускайте скрипт от root."; }

echo; line
echo "Индекс отражает текущее техническое состояние, износ накопителей, заполненность,"
echo "стабильность, ресурсную нагрузку и эксплуатационный ориентир. Вес — вклад показателя"
echo "в общий балл, а не процент износа. Индекс не прогнозирует срок службы."
if ((SAVE_REPORT==1)); then echo "Отчёт сохранён: $REPORT_FILE"; else echo "Отчёт не сохранялся (--no-save)."; fi
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
    printf '  "storage": {"score":%s,"known":%s,"fixed_disks":%s,"smart_unknown":%s},\n' \
        "$STORAGE_SCORE" "$([ "$STORAGE_KNOWN" -eq 1 ] && echo true || echo false)" "$FIXED_DISKS" "$SMART_UNKNOWN_COUNT"
    printf '  "filesystem": {"root_use_percent":%s,"max_use_percent":%s,"max_use_mount":"%s","max_inode_percent":%s,"score":%s},\n' \
        "$ROOT_USE" "$FS_WORST_USE" "$(json_escape "$FS_WORST_USE_MOUNT")" "$FS_WORST_INODE" "$FS_SCORE"
    printf '  "network": {"active_interfaces":%s,"gateway":"%s","dns":"%s","error_ppm":%s,"drop_ppm":%s,"score":%s},\n' \
        "$ACTIVE_NET" "$(json_escape "$GW_DISPLAY")" "$(json_escape "$DNS_DISPLAY")" "$NET_ERROR_PPM" "$NET_DROP_PPM" "$NET_SCORE"
    printf '  "stability": {"failed_units":%s,"hardware_errors":%s,"journal_errors":%s,"score":%s},\n' \
        "$FAILED_COUNT" "$HW_ERR_COUNT" "$JOURNAL_ERR_COUNT" "$STAB_SCORE"
    printf '  "diagnostics": {"time_sync":"%s","unclean_boot_signs":%s,"raid":"%s","ecc":"%s","battery_health":"%s","sssd":"%s","kerberos":"%s","cups":"%s","support_tier":"%s"},\n' \
        "$(json_escape "$TIME_SYNC")" "$UNCLEAN_BOOT_SIGNS" "$(json_escape "$RAID_STATUS")" "$(json_escape "$ECC_STATUS")" "$(json_escape "$BATTERY_HEALTH")" \
        "$(json_escape "$SSSD_STATUS")" "$(json_escape "$KRB_STATUS")" "$(json_escape "$CUPS_STATUS")" "$(json_escape "$SUPPORT_TIER")"
    printf '  "summary": {"state":"%s","score":%s,"confidence":%s,"conclusion":"%s"},\n' \
        "$(json_escape "$STATE_DISPLAY")" "$TOTAL_SCORE" "$CONFIDENCE" "$(json_escape "$CONCLUSION")"
    printf '  "recommendations": ['
    _first=1
    for ((i=0;i<${#REC_TITLES[@]};i++)); do
        ((_first==0)) && printf ','
        printf '\n    {"level":"%s","title":"%s","impact":"%s","action":"%s","command":"%s"}' \
            "$(json_escape "${REC_LEVELS[$i]}")" "$(json_escape "${REC_TITLES[$i]}")" "$(json_escape "${REC_IMPACTS[$i]}")" \
            "$(json_escape "${REC_ACTIONS[$i]}")" "$(json_escape "${REC_CHECKS[$i]}")"
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
