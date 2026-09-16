from pathlib import Path
import re

ROOT = Path('.')

def read(p): return (ROOT/p).read_text(encoding='utf-8')
def write(p,s): (ROOT/p).write_text(s, encoding='utf-8')
def rep(s, old, new, label, count=1):
    n=s.count(old)
    if n < count:
        raise SystemExit(f'{label}: expected at least {count}, got {n}')
    return s.replace(old,new,count)

# -------- arm_info.sh --------
p=Path('arm_info.sh'); s=read(p)
s=s.replace('arm_info 1.2.2 — диагностика АРМ', 'arm_info 1.2.3 — диагностика АРМ', 1)
s=rep(s, 'ARM_INFO_VERSION="1.2.2"', 'ARM_INFO_VERSION="1.2.3"', 'core version')
s=rep(s, 'enterprise-profile-dispatch-v1.2.2', 'enterprise-profile-dispatch-v1.2.3', 'dispatch marker')
s=rep(s, '# arm_info enterprise profiles — v1.2.2', '# arm_info enterprise profiles — v1.2.3', 'enterprise comment')
s=rep(s, 'VERSION="1.2.2"', 'VERSION="1.2.3"', 'enterprise version')
s=rep(s, 'arm_info enterprise profiles 1.2.2', 'arm_info enterprise profiles 1.2.3', 'enterprise help')

old_root = '''ROOT_DEV=$(findmnt -no SOURCE / 2>/dev/null); [ -z "$ROOT_DEV" ]&&ROOT_DEV="-"
ROOT_USE=$(df -P / 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}'); ROOT_INODE_USE=$(df -Pi / 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}')'''
new_root = '''ROOT_DEV=$(findmnt -no SOURCE / 2>/dev/null); [ -z "$ROOT_DEV" ]&&ROOT_DEV="-"

# Физический накопитель, на котором находится корневая ФС, является приоритетным.
# Для LVM/dm-crypt/device-mapper идём по цепочке parents до TYPE=disk.
ROOT_BLOCK="$ROOT_DEV"
if [[ "$ROOT_BLOCK" == /dev/* ]]; then ROOT_BLOCK=$(readlink -f "$ROOT_BLOCK" 2>/dev/null || printf '%s' "$ROOT_BLOCK"); fi
SYSTEM_DISKS=""
if command -v lsblk >/dev/null 2>&1 && [[ "$ROOT_BLOCK" == /dev/* ]]; then
    SYSTEM_DISKS=$(lsblk -sno NAME,TYPE "$ROOT_BLOCK" 2>/dev/null | awk '$2=="disk"{print $1}' | sort -u)
fi
if [[ -z "$SYSTEM_DISKS" ]] && command -v lsblk >/dev/null 2>&1; then
    ROOT_MAJMIN=$(findmnt -no MAJ:MIN / 2>/dev/null || true)
    if [[ -n "$ROOT_MAJMIN" ]]; then
        ROOT_NODE=$(lsblk -rno NAME,TYPE,MAJ:MIN 2>/dev/null | awk -v mm="$ROOT_MAJMIN" '$3==mm{print "/dev/"$1; exit}')
        [[ -n "$ROOT_NODE" ]] && SYSTEM_DISKS=$(lsblk -sno NAME,TYPE "$ROOT_NODE" 2>/dev/null | awk '$2=="disk"{print $1}' | sort -u)
    fi
fi
SYSTEM_DISK_TEXT=$(printf '%s\n' "$SYSTEM_DISKS" | sed '/^$/d' | paste -sd ',' -)
[ -z "$SYSTEM_DISK_TEXT" ] && SYSTEM_DISK_TEXT="Не определён"

is_system_disk() {
    local n=$1
    printf '%s\n' "$SYSTEM_DISKS" | grep -Fxq -- "$n"
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

ROOT_USE=$(df -P / 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}'); ROOT_INODE_USE=$(df -Pi / 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}')'''
s=rep(s, old_root, new_root, 'root disk resolver')

s=rep(s,
'''LOCAL_FS_COUNT=0; LOCAL_RO_COUNT=0; FS_WORST_USE=$ROOT_USE; FS_WORST_USE_MOUNT=/; FS_WORST_INODE=$ROOT_INODE_USE; FS_WORST_INODE_MOUNT=/; FS_RO_MOUNTS=(); LOCAL_FS_ROWS=()''',
'''LOCAL_FS_COUNT=0; REMOVABLE_FS_COUNT=0; LOCAL_RO_COUNT=0; FS_WORST_USE=$ROOT_USE; FS_WORST_USE_MOUNT=/; FS_WORST_INODE=$ROOT_INODE_USE; FS_WORST_INODE_MOUNT=/; FS_RO_MOUNTS=(); LOCAL_FS_ROWS=()''',
'fs counters')

s=rep(s,
'''    RO=0; findmnt -no OPTIONS --target "$MNT" 2>/dev/null | grep -Eq '(^|,)ro(,|$)'&&RO=1
    LOCAL_FS_COUNT=$((LOCAL_FS_COUNT+1)); ((USE>FS_WORST_USE))&&{ FS_WORST_USE=$USE; FS_WORST_USE_MOUNT="$MNT"; }; ((INO>FS_WORST_INODE))&&{ FS_WORST_INODE=$INO; FS_WORST_INODE_MOUNT="$MNT"; }''',
'''    RO=0; findmnt -no OPTIONS --target "$MNT" 2>/dev/null | grep -Eq '(^|,)ro(,|$)'&&RO=1
    if [ "$MNT" != / ] && mount_is_removable "$MNT"; then
        REMOVABLE_FS_COUNT=$((REMOVABLE_FS_COUNT+1))
        continue
    fi
    LOCAL_FS_COUNT=$((LOCAL_FS_COUNT+1)); ((USE>FS_WORST_USE))&&{ FS_WORST_USE=$USE; FS_WORST_USE_MOUNT="$MNT"; }; ((INO>FS_WORST_INODE))&&{ FS_WORST_INODE=$INO; FS_WORST_INODE_MOUNT="$MNT"; }''',
'fs removable exclusion')

s=rep(s,
'DISK_ROWS=(); DISK_SELFTEST_ROWS=(); DISK_WORST_SCORE=100; FIXED_DISKS=0; MAX_DISK_HOURS=0; SMART_UNKNOWN_COUNT=0',
'DISK_ROWS=(); DISK_SYSTEM_ROWS=(); DISK_FIXED_ROWS=(); DISK_REMOVABLE_ROWS=(); DISK_OPTICAL_ROWS=(); DISK_SELFTEST_ROWS=(); DISK_WORST_SCORE=100; SYSTEM_DISK_SCORE=100; SECONDARY_WORST_KNOWN_SCORE=100; FIXED_DISKS=0; SYSTEM_DISK_COUNT=0; SECONDARY_FIXED_DISKS=0; SECONDARY_KNOWN_COUNT=0; REMOVABLE_DISKS=0; MAX_DISK_HOURS=0; SYSTEM_MAX_DISK_HOURS=0; SMART_UNKNOWN_COUNT=0; SYSTEM_SMART_UNKNOWN_COUNT=0; SECONDARY_CRITICAL=0',
'disk counters')

s=rep(s,
'''    if [[ "$TYPE" = rom || "$NAME" = sr* ]]; then DISK_ROWS+=("$NAME|CD/DVD||$MODEL|-|-|-|-"); continue; fi
    FIXED_DISKS=$((FIXED_DISKS+1)); DISK_SCORE=100; RESOURCE="-"; SMART="Н/Д"; TEMP="-"; HOURS="-"; REALLOC=0; PENDING=0; UNCORR=0; MEDIAERR=0; CRITWARN=0
    if [[ "$NAME" = nvme* ]]; then DISK_TYPE="NVMe SSD"; elif [ "$ROTA" = 0 ]; then DISK_TYPE=SSD; else DISK_TYPE=HDD; fi''',
'''    if [[ "$TYPE" = rom || "$NAME" = sr* ]]; then DISK_OPTICAL_ROWS+=("$NAME|Оптический|CD/DVD||$MODEL|-|-|-|-"); continue; fi
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
    if [[ "$NAME" = nvme* ]]; then DISK_TYPE="NVMe SSD"; elif [ "$ROTA" = 0 ]; then DISK_TYPE=SSD; else DISK_TYPE=HDD; fi''',
'disk classification')

s=rep(s,
'''        if echo "$SMART_H"|grep -Eqi 'PASSED|SMART.*OK'; then SMART=OK; elif echo "$SMART_H"|grep -Eqi 'FAILED|SMART.*BAD'; then SMART=FAIL; DISK_SCORE=0; else SMART="Н/Д"; SMART_UNKNOWN_COUNT=$((SMART_UNKNOWN_COUNT+1)); fi''',
'''        if echo "$SMART_H"|grep -Eqi 'PASSED|SMART.*OK'; then SMART=OK; elif echo "$SMART_H"|grep -Eqi 'FAILED|SMART.*BAD'; then SMART=FAIL; DISK_SCORE=0; else SMART="Н/Д"; SMART_UNKNOWN_COUNT=$((SMART_UNKNOWN_COUNT+1)); [[ "$DISK_ROLE" == "Системный" ]] && SYSTEM_SMART_UNKNOWN_COUNT=$((SYSTEM_SMART_UNKNOWN_COUNT+1)); fi''',
'smart unknown priority')

s=rep(s,
'''    DISK_SCORE=$(clamp_score "$DISK_SCORE"); ((DISK_SCORE<DISK_WORST_SCORE))&&DISK_WORST_SCORE=$DISK_SCORE; [[ "$HOURS" =~ ^[0-9]+$ ]]&&((HOURS>MAX_DISK_HOURS))&&MAX_DISK_HOURS=$HOURS
    DISK_ROWS+=("$NAME|$DISK_TYPE|$SIZE|$MODEL|$RESOURCE|$SMART|$TEMP|$HOURS")''',
'''    DISK_SCORE=$(clamp_score "$DISK_SCORE")
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
    fi''',
'disk scoring roles')

s=rep(s,
'''done < <(lsblk -dn -o NAME,TYPE,SIZE,ROTA,MODEL 2>/dev/null)
((FIXED_DISKS==0))&&DISK_WORST_SCORE=70
((RAID_DEGRADED==1)) && DISK_WORST_SCORE=$(min_score "$DISK_WORST_SCORE" 30)

# -------------------- БАЛЛЫ --------------------
STORAGE_SCORE=$DISK_WORST_SCORE''',
'''done < <(lsblk -dn -o NAME,TYPE,SIZE,ROTA,MODEL 2>/dev/null)
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

# -------------------- БАЛЛЫ --------------------''',
'storage scoring')

old_age = '''DISK_AGE_MONTHS=-1; DISK_AGE_YEARS=-1; ((MAX_DISK_HOURS>0))&&{ DISK_AGE_MONTHS=$((MAX_DISK_HOURS*12/8760)); DISK_AGE_YEARS=$((DISK_AGE_MONTHS/12)); }
OS_AGE_MONTHS=-1; ((AGE_DAYS>=0))&&OS_AGE_MONTHS=$((AGE_DAYS*12/365))
SYSTEM_AGE_MONTHS=-1; AGE_SOURCE="Не определён"
if ((DISK_AGE_MONTHS>=0 && OS_AGE_MONTHS>=0)); then if ((DISK_AGE_MONTHS>=OS_AGE_MONTHS)); then SYSTEM_AGE_MONTHS=$DISK_AGE_MONTHS; AGE_SOURCE="макс. наработка накопителя"; else SYSTEM_AGE_MONTHS=$OS_AGE_MONTHS; AGE_SOURCE="возраст текущей установки ОС"; fi
elif ((DISK_AGE_MONTHS>=0)); then SYSTEM_AGE_MONTHS=$DISK_AGE_MONTHS; AGE_SOURCE="макс. наработка накопителя"; elif ((OS_AGE_MONTHS>=0)); then SYSTEM_AGE_MONTHS=$OS_AGE_MONTHS; AGE_SOURCE="возраст текущей установки ОС"; fi'''
new_age = '''AGE_DISK_HOURS=$MAX_DISK_HOURS; AGE_DISK_SOURCE="макс. наработка внутреннего накопителя"
if ((SYSTEM_MAX_DISK_HOURS>0)); then AGE_DISK_HOURS=$SYSTEM_MAX_DISK_HOURS; AGE_DISK_SOURCE="наработка системного накопителя"; fi
DISK_AGE_MONTHS=-1; DISK_AGE_YEARS=-1; ((AGE_DISK_HOURS>0))&&{ DISK_AGE_MONTHS=$((AGE_DISK_HOURS*12/8760)); DISK_AGE_YEARS=$((DISK_AGE_MONTHS/12)); }
OS_AGE_MONTHS=-1; ((AGE_DAYS>=0))&&OS_AGE_MONTHS=$((AGE_DAYS*12/365))
SYSTEM_AGE_MONTHS=-1; AGE_SOURCE="Не определён"
if ((DISK_AGE_MONTHS>=0 && OS_AGE_MONTHS>=0)); then if ((DISK_AGE_MONTHS>=OS_AGE_MONTHS)); then SYSTEM_AGE_MONTHS=$DISK_AGE_MONTHS; AGE_SOURCE="$AGE_DISK_SOURCE"; else SYSTEM_AGE_MONTHS=$OS_AGE_MONTHS; AGE_SOURCE="возраст текущей установки ОС"; fi
elif ((DISK_AGE_MONTHS>=0)); then SYSTEM_AGE_MONTHS=$DISK_AGE_MONTHS; AGE_SOURCE="$AGE_DISK_SOURCE"; elif ((OS_AGE_MONTHS>=0)); then SYSTEM_AGE_MONTHS=$OS_AGE_MONTHS; AGE_SOURCE="возраст текущей установки ОС"; fi'''
s=rep(s, old_age, new_age, 'age system disk priority')

old_known = '''STORAGE_KNOWN=1
if ! command -v smartctl >/dev/null 2>&1 && ((FIXED_DISKS>0)); then STORAGE_KNOWN=0; fi
((SMART_UNKNOWN_COUNT>0))&&STORAGE_KNOWN=0'''
new_known = '''STORAGE_KNOWN=1
if ((SYSTEM_DISK_COUNT>0)); then
    if ! command -v smartctl >/dev/null 2>&1 || ((SYSTEM_SMART_UNKNOWN_COUNT>0)); then STORAGE_KNOWN=0; fi
else
    if ! command -v smartctl >/dev/null 2>&1 && ((FIXED_DISKS>0)); then STORAGE_KNOWN=0; fi
    ((SMART_UNKNOWN_COUNT>0))&&STORAGE_KNOWN=0
fi'''
s=rep(s, old_known, new_known, 'storage known')

old_conf = '''if ! command -v smartctl >/dev/null 2>&1 && ((FIXED_DISKS>0)); then CONFIDENCE=$((CONFIDENCE-25)); CONFIDENCE_NOTES+=("нет smartctl"); elif ((SMART_UNKNOWN_COUNT>0)); then CONFIDENCE=$((CONFIDENCE-15)); CONFIDENCE_NOTES+=("SMART частично недоступен"); fi'''
new_conf = '''if ! command -v smartctl >/dev/null 2>&1 && ((FIXED_DISKS>0)); then
    CONFIDENCE=$((CONFIDENCE-25)); CONFIDENCE_NOTES+=("нет smartctl для внутренних накопителей")
elif ((SYSTEM_DISK_COUNT>0 && SYSTEM_SMART_UNKNOWN_COUNT>0)); then
    CONFIDENCE=$((CONFIDENCE-15)); CONFIDENCE_NOTES+=("SMART системного накопителя недоступен")
elif ((SYSTEM_DISK_COUNT==0 && SMART_UNKNOWN_COUNT>0)); then
    CONFIDENCE=$((CONFIDENCE-15)); CONFIDENCE_NOTES+=("SMART внутренних накопителей частично недоступен")
elif ((SMART_UNKNOWN_COUNT>0)); then
    CONFIDENCE_NOTES+=("SMART части дополнительных накопителей недоступен (без штрафа полноты)")
fi'''
s=rep(s, old_conf, new_conf, 'confidence priority')

s=rep(s,
'''if ((ROOT_RO==1 || STORAGE_SCORE<30 || ROOT_USE>=98 || RAID_DEGRADED==1 || ECC_UE>0)); then STATE="КРИТИЧЕСКОЕ"; elif ((OOM_DETECTED==1 || HW_ERR_COUNT>0 || ROOT_USE>=95 || ACTIVE_NET==0)); then [ "$STATE" = "ОТЛИЧНОЕ" ]||[ "$STATE" = "ХОРОШЕЕ" ]&&STATE="ТРЕБУЕТ ВНИМАНИЯ"; fi''',
'''if ((ROOT_RO==1 || (SYSTEM_DISK_COUNT>0 && SYSTEM_DISK_SCORE<30) || (SYSTEM_DISK_COUNT==0 && STORAGE_SCORE<30) || ROOT_USE>=98 || RAID_DEGRADED==1 || ECC_UE>0)); then STATE="КРИТИЧЕСКОЕ"; elif ((SECONDARY_CRITICAL==1 || OOM_DETECTED==1 || HW_ERR_COUNT>0 || ROOT_USE>=95 || ACTIVE_NET==0)); then [ "$STATE" = "ОТЛИЧНОЕ" ]||[ "$STATE" = "ХОРОШЕЕ" ]&&STATE="ТРЕБУЕТ ВНИМАНИЯ"; fi''',
'state storage priority')

old_rec='''if ! command -v smartctl >/dev/null 2>&1 && ((FIXED_DISKS>0)); then add_rec "ПРОВЕРКА" "SMART накопителей не проверен" "Без SMART нельзя достоверно оценить износ SSD/NVMe и признаки деградации HDD." "Установить smartmontools и повторить диагностику." "dnf install smartmontools"; elif ((SMART_UNKNOWN_COUNT>0)); then add_rec "ПРОВЕРКА" "SMART частично недоступен" "Состояние части накопителей оценено не полностью." "Проверить контроллер/поддержку SMART." "smartctl --scan-open"; fi'''
new_rec='''if ! command -v smartctl >/dev/null 2>&1 && ((FIXED_DISKS>0)); then add_rec "ПРОВЕРКА" "SMART внутренних накопителей не проверен" "Без SMART нельзя достоверно оценить системный SSD/NVMe/HDD." "Установить smartmontools и повторить диагностику." "dnf install smartmontools"; elif ((SYSTEM_SMART_UNKNOWN_COUNT>0)); then add_rec "ПРОВЕРКА" "SMART системного накопителя недоступен" "Основной накопитель АРМ оценён не полностью; съёмные носители на этот статус не влияют." "Проверить поддержку SMART системного устройства и повторить диагностику." "smartctl --scan-open"; elif ((SMART_UNKNOWN_COUNT>0)); then add_rec "ПРОВЕРКА" "SMART дополнительных накопителей частично недоступен" "Системный накопитель имеет приоритет; неполные данные относятся к дополнительным внутренним дискам." "При необходимости проверить дополнительные диски отдельно." "smartctl --scan-open"; fi'''
s=rep(s, old_rec, new_rec, 'smart rec priority')

s=rep(s,
'''section "НАКОПИТЕЛИ"
{ echo "Диск|Тип|Размер|Модель|Ресурс|SMART|°C|Часы"; if ((${#DISK_ROWS[@]})); then printf '%s\\n' "${DISK_ROWS[@]}"; else echo "-|-|-|Не найдены|-|-|-|-"; fi; } | table''',
'''section "НАКОПИТЕЛИ"
echo "Системный накопитель: $SYSTEM_DISK_TEXT"
{ echo "Диск|Роль|Тип|Размер|Модель|Ресурс|SMART|°C|Часы"; if ((${#DISK_ROWS[@]})); then printf '%s\\n' "${DISK_ROWS[@]}"; else echo "-|-|-|-|Не найдены|-|-|-|-"; fi; } | table''',
'disk table')

s=rep(s,
'''section "ФАЙЛОВЫЕ СИСТЕМЫ"
{ echo "Корневой раздел|$ROOT_DEV"; echo "Размер / занято / свободно|$ROOT_SIZE / $ROOT_USED / $ROOT_FREE"; echo "Корень: место / inode|${ROOT_USE}% / ${ROOT_INODE_USE}%"; echo "Локальных ФС проверено|$LOCAL_FS_COUNT"; echo "Макс. заполнение|${FS_WORST_USE}% на $FS_WORST_USE_MOUNT"; echo "Использование inode|${FS_WORST_INODE}% на $FS_WORST_INODE_MOUNT"; } | table''',
'''section "ФАЙЛОВЫЕ СИСТЕМЫ"
{ echo "Корневой раздел|$ROOT_DEV"; echo "Размер / занято / свободно|$ROOT_SIZE / $ROOT_USED / $ROOT_FREE"; echo "Корень: место / inode|${ROOT_USE}% / ${ROOT_INODE_USE}%"; echo "Локальных ФС проверено|$LOCAL_FS_COUNT"; echo "Съёмных ФС вне индекса|$REMOVABLE_FS_COUNT"; echo "Макс. заполнение|${FS_WORST_USE}% на $FS_WORST_USE_MOUNT"; echo "Использование inode|${FS_WORST_INODE}% на $FS_WORST_INODE_MOUNT"; } | table''',
'fs report')

old_smart='''SMART_SUMMARY=OK; if ((FIXED_DISKS==0)); then SMART_SUMMARY="Н/Д"; elif ! command -v smartctl >/dev/null 2>&1; then SMART_SUMMARY="Н/Д (smartctl отсутствует)"; elif ((STORAGE_SCORE==0)); then SMART_SUMMARY=FAIL; elif ((SMART_UNKNOWN_COUNT>0)); then SMART_SUMMARY="Частично / Н/Д"; fi'''
new_smart='''SMART_SUMMARY=OK; if ((FIXED_DISKS==0)); then SMART_SUMMARY="Н/Д"; elif ! command -v smartctl >/dev/null 2>&1; then SMART_SUMMARY="Н/Д (smartctl отсутствует)"; elif ((SYSTEM_DISK_COUNT>0 && SYSTEM_DISK_SCORE==0)); then SMART_SUMMARY=FAIL; elif ((SYSTEM_DISK_COUNT>0 && SYSTEM_SMART_UNKNOWN_COUNT>0)); then SMART_SUMMARY="Н/Д (системный)"; elif ((SYSTEM_DISK_COUNT==0 && SMART_UNKNOWN_COUNT>0)); then SMART_SUMMARY="Частично / Н/Д"; fi'''
s=rep(s, old_smart, new_smart, 'smart summary')
s=rep(s,
'''{ echo "SMART накопителей|$SMART_SUMMARY"; echo "Файловые системы|макс. ${FS_WORST_USE}% на $FS_WORST_USE_MOUNT; inode ${FS_WORST_INODE}% на $FS_WORST_INODE_MOUNT";''',
'''{ echo "SMART системного накопителя|$SMART_SUMMARY"; echo "Съёмных накопителей вне индекса|$REMOVABLE_DISKS"; echo "Файловые системы|макс. ${FS_WORST_USE}% на $FS_WORST_USE_MOUNT; inode ${FS_WORST_INODE}% на $FS_WORST_INODE_MOUNT";''',
'key storage summary')

s=rep(s,
'''    printf '  "storage": {"score":%s,"known":%s,"fixed_disks":%s,"smart_unknown":%s},\\n' \\
        "$STORAGE_SCORE" "$([ "$STORAGE_KNOWN" -eq 1 ] && echo true || echo false)" "$FIXED_DISKS" "$SMART_UNKNOWN_COUNT"''',
'''    printf '  "storage": {"score":%s,"known":%s,"system_disks":%s,"fixed_disks":%s,"secondary_fixed_disks":%s,"removable_disks":%s,"smart_unknown":%s,"system_smart_unknown":%s},\\n' \\
        "$STORAGE_SCORE" "$([ "$STORAGE_KNOWN" -eq 1 ] && echo true || echo false)" "$SYSTEM_DISK_COUNT" "$FIXED_DISKS" "$SECONDARY_FIXED_DISKS" "$REMOVABLE_DISKS" "$SMART_UNKNOWN_COUNT" "$SYSTEM_SMART_UNKNOWN_COUNT"''',
'json storage')

write(p,s)

# -------- version --------
write(Path('VERSION'), '1.2.3\n')

# -------- RPM spec --------
p=Path('packaging/arm_info.spec'); x=read(p)
x=rep(x, 'Version:        1.2.2', 'Version:        1.2.3', 'rpm version')
marker='%changelog\n'
entry='''%changelog\n* Wed Sep 16 2026 NewMishka - 1.2.3-1\n- Prioritize the physical system disk in storage health and completeness\n- Classify removable USB media separately and exclude them from score/SMART completeness\n- Exclude removable filesystems from max-fill/inode scoring\n\n'''
x=rep(x, marker, entry, 'rpm changelog')
write(p,x)

# -------- CHANGELOG --------
p=Path('CHANGELOG.md'); x=read(p)
entry='''# Changelog\n\n## 1.2.3 — 2026-09-16\n\n### Changed\n- Накопитель, содержащий корневую файловую систему, определяется через `findmnt` + `lsblk` и получает роль **Системный**.\n- Системный накопитель выводится первым и имеет 80% веса внутри storage-группы; известный худший дополнительный внутренний диск — 20%.\n- Съёмные/USB-накопители отображаются отдельно как `Съёмный (вне индекса)` и не влияют на storage score, SMART completeness, возраст АРМ и рекомендации по SMART.\n- Файловые системы на съёмных носителях исключены из `Макс. заполнение`, inode-score и read-only штрафов; корневая и внутренние ФС остаются приоритетными.\n- Наработку/возраст накопителя по возможности определяет системный диск; при отсутствии данных используется внутренний fallback.\n- JSON storage дополнен счётчиками системных, дополнительных и съёмных накопителей.\n\n## 1.2.2 — 2026-09-16\n'''
x=rep(x, '# Changelog\n\n## 1.2.2 — 2026-09-16\n', entry, 'changelog 1.2.3')
write(p,x)

# -------- README --------
p=Path('README.md'); x=read(p)
x=x.replace('Начиная с версии **1.2.2** вся базовая и корпоративная диагностика находится в одном `arm_info.sh`.', 'Начиная с версии **1.2.1** вся базовая и корпоративная диагностика находится в одном `arm_info.sh`.', 1)
x=x.replace('`arm_info 1.2.2` содержит встроенные профили', '`arm_info 1.2.3` содержит встроенные профили', 1)
x=x.replace('Текущая версия: **1.2.2**.', 'Текущая версия: **1.2.3**.', 1)
anchor='''Стандартный анализ также использует выровненные рекомендации. Температура CPU в пользовательском отчёте выводится как медиана (`NN°C (медиана)`) без одновременного значения максимума.\n'''
insert=anchor+'''\nВ **1.2.3** анализ накопителей ориентирован прежде всего на диск, с которого работает корневая файловая система. Он помечается как `Системный` и выводится первым. Подключённые USB/съёмные носители показываются отдельно, но не снижают storage score и полноту SMART. Их файловые системы также не подменяют показатель `Макс. заполнение` системных/внутренних ФС.\n'''
x=rep(x, anchor, insert, 'readme storage note')
write(p,x)

# -------- SCORING --------
p=Path('docs/SCORING.md'); x=read(p)
old='''### Накопители\n\nУчитываются SMART health, ресурс SSD/NVMe, температура, Power-On Hours, reallocated/pending/uncorrectable, NVMe Critical Warning/Media Errors и состояние software RAID. Худший фиксированный накопитель определяет storage score. Неизвестный SMART снижает полноту диагностики.\n'''
new='''### Накопители\n\nУчитываются SMART health, ресурс SSD/NVMe, температура, Power-On Hours, reallocated/pending/uncorrectable, NVMe Critical Warning/Media Errors и состояние software RAID. Начиная с 1.2.3 физический накопитель, на котором находится корневая ФС, определяется через `findmnt`/`lsblk` и считается системным. Его оценка имеет 80% веса внутри storage-группы; худший **известный** дополнительный внутренний диск — 20%. Если дополнительных внутренних дисков нет или их SMART неизвестен, storage score определяется системным накопителем.\n\nСъёмные/USB-носители выводятся для инвентаризации, но не участвуют в storage score, SMART completeness и эксплуатационном возрасте АРМ. Если системный диск определить не удалось, применяется прежний fallback по внутренним несъёмным дискам.\n'''
x=rep(x, old, new, 'scoring storage')
oldfs='''### Файловые системы\n\nПроверяются локальные FS, заполнение и inode. По умолчанию пороги задаются `FS_WARN=80`, `FS_HIGH=90`, `FS_CRIT=95`, `INODE_WARN=80`. Read-only корневая FS считается критической.\n'''
newfs='''### Файловые системы\n\nПроверяются корневая и локальные файловые системы на внутренних накопителях: заполнение, inode и read-only. ФС на съёмных/USB-носителях не участвуют в `Макс. заполнение`, inode-score и read-only штрафах, чтобы подключённая флешка не меняла техническую оценку АРМ. По умолчанию пороги задаются `FS_WARN=80`, `FS_HIGH=90`, `FS_CRIT=95`, `INODE_WARN=80`. Read-only корневая FS считается критической.\n'''
x=rep(x, oldfs, newfs, 'scoring fs')
write(p,x)

# -------- USAGE --------
p=Path('docs/USAGE.md'); x=read(p)
anchor='''Полная инвентаризация RPM-пакетов запускается отдельно:\n\n```bash\nsudo arm_info --profile software\n```\n'''
if anchor in x:
    x=x.replace(anchor, anchor+'''\n## Приоритет системного накопителя\n\nНачиная с 1.2.3 `arm_info` определяет физический диск корневой ФС и помечает его как `Системный`. Подключённые USB/съёмные носители отображаются в таблице, но исключены из storage score, SMART completeness, возраста АРМ и filesystem max/inode. Это позволяет диагностировать рабочую станцию независимо от подключённой флешки.\n''',1)
else:
    x += '''\n## Приоритет системного накопителя\n\nНачиная с 1.2.3 `arm_info` определяет физический диск корневой ФС и помечает его как `Системный`. USB/съёмные носители показываются отдельно и не влияют на технический индекс.\n'''
write(p,x)

# -------- TECHNICAL --------
p=Path('docs/TECHNICAL.md'); x=read(p)
anchor='''- `lsblk`, `smartctl`;\n'''
if anchor in x:
    x=x.replace(anchor, '''- `lsblk`, `smartctl`;\n- `findmnt` + `lsblk -s` для определения физического системного диска через LVM/device-mapper;\n- `/sys/class/block/*/removable` и `lsblk TRAN` для отделения съёмных/USB-носителей;\n''',1)
principle='''6. Конфигурация парсится whitelist-механизмом, без `source`.\n'''
if principle in x:
    x=x.replace(principle, principle+'''7. Системный накопитель имеет приоритет в storage score/completeness; removable media не должны менять оценку АРМ.\n''',1)
write(p,x)

# -------- COMPATIBILITY --------
p=Path('docs/COMPATIBILITY.md'); x=read(p)
x += '''\n## Накопители и съёмные носители\n\nВ 1.2.3 системный физический диск определяется по цепочке корневой ФС через `findmnt`/`lsblk -s`, включая типовой LVM/device-mapper. Признак съёмности берётся из `/sys/class/block/<dev>/removable` и transport `lsblk -o TRAN`; для типовых автомонтирований `/run/media`/`/media` используется fallback. Системный диск никогда не исключается из оценки только из-за transport/removable-флага (например, при загрузке ОС с внешнего носителя).\n'''
write(p,x)

# -------- TESTING --------
p=Path('docs/TESTING.md'); x=read(p)
x += '''\n## Storage priority 1.2.3\n\nПеред релизом дополнительно проверить: (1) обычный АРМ только с системным SSD/NVMe; (2) тот же АРМ с подключённой USB-флешкой; (3) LVM/device-mapper root. Подключение флешки не должно менять storage score/SMART completeness и `Макс. заполнение`; в таблице она должна иметь роль `Съёмный (вне индекса)`, а системный диск — `Системный`.\n'''
write(p,x)

# -------- PRE RELEASE --------
p=Path('docs/PRE_RELEASE_CHECKLIST.md'); x=read(p)
x=re.sub(r'^# Pre-release checklist — v[^\n]+', '# Pre-release checklist — v1.2.3', x, count=1, flags=re.M)
insert='''- [ ] Системный физический диск корректно определяется через root → LVM/device-mapper → disk.\n- [ ] USB/съёмный диск не влияет на storage score, SMART completeness, возраст и max filesystem usage.\n- [ ] В таблице накопителей системный диск идёт первым; removable помечен `Съёмный (вне индекса)`.\n'''
needle='- [ ] Privacy mode не раскрывает hostname/IP/MAC/DNS/domain и credentials в printer URI.\n'
if needle in x: x=x.replace(needle, needle+insert,1)
write(p,x)

# -------- release notes --------
Path('docs/releases/v1.2.3.md').write_text('''# arm_info 1.2.3\n\nВерсия 1.2.3 исправляет оценку накопителей при подключённых USB/съёмных носителях и делает системный диск приоритетным.\n\n- физический диск корневой ФС определяется через `findmnt` + `lsblk -s`, включая LVM/device-mapper;\n- системный диск выводится первым с ролью `Системный`;\n- USB/съёмные носители имеют роль `Съёмный (вне индекса)` и тип `USB-накопитель`/`Съёмный накопитель`;\n- removable media не влияют на storage score, SMART completeness, эксплуатационный возраст и SMART-рекомендации;\n- файловые системы съёмных носителей не участвуют в `Макс. заполнение`, inode-score и read-only штрафах;\n- системный накопитель имеет 80% веса внутри storage-группы, худший известный дополнительный внутренний — 20%;\n- JSON storage содержит отдельные счётчики системных, дополнительных и съёмных накопителей.\n\nЦель изменения: подключённая флешка не должна ухудшать оценку технического состояния АРМ или подменять показатели системного диска.\n\nРекомендуемый smoke-test перед релизом:\n\n```bash\nsudo bash arm_info.sh\nsudo bash arm_info.sh --privacy\n```\n\nПовторить оба запуска с подключённой USB-флешкой и убедиться, что итоговый storage score/SMART completeness не изменились из-за removable media.\n''', encoding='utf-8')

# -------- sample report --------
p=Path('examples/sample-report.txt'); x=read(p)
if 'НАКОПИТЕЛИ' not in x:
    insert='''\nНАКОПИТЕЛИ\n--------------------------------------------------------------------------------------------\nСистемный накопитель: nvme0n1\nДиск     Роль                    Тип              Размер  Модель             Ресурс SMART           °C Часы\nnvme0n1  Системный               NVMe SSD         476,9G  ADATA SX6000LNP    97%    OK              47 1554\nsda      Съёмный (вне индекса)  USB-накопитель   28,9G   DataTraveler 2.0   -      не учитывается  -  -\n\n'''
    x=x.replace('\nФАЙЛОВЫЕ СИСТЕМЫ\n', insert+'ФАЙЛОВЫЕ СИСТЕМЫ\n',1)
x=x.replace('Макс. заполнение    15% на /', 'Съёмных ФС вне индекса 1\nМакс. заполнение    15% на /')
write(p,x)

# -------- tests --------
p=Path('tests/test_cli.sh'); x=read(p)
needle='''grep -Fq 'Температура CPU|${CPU_TEMP}°C (медиана)' "$SCRIPT" || die "CPU median label"\n'''
checks='''grep -q 'SYSTEM_DISKS=' "$SCRIPT" || die "system disk resolver"\ngrep -q 'disk_is_removable' "$SCRIPT" || die "removable disk classifier"\ngrep -q 'USB-накопитель' "$SCRIPT" || die "USB disk type"\ngrep -q 'Съёмный (вне индекса)' "$SCRIPT" || die "removable disk role"\ngrep -q 'SYSTEM_DISK_SCORE' "$SCRIPT" || die "system disk priority score"\ngrep -q 'SECONDARY_WORST_KNOWN_SCORE' "$SCRIPT" || die "secondary disk weighted score"\ngrep -q 'REMOVABLE_FS_COUNT' "$SCRIPT" || die "removable filesystem exclusion"\ngrep -q 'Съёмных ФС вне индекса' "$SCRIPT" || die "removable filesystem report"\n'''
if needle in x: x=x.replace(needle, needle+checks,1)
else: raise SystemExit('test_cli anchor missing')
write(p,x)

# -------- CI docs contract --------
p=Path('.github/workflows/ci.yml'); x=read(p)
needle='''          grep -q 'SHA256SUMS' README.md\n'''
extra='''          grep -q '1.2.3' docs/releases/v1.2.3.md\n          grep -q 'Съёмный (вне индекса)' docs/SCORING.md docs/USAGE.md docs/TESTING.md\n          grep -q 'SYSTEM_DISKS=' arm_info.sh\n'''
if needle in x: x=x.replace(needle, needle+extra,1)
else:
    # Add to Report and documentation contract block before RPM smoke step.
    x=x.replace('      - name: RPM build smoke test\n', '          grep -q \'1.2.3\' docs/releases/v1.2.3.md\n          grep -q \'Съёмный (вне индекса)\' docs/SCORING.md docs/USAGE.md docs/TESTING.md\n          grep -q \'SYSTEM_DISKS=\' arm_info.sh\n      - name: RPM build smoke test\n',1)
write(Path('.github/workflows/ci.yml'),x)

print('v1.2.3 storage priority patch applied')
