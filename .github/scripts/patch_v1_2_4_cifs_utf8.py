from pathlib import Path

# arm_info.sh
path = Path('arm_info.sh')
text = path.read_text(encoding='utf-8')
old = 'findmnt -rn -t cifs -o TARGET'
new = 'findmnt -n -l -t cifs -o TARGET'
count = text.count(old)
if count < 1:
    raise SystemExit(f'arm_info raw CIFS command not found: {count}')
text = text.replace(old, new)
old_pat = r'findmnt\ -rn\ -t\ cifs\ -o\ TARGET'
new_pat = r'findmnt\ -n\ -l\ -t\ cifs\ -o\ TARGET'
text = text.replace(old_pat, new_pat)
old_check = 'Определить локальные TARGET всех CIFS mount, автоматически проверить каждый TARGET через stat с timeout, затем проверить kernel CIFS messages и Kerberos ticket. SOURCE вида //server/share в stat не использовать.'
new_check = 'Определить локальные TARGET всех CIFS mount без raw-режима findmnt, автоматически проверить каждый TARGET через stat с timeout, затем проверить kernel CIFS messages и Kerberos ticket. SOURCE вида //server/share в stat не использовать.'
if text.count(old_check) != 1:
    raise SystemExit('REC_CHECK CIFS anchor mismatch')
text = text.replace(old_check, new_check, 1)
path.write_text(text, encoding='utf-8')

# recommendation command regression test
path = Path('tests/test_recommendation_commands.sh')
text = path.read_text(encoding='utf-8')
text = text.replace('findmnt -rn -t cifs -o TARGET', 'findmnt -n -l -t cifs -o TARGET')
guard_anchor = "! grep -Fq \"timeout 5 stat -f 'MOUNT_PATH'\" \"$SCRIPT\" || fail 'manual CIFS MOUNT_PATH recommendation remains'"
extra = "! grep -Fq 'findmnt -rn -t cifs -o TARGET' \"$SCRIPT\" || fail 'CIFS raw findmnt mode would hex-escape non-ASCII TARGETs'"
if extra not in text:
    if text.count(guard_anchor) != 1:
        raise SystemExit('test guard anchor mismatch')
    text = text.replace(guard_anchor, guard_anchor + '\n' + extra, 1)
path.write_text(text, encoding='utf-8')

# docs/COMMANDS.md
path = Path('docs/COMMANDS.md')
text = path.read_text(encoding='utf-8')
old = 'Для CIFS `SOURCE` и `TARGET` — разные сущности. `SOURCE` обычно выглядит как `//server/share` и не является локальным путём для `stat`. Рекомендация 1.2.4 сама получает локальные `TARGET` через `findmnt` и по очереди проверяет каждый из них с таймаутом; вручную подставлять путь больше не требуется.'
new = 'Для CIFS `SOURCE` и `TARGET` — разные сущности. `SOURCE` обычно выглядит как `//server/share` и не является локальным путём для `stat`. Рекомендация 1.2.4 сама получает локальные `TARGET` через `findmnt -n -l -t cifs -o TARGET` и по очереди проверяет каждый из них с таймаутом; вручную подставлять путь больше не требуется. В этой команде намеренно не используется `-r/--raw`: raw-режим `findmnt` hex-экранирует потенциально небезопасные символы, включая байты не-ASCII имён, и такой текст нельзя напрямую передавать в `stat` как фактический путь.'
if text.count(old) != 1:
    raise SystemExit('COMMANDS CIFS paragraph anchor mismatch')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')

# CHANGELOG.md
path = Path('CHANGELOG.md')
text = path.read_text(encoding='utf-8')
anchor = '- CIFS-рекомендация автоматически получает локальные `TARGET` всех CIFS mounts и проверяет каждый через `stat` с timeout; ручной `MOUNT_PATH` удалён, а `SOURCE` вида `//server/share` явно не предлагается как локальный путь.'
add = '- Исправлена полевая проблема с кириллическими CIFS mount points: из автоматической проверки удалён `findmnt -r/--raw`, который hex-экранировал не-ASCII байты (`\\xd0...`) и приводил к ложному `No such file or directory`; используется list-режим `findmnt -n -l`.'
if text.count(anchor) != 1:
    raise SystemExit('CHANGELOG CIFS anchor mismatch')
if add not in text:
    text = text.replace(anchor, anchor + '\n' + add, 1)
path.write_text(text, encoding='utf-8')

# release notes
path = Path('docs/releases/v1.2.4.md')
text = path.read_text(encoding='utf-8')
old = '- CIFS-рекомендация больше не требует вручную подставлять `MOUNT_PATH`: она автоматически получает локальные `TARGET` всех CIFS mounts и проверяет каждый через `stat` с timeout; `SOURCE` вида `//server/share` явно не используется как локальный путь;'
new = '- CIFS-рекомендация больше не требует вручную подставлять `MOUNT_PATH`: она автоматически получает локальные `TARGET` всех CIFS mounts через list-режим `findmnt -n -l` и проверяет каждый через `stat` с timeout; `SOURCE` вида `//server/share` явно не используется как локальный путь, а `findmnt -r/--raw` исключён, чтобы кириллические пути не превращались в `\\xd0...`;'
if text.count(old) != 1:
    raise SystemExit('release CIFS anchor mismatch')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')

# final guards
script = Path('arm_info.sh').read_text(encoding='utf-8')
if 'findmnt -n -l -t cifs -o TARGET | while IFS= read -r m;' not in script:
    raise SystemExit('new CIFS list-mode command missing')
if 'findmnt -rn -t cifs -o TARGET' in script:
    raise SystemExit('old raw CIFS command remains')
