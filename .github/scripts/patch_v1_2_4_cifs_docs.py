from pathlib import Path

# docs/COMMANDS.md
path = Path('docs/COMMANDS.md')
text = path.read_text(encoding='utf-8')
old = '`DOMAIN_FQDN`, `DC_FQDN`, `DC_IP`, `USER_NAME`, `PROFILE_NAME`, `CERT_PATH`, `MOUNT_PATH`, `QUEUE_NAME`, `JOB_ID`, `PARENT_PID`, `UNIT_NAME`, `DEVICE_PATH`, `MD_DEVICE`, `IFACE_NAME`'
new = '`DOMAIN_FQDN`, `DC_FQDN`, `DC_IP`, `USER_NAME`, `PROFILE_NAME`, `CERT_PATH`, `QUEUE_NAME`, `JOB_ID`, `PARENT_PID`, `UNIT_NAME`, `DEVICE_PATH`, `MD_DEVICE`, `IFACE_NAME`'
if text.count(old) != 1:
    raise SystemExit('COMMANDS marker list anchor mismatch')
text = text.replace(old, new, 1)
old = '- CIFS/GVFS: `findmnt -t cifs`, `timeout stat`, `loginctl`, `/run/user/*/gvfs`;'
new = '- CIFS/GVFS: `findmnt -t cifs`, автоматический обход локальных `TARGET` через `timeout 5 stat -f`, `loginctl`, `/run/user/*/gvfs`;'
if text.count(old) != 1:
    raise SystemExit('COMMANDS CIFS family anchor mismatch')
text = text.replace(old, new, 1)
anchor = '`mdadm --detail MD_DEVICE` требует реальное имя массива из `/proc/mdstat`; скрипт больше не предполагает, что это всегда `/dev/md0`.'
insert = '''Для CIFS `SOURCE` и `TARGET` — разные сущности. `SOURCE` обычно выглядит как `//server/share` и не является локальным путём для `stat`. Рекомендация 1.2.4 сама получает локальные `TARGET` через `findmnt` и по очереди проверяет каждый из них с таймаутом; вручную подставлять путь больше не требуется.\n\n'''
if text.count(anchor) != 1:
    raise SystemExit('COMMANDS mdadm anchor mismatch')
text = text.replace(anchor, insert + anchor, 1)
path.write_text(text, encoding='utf-8')

# CHANGELOG.md
path = Path('CHANGELOG.md')
text = path.read_text(encoding='utf-8')
old = '- Служебные маркеры вида `<DOMAIN>`/`<MOUNT>` заменены безопасными именованными токенами (`DOMAIN_FQDN`, `MOUNT_PATH`, `QUEUE_NAME`, `UNIT_NAME` и др.), которые не интерпретируются shell как redirection.'
new = '- Служебные маркеры вида `<DOMAIN>`/`<MOUNT>` заменены безопасными именованными токенами (`DOMAIN_FQDN`, `QUEUE_NAME`, `UNIT_NAME` и др.), которые не интерпретируются shell как redirection.'
if text.count(old) != 1:
    raise SystemExit('CHANGELOG placeholder anchor mismatch')
text = text.replace(old, new, 1)
anchor = '- Каждая команда в текстовой рекомендации имеет отдельное описание ожидаемого результата.'
insert = '- CIFS-рекомендация автоматически получает локальные `TARGET` всех CIFS mounts и проверяет каждый через `stat` с timeout; ручной `MOUNT_PATH` удалён, а `SOURCE` вида `//server/share` явно не предлагается как локальный путь.'
if text.count(anchor) != 1:
    raise SystemExit('CHANGELOG command description anchor mismatch')
text = text.replace(anchor, anchor + '\n' + insert, 1)
path.write_text(text, encoding='utf-8')
