from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "arm_info.sh"
text = SCRIPT.read_text(encoding="utf-8")

def replace_once(old: str, new: str, name: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{name}: expected 1 match, got {count}")
    text = text.replace(old, new, 1)

# Enterprise/corporate: support explicit no-save and automatic saving for --corp.
replace_once(
    'JSON_MODE=0\nOUTPUT_PATH=""\nCOMPARE_A=""',
    'JSON_MODE=0\nSAVE_REPORT=1\nOUTPUT_PATH=""\nCOMPARE_A=""',
    'enterprise save flag',
)
replace_once(
    '        --json) JSON_MODE=1; shift ;;\n        -o|--output)',
    '        --json) JSON_MODE=1; shift ;;\n        --no-save) SAVE_REPORT=0; shift ;;\n        -o|--output)',
    'enterprise --no-save',
)
replace_once(
    '  arm_info --corp [--privacy] [--json] [-o FILE]\n  arm_info --profile enterprise [--privacy] [--json] [-o FILE]',
    '  arm_info --corp [--privacy] [--json] [--no-save] [-o FILE]\n  arm_info --profile enterprise [--privacy] [--json] [--no-save] [-o FILE]',
    'enterprise usage',
)
old_output = '''if [[ -n $OUTPUT_PATH ]]; then
    OUTDIR=$(dirname -- "$OUTPUT_PATH")
    [[ -d $OUTDIR && -w $OUTDIR ]] || { echo "Ошибка: каталог для отчёта недоступен: $OUTDIR" >&2; exit 73; }
    exec > >(tee "$OUTPUT_PATH")
fi
'''
new_output = '''# Корпоративный профиль (--corp / --profile enterprise) по умолчанию сохраняет
# отчёт так же, как стандартный анализ. Явный -o имеет приоритет; --no-save отключает запись.
if [[ -z $COMPARE_A && $PROFILE == enterprise && -z $OUTPUT_PATH ]] && ((SAVE_REPORT==1)); then
    CORP_EXT=txt
    ((JSON_MODE==1)) && CORP_EXT=json
    CORP_STAMP=$(date '+%Y%m%d_%H%M%S')
    CORP_HOST=$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'ARM')
    CORP_HOST=$(printf '%s' "$CORP_HOST" | tr -c '[:alnum:]_.-' '_')
    if ((PRIVACY)); then
        CORP_NAME="ARM_INFO_CORP_PRIVATE_${CORP_STAMP}.${CORP_EXT}"
    else
        CORP_NAME="ARM_INFO_CORP_${CORP_HOST}_${CORP_STAMP}.${CORP_EXT}"
    fi
    CORP_DIR=$(pwd -P 2>/dev/null || printf '/tmp')
    [[ -d $CORP_DIR && -w $CORP_DIR ]] || CORP_DIR=/tmp
    OUTPUT_PATH="$CORP_DIR/$CORP_NAME"
fi

if [[ -n $OUTPUT_PATH ]] && ((SAVE_REPORT==1)); then
    if [[ -d $OUTPUT_PATH ]]; then
        # Для -o DIR используем то же имя, что и при автоматическом сохранении.
        CORP_EXT=txt
        ((JSON_MODE==1)) && CORP_EXT=json
        CORP_STAMP=$(date '+%Y%m%d_%H%M%S')
        CORP_HOST=$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'ARM')
        CORP_HOST=$(printf '%s' "$CORP_HOST" | tr -c '[:alnum:]_.-' '_')
        if ((PRIVACY)); then CORP_NAME="ARM_INFO_CORP_PRIVATE_${CORP_STAMP}.${CORP_EXT}"
        else CORP_NAME="ARM_INFO_CORP_${CORP_HOST}_${CORP_STAMP}.${CORP_EXT}"; fi
        OUTPUT_PATH="${OUTPUT_PATH%/}/$CORP_NAME"
    fi
    OUTDIR=$(dirname -- "$OUTPUT_PATH")
    [[ -d $OUTDIR && -w $OUTDIR ]] || { echo "Ошибка: каталог для отчёта недоступен: $OUTDIR" >&2; exit 73; }
    exec > >(tee "$OUTPUT_PATH")
fi
'''
replace_once(old_output, new_output, 'enterprise output save block')

# Show save path in human-readable enterprise output only.
replace_once(
    '''    printf 'Дата: %s\\n' "$(date '+%d.%m.%Y %H:%M:%S')"
    ((PRIVACY)) && printf 'Privacy: включён\\n'
''',
    '''    printf 'Дата: %s\\n' "$(date '+%d.%m.%Y %H:%M:%S')"
    ((PRIVACY)) && printf 'Privacy: включён\\n'
    if [[ -n $OUTPUT_PATH ]] && ((SAVE_REPORT==1)); then
        printf 'Отчёт: %s\\n' "$OUTPUT_PATH"
    elif [[ $PROFILE == enterprise ]] && ((SAVE_REPORT==0)); then
        printf 'Сохранение: отключено (--no-save)\\n'
    fi
''',
    'enterprise text save path',
)
replace_once(
    '''    fi
}

emit_json() {
''',
    '''    fi
    if [[ -n $OUTPUT_PATH ]] && ((SAVE_REPORT==1)); then
        printf '\\nОтчёт сохранён: %s\\n' "$OUTPUT_PATH"
    fi
}

emit_json() {
''',
    'enterprise text save footer',
)
replace_once(
    '''build_recommendations
if ((JSON_MODE)); then emit_json; else emit_text; fi

if ((CRIT_COUNT>0)); then exit 2
''',
    '''build_recommendations
if ((JSON_MODE)); then emit_json; else emit_text; fi

if [[ -n $OUTPUT_PATH ]] && ((SAVE_REPORT==1)); then
    chmod 0644 "$OUTPUT_PATH" 2>/dev/null || true
    if [[ "${SUDO_UID:-}" =~ ^[0-9]+$ && "${SUDO_GID:-}" =~ ^[0-9]+$ ]]; then
        chown "$SUDO_UID:$SUDO_GID" "$OUTPUT_PATH" 2>/dev/null || true
    fi
fi

if ((CRIT_COUNT>0)); then exit 2
''',
    'enterprise saved report permissions',
)

# Standard report: adapt width to terminal instead of a fixed 92 columns.
replace_once(
    '''WIDTH=92
line() { printf '%*s\\n' "$WIDTH" '' | tr ' ' '-'; }
''',
    '''WIDTH=${COLUMNS:-}
if [[ ! $WIDTH =~ ^[0-9]+$ ]] && command -v tput >/dev/null 2>&1; then WIDTH=$(tput cols 2>/dev/null || true); fi
[[ $WIDTH =~ ^[0-9]+$ ]] || WIDTH=110
((WIDTH<92)) && WIDTH=92
((WIDTH>132)) && WIDTH=132
line() { printf '%*s\\n' "$WIDTH" '' | tr ' ' '-'; }
''',
    'base dynamic width',
)

# Replace base recommendation wrapping with the same aligned field model used by corporate output.
pattern = re.compile(r'''print_wrapped\(\) \{.*?\n\}\nrun_smart\(\) \{''', re.S)
match = pattern.search(text)
if not match:
    raise SystemExit('base print_wrapped function not found')
replacement = r'''print_wrapped() {
    local label="$1" text="$2" indent=3 label_w=19 gap=1 value_w first=1 ln
    value_w=$((WIDTH-indent-label_w-gap))
    ((value_w<32)) && value_w=32
    while IFS= read -r ln || [[ -n $ln ]]; do
        if ((first)); then
            printf '%*s%-*s %s\n' "$indent" '' "$label_w" "$label" "$ln"
            first=0
        else
            printf '%*s%-*s %s\n' "$indent" '' "$label_w" '' "$ln"
        fi
    done < <(printf '%s\n' "$text" | fold -s -w "$value_w")
    ((first==0)) || printf '%*s%s\n' "$indent" '' "$label"
}

base_command_description() {
    local cmd=$1
    case "$cmd" in
        journalctl\ -k*) echo "покажет сообщения ядра текущей загрузки для поиска аппаратных, дисковых и драйверных ошибок" ;;
        journalctl\ -b\ -p\ err..alert*) echo "покажет ошибки уровня error и выше за текущую загрузку" ;;
        journalctl*) echo "покажет системный журнал, относящийся к диагностируемой проблеме" ;;
        systemctl\ --failed*) echo "покажет службы systemd, завершившиеся с ошибкой" ;;
        systemctl\ status*) echo "покажет состояние указанной службы и последние сообщения о её запуске" ;;
        smartctl\ --scan-open*) echo "покажет накопители и способы доступа к SMART" ;;
        smartctl*) echo "покажет SMART-состояние и диагностические атрибуты накопителя" ;;
        dnf\ install\ smartmontools*) echo "установит smartmontools для чтения SMART накопителей" ;;
        du\ -xhd1*) echo "покажет, какие каталоги занимают место в выбранной файловой системе" ;;
        df\ -h*) echo "покажет заполнение файловой системы и доступное место" ;;
        df\ -i*) echo "покажет использование inode файловой системы" ;;
        ps\ aux*) echo "покажет процессы с сортировкой для поиска основных потребителей ресурсов" ;;
        free\ -h*) echo "покажет использование ОЗУ и swap" ;;
        timedatectl*) echo "покажет системное время и состояние синхронизации" ;;
        mdadm*) echo "покажет состояние программного RAID" ;;
        ip\ *) echo "покажет сетевые интерфейсы, адреса или маршруты" ;;
        *) echo "покажет диагностические данные для проверки этой рекомендации" ;;
    esac
}
run_smart() {'''
text = text[:match.start()] + replacement + text[match.end():]

replace_once(
    '''   REC_NUM=$((REC_NUM+1)); echo; echo "$REC_NUM. [${REC_LEVELS[$i]}] ${REC_TITLES[$i]}"
''',
    '''   REC_NUM=$((REC_NUM+1)); echo; print_wrapped "$REC_NUM. [${REC_LEVELS[$i]}]" "${REC_TITLES[$i]}"
''',
    'base recommendation title wrapping',
)
replace_once(
    '''   [ -n "${REC_CHECKS[$i]}" ]&&print_wrapped "Команда:" "${REC_CHECKS[$i]}"
''',
    '''   if [ -n "${REC_CHECKS[$i]}" ]; then
       _rec_cmd_desc=$(base_command_description "${REC_CHECKS[$i]}")
       print_wrapped "Команда:" "${REC_CHECKS[$i]} ($_rec_cmd_desc)"
   fi
''',
    'base recommendation command description',
)

# CPU temperature: the reported CPU_TEMP is the median. Do not mix it with the maximum in one label.
replace_once(
    '     echo "Температура CPU|${CPU_TEMP}°C (медиана; максимум ${CPU_TEMP_MAX}°C)"',
    '     echo "Температура CPU|${CPU_TEMP}°C (медиана)"',
    'cpu temperature wording',
)

SCRIPT.write_text(text, encoding="utf-8")

# Documentation updates.
def patch_file(path: Path, updater):
    data = path.read_text(encoding="utf-8")
    new = updater(data)
    if new == data:
        raise SystemExit(f"no documentation change for {path}")
    path.write_text(new, encoding="utf-8")

patch_file(ROOT / "docs/releases/v1.2.2.md", lambda s: s.replace(
    "- корпоративный TXT-отчёт выровнен по колонкам и аккуратно переносит длинные строки;",
    "- корпоративный TXT-отчёт выровнен по колонкам и аккуратно переносит длинные строки;\n- `--corp` теперь по умолчанию сохраняет отчёт в текущий каталог; `--no-save` отключает сохранение;\n- стандартный отчёт получил выровненные рекомендации, аккуратный перенос и пояснения к командам;\n- температура CPU в стандартном отчёте отображается как медиана без дублирования максимума;"
) if "по умолчанию сохраняет отчёт" not in s else s)

patch_file(ROOT / "CHANGELOG.md", lambda s: s.replace(
    "## [1.2.2]",
    "## [1.2.2]\n\n- Corporate `--corp` report now saves automatically by default; `--no-save` disables saving.\n- Standard recommendations use aligned wrapped fields and command descriptions.\n- CPU temperature output now labels the displayed value simply as the median."
) if "Corporate `--corp` report now saves automatically" not in s else s)

patch_file(ROOT / "README.md", lambda s: s.replace(
    "sudo bash /tmp/arm_info.sh --corp\n```",
    "sudo bash /tmp/arm_info.sh --corp\n```\n\nКорпоративный TXT-отчёт при таком запуске сохраняется автоматически в текущий каталог. Чтобы только вывести результат без сохранения, используйте `--no-save`."
) if "Корпоративный TXT-отчёт при таком запуске сохраняется автоматически" not in s else s)
