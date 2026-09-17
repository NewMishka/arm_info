from pathlib import Path

p = Path('arm_info.sh')
s = p.read_text(encoding='utf-8')

anchor = 'clamp_score() { local v="$1"; ((v<0))&&v=0; ((v>100))&&v=100; echo "$v"; }\n'
helpers = r'''

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
'''
if 'format_uptime_ru() {' not in s:
    if anchor not in s:
        raise SystemExit('helper anchor not found')
    s = s.replace(anchor, anchor + helpers, 1)

old = "UPTIME=$(LC_ALL=C uptime -p 2>/dev/null | sed 's/^up //'); [ -z \"$UPTIME\" ] && UPTIME=\"Не определено\""
new = 'UPTIME=$(format_uptime_ru)'
if old not in s:
    raise SystemExit('old uptime expression not found')
s = s.replace(old, new, 1)

old = 'SYSTEM_AGE_TEXT="Не определён"; ((SYSTEM_AGE_MONTHS>=0))&&SYSTEM_AGE_TEXT=$(awk -v m="$SYSTEM_AGE_MONTHS" \'BEGIN{printf "%.1f",m/12}\')'
new = 'SYSTEM_AGE_TEXT="Не определён"; ((SYSTEM_AGE_MONTHS>=0))&&SYSTEM_AGE_TEXT=$(format_years_ru_from_months "$SYSTEM_AGE_MONTHS")'
if old not in s:
    raise SystemExit('system age formatter not found')
s = s.replace(old, new, 1)

old = 'echo "Хост|$HOST_DISPLAY"; echo "ОС|$OS"; echo "Модель системы|$SYSTEM_VENDOR $SYSTEM_PRODUCT"; echo "Ядро|$KERNEL"; echo "Архитектура|$ARCH"; echo "Установка ОС|$INSTALL_DATE"; ((AGE_YEARS>=0))&&echo "Возраст установки|≈ ${AGE_YEARS} лет"; echo "BIOS|$BIOS_VERSION; дата $BIOS_DATE (справочно)"; ((MAX_DISK_HOURS>0))&&echo "Макс. наработка диска|${MAX_DISK_HOURS} ч"; ((SYSTEM_AGE_MONTHS>=0))&&echo "Эксплуатационный ориентир|≈ ${SYSTEM_AGE_TEXT} лет ($AGE_SOURCE)"; echo "Время работы|$UPTIME"'
new = 'echo "Хост|$HOST_DISPLAY"; echo "ОС|$OS"; echo "Модель системы|$SYSTEM_VENDOR $SYSTEM_PRODUCT"; echo "Ядро|$KERNEL"; echo "Архитектура|$ARCH"; echo "Установка ОС|$INSTALL_DATE"; echo "BIOS|$BIOS_VERSION; дата $BIOS_DATE (справочно)"; ((MAX_DISK_HOURS>0))&&echo "Макс. наработка диска|${MAX_DISK_HOURS} ч"; ((SYSTEM_AGE_MONTHS>=0))&&echo "Эксплуатационный ориентир|≈ ${SYSTEM_AGE_TEXT} ($AGE_SOURCE)"; echo "Время работы|$UPTIME"'
if old not in s:
    raise SystemExit('system report row not found')
s = s.replace(old, new, 1)
s = s.replace('"Эксплуатационный ориентир — около ${SYSTEM_AGE_TEXT} лет"', '"Эксплуатационный ориентир — около ${SYSTEM_AGE_TEXT}"')
p.write_text(s, encoding='utf-8')

t = Path('tests/test_cli.sh')
ts = t.read_text(encoding='utf-8')
test_anchor = '! grep -Fq \'(медиана; максимум ${CPU_TEMP_MAX}°C)\' "$SCRIPT" || die "CPU maximum must not be shown with median"\n'
guards = '''grep -q '^format_uptime_ru() {' "$SCRIPT" || die "Russian uptime formatter missing"\ngrep -q '^format_years_ru_from_months() {' "$SCRIPT" || die "Russian years formatter missing"\ngrep -Fq 'UPTIME=$(format_uptime_ru)' "$SCRIPT" || die "uptime must use Russian formatter"\n! grep -Fq 'uptime -p' "$SCRIPT" || die "English uptime -p output must not be used"\n! grep -Fq 'Возраст установки|' "$SCRIPT" || die "installation age duplicates operational age"\ngrep -Fq 'Эксплуатационный ориентир|≈ ${SYSTEM_AGE_TEXT} ($AGE_SOURCE)' "$SCRIPT" || die "operational age must carry declined unit from formatter"\n'''
if 'Russian uptime formatter missing' not in ts:
    if test_anchor not in ts:
        raise SystemExit('test anchor not found')
    ts = ts.replace(test_anchor, test_anchor + guards, 1)
t.write_text(ts, encoding='utf-8')

r = Path('docs/releases/v1.2.4.md')
rs = r.read_text(encoding='utf-8')
bullet = '- системный блок локализован: uptime формируется из `/proc/uptime` с русским склонением (`1 час 13 минут`, `2 дня 4 часа`), эксплуатационный ориентир выводится как `1 год` / `2 года` / `5 лет` / `2,2 года`, а дублирующая строка «Возраст установки» удалена при сохранении точной даты установки ОС;\n'
marker = '## Release assets\n'
if bullet not in rs:
    if marker not in rs:
        raise SystemExit('release marker not found')
    rs = rs.replace(marker, bullet + '\n' + marker, 1)
r.write_text(rs, encoding='utf-8')
