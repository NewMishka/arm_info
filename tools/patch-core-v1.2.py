from pathlib import Path

p = Path('arm_info.sh')
s = p.read_text(encoding='utf-8')

s = s.replace('# arm_info 1.1.0 — диагностика АРМ для РЕД ОС 7 / 8', '# arm_info 1.2.0 — диагностика АРМ для РЕД ОС 7 / 8', 1)
s = s.replace('ARM_INFO_VERSION="1.1.0"', 'ARM_INFO_VERSION="1.2.0"', 1)

marker = '# enterprise-profile-dispatch-v1.2\n'
if marker not in s:
    needle = 'ARM_INFO_VERSION="1.2.0"\n'
    dispatch = r'''

# enterprise-profile-dispatch-v1.2
# Профили вынесены в отдельный read-only helper, чтобы базовая диагностика
# оставалась компактной и пригодной для вставки целиком в root-терминал.
_arm_enterprise_requested=0
for _arm_arg in "$@"; do
    case "$_arm_arg" in
        --profile|--profile=*|--compare) _arm_enterprise_requested=1; break ;;
    esac
done
if ((_arm_enterprise_requested)); then
    _arm_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)
    for _arm_helper in \
        "$_arm_script_dir/arm_info-enterprise.sh" \
        "$_arm_script_dir/../libexec/arm_info/arm_info-enterprise.sh" \
        "/usr/local/libexec/arm_info/arm_info-enterprise.sh" \
        "/usr/libexec/arm_info/arm_info-enterprise.sh"; do
        if [ -r "$_arm_helper" ]; then
            exec bash "$_arm_helper" "$@"
        fi
    done
    echo "Ошибка: enterprise helper arm_info-enterprise.sh не найден." >&2
    echo "Запустите из полного репозитория или выполните sudo bash install.sh." >&2
    exit 69
fi
'''
    if needle not in s:
        raise SystemExit('version marker not found')
    s = s.replace(needle, needle + dispatch, 1)

help_anchor = '  --config PATH           использовать другой конфигурационный файл\n'
if '--profile NAME' not in s:
    replacement = help_anchor + '  --profile NAME          domain|network|print|software|enterprise\n  --compare A.json B.json сравнить два JSON-отчёта АРМ\n'
    if help_anchor not in s:
        raise SystemExit('help anchor not found')
    s = s.replace(help_anchor, replacement, 1)

p.write_text(s, encoding='utf-8')
