from pathlib import Path

path = Path('arm_info.sh')
text = path.read_text(encoding='utf-8')

replacements = [
    (
        '            REC_CHECK="Определить конкретные mount points, проверить stat с timeout, kernel CIFS messages и Kerberos ticket."',
        '            REC_CHECK="Определить локальные TARGET всех CIFS mount, автоматически проверить каждый TARGET через stat с timeout, затем проверить kernel CIFS messages и Kerberos ticket. SOURCE вида //server/share в stat не использовать."'
    ),
    (
        '            REC_COMMAND="findmnt -t cifs -o TARGET,SOURCE,OPTIONS|timeout 5 stat -f \'MOUNT_PATH\'|journalctl -k -b --no-pager | grep -Ei \'cifs|smb\' | tail -120|sudo -u \'USER_NAME\' klist -A"',
        '            REC_COMMAND="findmnt -t cifs -o TARGET,SOURCE,OPTIONS|findmnt -rn -t cifs -o TARGET | while IFS= read -r m; do printf \'=== %s ===\\n\' \\"\\$m\\"; timeout 5 stat -f -- \\"\\$m\\" || printf \'ОШИБКА/ТАЙМАУТ: %s\\n\' \\"\\$m\\"; done|journalctl -k -b --no-pager | grep -Ei \'cifs|smb\' | tail -120|sudo -u \'USER_NAME\' klist -A"'
    ),
    (
        '        findmnt*) desc="покажет источник, тип и параметры монтирования файловой системы" ;;',
        '        findmnt\\ -rn\\ -t\\ cifs\\ -o\\ TARGET*) desc="автоматически проверит каждый локальный TARGET CIFS через stat с таймаутом; SOURCE вида //server/share не используется" ;;\n        findmnt*) desc="покажет источник, тип и параметры монтирования файловой системы" ;;'
    ),
    (
        '(DOMAIN_FQDN|DC_FQDN|DC_IP|USER_NAME|PROFILE_NAME|CERT_PATH|MOUNT_PATH|QUEUE_NAME|JOB_ID|PARENT_PID|UNIT_NAME|DEVICE_PATH|MD_DEVICE|IFACE_NAME)',
        '(DOMAIN_FQDN|DC_FQDN|DC_IP|USER_NAME|PROFILE_NAME|CERT_PATH|QUEUE_NAME|JOB_ID|PARENT_PID|UNIT_NAME|DEVICE_PATH|MD_DEVICE|IFACE_NAME)'
    ),
]

for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'expected exactly one match, got {count}: {old[:100]}')
    text = text.replace(old, new, 1)

# Guard the exact contract we want to preserve.
required = [
    'findmnt -rn -t cifs -o TARGET | while IFS= read -r m;',
    'timeout 5 stat -f -- \\"\\$m\\"',
    'SOURCE вида //server/share в stat не использовать',
]
for token in required:
    if token not in text:
        raise SystemExit(f'missing generated token: {token}')
if "timeout 5 stat -f 'MOUNT_PATH'" in text:
    raise SystemExit('old manual CIFS MOUNT_PATH command remains')

path.write_text(text, encoding='utf-8')
