from pathlib import Path

path = Path('arm_info.sh')
text = path.read_text(encoding='utf-8')

enterprise_old = '''        findmnt\\ -t\\ cifs*) desc="покажет активные CIFS-точки монтирования, источник и параметры mount" ;;
        timeout*stat*) desc="проверит доступность конкретной точки монтирования без длительного зависания" ;;'''
enterprise_new = '''        findmnt\\ -rn\\ -t\\ cifs\\ -o\\ TARGET*) desc="автоматически проверит каждый локальный TARGET CIFS через stat с таймаутом; SOURCE вида //server/share не используется" ;;
        findmnt\\ -t\\ cifs*) desc="покажет активные CIFS-точки монтирования, источник и параметры mount" ;;
        timeout*stat*) desc="проверит доступность конкретной точки монтирования без длительного зависания" ;;'''

if text.count(enterprise_old) != 1:
    raise SystemExit(f'enterprise command-description anchor count={text.count(enterprise_old)}')
text = text.replace(enterprise_old, enterprise_new, 1)

base_extra = '        findmnt\\ -rn\\ -t\\ cifs\\ -o\\ TARGET*) desc="автоматически проверит каждый локальный TARGET CIFS через stat с таймаутом; SOURCE вида //server/share не используется" ;;\n'
if text.count(base_extra) != 1:
    raise SystemExit(f'base misplaced description count={text.count(base_extra)}')
text = text.replace(base_extra, '', 1)

required = [
    'findmnt -rn -t cifs -o TARGET | while IFS= read -r m;',
    'timeout 5 stat -f -- \\"\\$m\\"',
    'SOURCE вида //server/share в stat не использовать',
    'findmnt\\ -rn\\ -t\\ cifs\\ -o\\ TARGET*) desc="автоматически проверит каждый локальный TARGET CIFS через stat с таймаутом; SOURCE вида //server/share не используется"',
]
for token in required:
    if token not in text:
        raise SystemExit(f'missing generated token: {token}')
if "timeout 5 stat -f 'MOUNT_PATH'" in text:
    raise SystemExit('old manual CIFS MOUNT_PATH command remains')

path.write_text(text, encoding='utf-8')
