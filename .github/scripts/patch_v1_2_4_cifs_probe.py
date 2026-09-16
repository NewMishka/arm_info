from pathlib import Path


def replace_once(path, old, new, label):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 occurrence, got {count}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


def replace_all(path, old, new, label, min_count=1):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count < min_count:
        raise SystemExit(f'{label}: expected >= {min_count}, got {count}')
    p.write_text(text.replace(old, new), encoding='utf-8')

# arm_info.sh: make the detector and the suggested command use the same real directory-read probe.
p = Path('arm_info.sh')
text = p.read_text(encoding='utf-8')
old_decl = '    local gw ifaces idx=0 row iface ip mac speed duplex link dns_domain cifs_count=0 cifs_bad=0 mnt src gvfs_count=0 gvfs_bad=0 g dir\n'
new_decl = '    local gw ifaces idx=0 row iface ip mac speed duplex link dns_domain cifs_count=0 cifs_bad=0 mnt cifs_bad_value gvfs_count=0 gvfs_bad=0 g dir\n    local -a cifs_bad_targets=()\n'
if text.count(old_decl) != 1:
    raise SystemExit(f'check_network declaration anchor mismatch: {text.count(old_decl)}')
text = text.replace(old_decl, new_decl, 1)

old_check = '''    if have findmnt; then
        while IFS='|' read -r mnt src; do
            [[ -n $mnt ]] || continue; cifs_count=$((cifs_count+1))
            if run_timeout 4 stat -f "$mnt" >/dev/null 2>&1; then :; else cifs_bad=$((cifs_bad+1)); fi
        done < <(findmnt -n -l -t cifs -o TARGET,SOURCE 2>/dev/null | awk '{print $1"|"$2}')
        if ((cifs_count==0)); then add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "нет" info
        elif ((cifs_bad==0)); then add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "$cifs_count, доступны" ok
        else add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "$cifs_count, недоступны/зависли: $cifs_bad" warn; fi
    else add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "findmnt отсутствует" unknown; fi
'''
new_check = '''    if have findmnt; then
        # Читаем только TARGET одной колонкой. Разбор TARGET,SOURCE через awk ломает
        # точки монтирования с пробелами, а stat -f проверяет лишь метаданные ФС.
        # find -print -quit делает минимальное реальное чтение каталога и ловит stale/hang.
        while IFS= read -r mnt; do
            [[ -n $mnt ]] || continue; cifs_count=$((cifs_count+1))
            if run_timeout 5 find "$mnt" -mindepth 1 -maxdepth 1 -print -quit >/dev/null 2>&1; then
                :
            else
                cifs_bad=$((cifs_bad+1))
                cifs_bad_targets+=("$mnt")
            fi
        done < <(findmnt -n -l -t cifs -o TARGET 2>/dev/null)
        if ((cifs_count==0)); then
            add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "нет" info
        elif ((cifs_bad==0)); then
            add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "$cifs_count, каталоги читаются" ok
        else
            if ((PRIVACY)); then
                cifs_bad_value="$cifs_count, недоступны/зависли: $cifs_bad; проблемные TARGET: скрыто"
            else
                cifs_bad_value="$cifs_count, недоступны/зависли: $cifs_bad; проблемные TARGET: $(join_by ', ' "${cifs_bad_targets[@]}")"
            fi
            add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "$cifs_bad_value" warn
        fi
    else add_check "SMB / GVFS" "network.cifs" "CIFS mounts" "findmnt отсутствует" unknown; fi
'''
if text.count(old_check) != 1:
    raise SystemExit(f'CIFS checker anchor mismatch: {text.count(old_check)}')
text = text.replace(old_check, new_check, 1)

old_rec_check = '            REC_CHECK="Определить локальные TARGET всех CIFS mount без raw-режима findmnt, автоматически проверить каждый TARGET через stat с timeout, затем проверить kernel CIFS messages и Kerberos ticket. SOURCE вида //server/share в stat не использовать."\n'
new_rec_check = '            REC_CHECK="Определить локальные TARGET всех CIFS mount без raw-режима findmnt, затем выполнить минимальное фактическое чтение каждого каталога с timeout. Это выявляет ресурс, который смонтирован, но не открывается. SOURCE вида //server/share как локальный путь не использовать."\n'
if text.count(old_rec_check) != 1:
    raise SystemExit('CIFS REC_CHECK anchor mismatch')
text = text.replace(old_rec_check, new_rec_check, 1)

old_cmd = 'findmnt -n -l -t cifs -o TARGET | while IFS= read -r m; do printf \'=== %s ===\\n\' \\"\\$m\\"; timeout 5 stat -f -- \\"\\$m\\" || printf \'ОШИБКА/ТАЙМАУТ: %s\\n\' \\"\\$m\\"; done'
new_cmd = 'findmnt -n -l -t cifs -o TARGET | while IFS= read -r m; do printf \'=== %s ===\\n\' \\"\\$m\\"; if timeout 5 find \\"\\$m\\" -mindepth 1 -maxdepth 1 -print -quit >/dev/null 2>&1; then printf \'OK: каталог читается\\n\'; else printf \'ОШИБКА/ТАЙМАУТ: %s\\n\' \\"\\$m\\"; fi; done'
if text.count(old_cmd) != 1:
    raise SystemExit(f'CIFS recommendation command anchor mismatch: {text.count(old_cmd)}')
text = text.replace(old_cmd, new_cmd, 1)

text = text.replace(
    'автоматически проверит каждый локальный TARGET CIFS через stat с таймаутом; SOURCE вида //server/share не используется',
    'автоматически проверит фактическое чтение каждого локального TARGET CIFS через find с таймаутом; SOURCE вида //server/share не используется'
)
p.write_text(text, encoding='utf-8')

# Recommendation command test: protect both regressions (spaces and metadata-only stat).
p = Path('tests/test_recommendation_commands.sh')
text = p.read_text(encoding='utf-8')
text = text.replace(
    "grep -Fq 'timeout 5 stat -f -- \\\"\\$m\\\"' \"$SCRIPT\" || fail 'CIFS TARGET stat timeout missing'",
    "grep -Fq 'timeout 5 find \\\"\\$m\\\" -mindepth 1 -maxdepth 1 -print -quit' \"$SCRIPT\" || fail 'CIFS TARGET directory-read timeout missing'"
)
anchor = "! grep -Fq 'findmnt -rn -t cifs -o TARGET' \"$SCRIPT\" || fail 'CIFS raw findmnt mode would hex-escape non-ASCII TARGETs'"
extra = "! grep -Fq \"findmnt -n -l -t cifs -o TARGET,SOURCE 2>/dev/null | awk\" \"$SCRIPT\" || fail 'CIFS checker must not split TARGET/SOURCE on whitespace'\n! grep -Fq 'run_timeout 4 stat -f \"$mnt\"' \"$SCRIPT\" || fail 'metadata-only CIFS availability probe remains'\ngrep -Fq 'run_timeout 5 find \"$mnt\" -mindepth 1 -maxdepth 1 -print -quit' \"$SCRIPT\" || fail 'runtime CIFS directory-read probe missing'"
if extra not in text:
    if text.count(anchor) != 1:
        raise SystemExit('CIFS test guard anchor mismatch')
    text = text.replace(anchor, anchor + '\n' + extra, 1)
old_rep = '  "findmnt -n -l -t cifs -o TARGET | while IFS= read -r m; do printf \'=== %s ===\\\\n\' \\\"\\$m\\\"; timeout 5 stat -f -- \\\"\\$m\\\" || printf \'ОШИБКА/ТАЙМАУТ: %s\\\\n\' \\\"\\$m\\\"; done"'
new_rep = '  "findmnt -n -l -t cifs -o TARGET | while IFS= read -r m; do printf \'=== %s ===\\\\n\' \\\"\\$m\\\"; if timeout 5 find \\\"\\$m\\\" -mindepth 1 -maxdepth 1 -print -quit >/dev/null 2>&1; then printf \'OK: каталог читается\\\\n\'; else printf \'ОШИБКА/ТАЙМАУТ: %s\\\\n\' \\\"\\$m\\\"; fi; done"'
if text.count(old_rep) != 1:
    raise SystemExit(f'representative CIFS command anchor mismatch: {text.count(old_rep)}')
text = text.replace(old_rep, new_rep, 1)
p.write_text(text, encoding='utf-8')

# Full section test also protects the runtime checker implementation.
p = Path('tests/test_sections.sh')
text = p.read_text(encoding='utf-8')
anchor = 'grep -q \'check_network()\' "$SCRIPT" || die "enterprise: network checker missing"'
extra = '''grep -Fq 'done < <(findmnt -n -l -t cifs -o TARGET 2>/dev/null)' "$SCRIPT" || die "enterprise: CIFS TARGET-only enumeration missing"
grep -Fq 'run_timeout 5 find "$mnt" -mindepth 1 -maxdepth 1 -print -quit' "$SCRIPT" || die "enterprise: CIFS real directory-read probe missing"
! grep -Fq "findmnt -n -l -t cifs -o TARGET,SOURCE 2>/dev/null | awk" "$SCRIPT" || die "enterprise: whitespace-splitting CIFS parser returned"'''
if extra not in text:
    if text.count(anchor) != 1:
        raise SystemExit('section-test network anchor mismatch')
    text = text.replace(anchor, anchor + '\n' + extra, 1)
p.write_text(text, encoding='utf-8')

# Dedicated field-regression test: Cyrillic + spaces must be preserved, and missing target must fail.
Path('tests/test_cifs_probe.sh').write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/arm_info.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Static contract for the production checker.
grep -Fq 'findmnt -n -l -t cifs -o TARGET 2>/dev/null' "$SCRIPT" || fail 'TARGET-only findmnt enumeration missing'
grep -Fq 'run_timeout 5 find "$mnt" -mindepth 1 -maxdepth 1 -print -quit' "$SCRIPT" || fail 'real directory-read CIFS probe missing'
! grep -Fq 'findmnt -n -l -t cifs -o TARGET,SOURCE 2>/dev/null | awk' "$SCRIPT" || fail 'whitespace-splitting CIFS parser remains'
! grep -Fq 'run_timeout 4 stat -f "$mnt"' "$SCRIPT" || fail 'metadata-only CIFS probe remains'

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
GOOD="$TMP/Проектный офис"
BAD="$TMP/Несуществующий ресурс"
mkdir -p "$GOOD"
touch "$GOOD/контроль.txt"

# Same minimal read primitive used by arm_info: must handle UTF-8 and spaces.
timeout 5 find "$GOOD" -mindepth 1 -maxdepth 1 -print -quit >/dev/null 2>&1 || fail 'UTF-8/space TARGET probe failed'
if timeout 2 find "$BAD" -mindepth 1 -maxdepth 1 -print -quit >/dev/null 2>&1; then
    fail 'missing TARGET unexpectedly passed directory-read probe'
fi

# Simulate the one-column findmnt stream: the path must arrive unchanged in read -r.
SEEN=''
while IFS= read -r m; do SEEN=$m; done < <(printf '%s\n' "$GOOD")
[[ $SEEN == "$GOOD" ]] || fail "TARGET changed while reading: '$SEEN'"

echo 'CIFS probe regression tests: OK'
''', encoding='utf-8')

# Makefile
p = Path('Makefile')
text = p.read_text(encoding='utf-8')
text = text.replace('tests/test_recommendation_commands.sh tests/test_sections.sh packaging/build-rpm.sh', 'tests/test_recommendation_commands.sh tests/test_sections.sh tests/test_cifs_probe.sh packaging/build-rpm.sh')
if '\tbash tests/test_cifs_probe.sh\n' not in text:
    text = text.replace('\tbash tests/test_sections.sh\n', '\tbash tests/test_sections.sh\n\tbash tests/test_cifs_probe.sh\n', 1)
p.write_text(text, encoding='utf-8')

# CI
p = Path('.github/workflows/ci.yml')
text = p.read_text(encoding='utf-8')
text = text.replace('tests/test_recommendation_commands.sh tests/test_sections.sh packaging/build-rpm.sh', 'tests/test_recommendation_commands.sh tests/test_sections.sh tests/test_cifs_probe.sh packaging/build-rpm.sh')
anchor = '      - name: Full report section coverage\n        run: bash tests/test_sections.sh\n'
insert = anchor + '      - name: CIFS runtime probe regression tests\n        run: bash tests/test_cifs_probe.sh\n'
if 'CIFS runtime probe regression tests' not in text:
    if text.count(anchor) != 1:
        raise SystemExit('CI section anchor mismatch')
    text = text.replace(anchor, insert, 1)
p.write_text(text, encoding='utf-8')

# Documentation.
p = Path('docs/COMMANDS.md')
text = p.read_text(encoding='utf-8')
old = 'Для CIFS `SOURCE` и `TARGET` — разные сущности. `SOURCE` обычно выглядит как `//server/share` и не является локальным путём для `stat`. Рекомендация 1.2.4 сама получает локальные `TARGET` через `findmnt -n -l -t cifs -o TARGET` и по очереди проверяет каждый из них с таймаутом; вручную подставлять путь больше не требуется. В этой команде намеренно не используется `-r/--raw`: raw-режим `findmnt` hex-экранирует потенциально небезопасные символы, включая байты не-ASCII имён, и такой текст нельзя напрямую передавать в `stat` как фактический путь.'
new = 'Для CIFS `SOURCE` и `TARGET` — разные сущности. `SOURCE` обычно выглядит как `//server/share` и не является локальным путём к смонтированному каталогу. Рекомендация 1.2.4 сама получает локальные `TARGET` через `findmnt -n -l -t cifs -o TARGET` и по очереди выполняет минимальное фактическое чтение каждого каталога через `find ... -print -quit` с таймаутом. `stat -f` больше не используется как критерий доступности: он может успешно вернуть метаданные файловой системы, даже когда содержимое ресурса фактически не открывается. В команде также намеренно не используется `-r/--raw`: raw-режим `findmnt` hex-экранирует не-ASCII имена (`\\xd0...`). TARGET читается одной колонкой без `awk`, поэтому пробелы в именах точек монтирования не создают ложные ошибки.'
if text.count(old) != 1:
    raise SystemExit('COMMANDS CIFS paragraph mismatch')
text = text.replace(old, new, 1)
p.write_text(text, encoding='utf-8')

p = Path('docs/ENTERPRISE_PROFILES.md')
text = p.read_text(encoding='utf-8')
old = 'Проверка CIFS/GVFS использует короткий timeout, чтобы сама диагностика не зависла на недоступном ресурсе.'
new = 'Проверка CIFS/GVFS использует короткий timeout, чтобы сама диагностика не зависла на недоступном ресурсе. Для CIFS проверяется не только наличие mount: `arm_info` получает TARGET одной колонкой и выполняет минимальное чтение каталога. Это позволяет отличить смонтированный, но фактически не открывающийся ресурс; TARGET с пробелами и кириллицей сохраняются без разбиения/hex-экранирования.'
if text.count(old) != 1:
    raise SystemExit('ENTERPRISE CIFS paragraph mismatch')
text = text.replace(old, new, 1)
text = text.replace('`DOMAIN_FQDN`, `DC_FQDN`, `USER_NAME`, `PROFILE_NAME`, `CERT_PATH`, `MOUNT_PATH`, `QUEUE_NAME`', '`DOMAIN_FQDN`, `DC_FQDN`, `USER_NAME`, `PROFILE_NAME`, `CERT_PATH`, `QUEUE_NAME`')
p.write_text(text, encoding='utf-8')

p = Path('README.md')
text = p.read_text(encoding='utf-8')
text = text.replace('безопасные маркеры (`DOMAIN_FQDN`, `PROFILE_NAME`, `MOUNT_PATH` и т. п.)', 'безопасные маркеры (`DOMAIN_FQDN`, `PROFILE_NAME`, `USER_NAME` и т. п.)')
needle = 'Каждая выводимая команда получает отдельное описание результата. CI дополнительно запускает `tests/test_sections.sh`, который проверяет все пользовательские разделы стандартного TXT, основные группы JSON и все секции корпоративных профилей.'
replacement = needle + ' CIFS-проверка в 1.2.4 использует TARGET одной колонкой и фактическое минимальное чтение каталога с timeout: это исключает ложные WARN из-за пробелов/кириллицы и не считает успешный `stat -f` доказательством доступности содержимого.'
if text.count(needle) != 1:
    raise SystemExit('README 1.2.4 paragraph mismatch')
text = text.replace(needle, replacement, 1)
p.write_text(text, encoding='utf-8')

p = Path('docs/TESTING.md')
text = p.read_text(encoding='utf-8')
needle = '- `tests/test_sections.sh` — сквозной контроль всех пользовательских разделов стандартного TXT, всех основных групп standard JSON, всех секций профилей `domain/network/print/software/enterprise`, корпоративного TXT и критичных helper-контрактов SMART/CPU/ФС/корпоративных проверок.\n'
add = needle + '- `tests/test_cifs_probe.sh` — отдельная regression-проверка CIFS: TARGET читается одной колонкой без whitespace-splitting, UTF-8/пробелы сохраняются, а доступность проверяется фактическим чтением каталога вместо `stat -f`.\n'
if 'tests/test_cifs_probe.sh' not in text:
    if text.count(needle) != 1:
        raise SystemExit('TESTING tests anchor mismatch')
    text = text.replace(needle, add, 1)
text = text.replace('- recommendation-command audit tests;\n', '- recommendation-command audit tests;\n- CIFS runtime-probe regression tests (UTF-8, пробелы, actual directory read);\n')
p.write_text(text, encoding='utf-8')

p = Path('docs/PRE_RELEASE_CHECKLIST.md')
text = p.read_text(encoding='utf-8')
anchor = '- [ ] `tests/test_recommendation_commands.sh`: command-audit contract проходит без ошибок.\n'
extra = '- [ ] `tests/test_cifs_probe.sh`: CIFS TARGET с кириллицей/пробелами проходит без искажения; отсутствующий TARGET определяется как ошибка; metadata-only `stat -f` не используется как критерий доступности.\n'
if extra not in text:
    if text.count(anchor) != 1:
        raise SystemExit('PRE_RELEASE CIFS anchor mismatch')
    text = text.replace(anchor, anchor + extra, 1)
p.write_text(text, encoding='utf-8')

p = Path('CHANGELOG.md')
text = p.read_text(encoding='utf-8')
anchor = '- Исправлена полевая проблема с кириллическими CIFS mount points: из автоматической проверки удалён `findmnt -r/--raw`, который hex-экранировал не-ASCII байты (`\\xd0...`) и приводил к ложному `No such file or directory`; используется list-режим `findmnt -n -l`.\n'
extra = '- Исправлена вторая полевая проблема CIFS: внутренний checker больше не разбирает `TARGET,SOURCE` через `awk` (что ломало TARGET с пробелами) и не использует `stat -f` как доказательство доступности. Каждый TARGET читается отдельно, через минимальный `find -print -quit` с timeout; при WARN в обычном режиме выводятся конкретные проблемные TARGET.\n'
if extra not in text:
    if text.count(anchor) != 1:
        raise SystemExit('CHANGELOG CIFS anchor mismatch')
    text = text.replace(anchor, anchor + extra, 1)
p.write_text(text, encoding='utf-8')

p = Path('docs/releases/v1.2.4.md')
text = p.read_text(encoding='utf-8')
anchor = '- CIFS-рекомендация больше не требует вручную подставлять `MOUNT_PATH`: она автоматически получает локальные `TARGET` всех CIFS mounts через list-режим `findmnt -n -l` и проверяет каждый через `stat` с timeout; `SOURCE` вида `//server/share` явно не используется как локальный путь, а `findmnt -r/--raw` исключён, чтобы кириллические пути не превращались в `\\xd0...`;\n'
new = '- CIFS-рекомендация больше не требует вручную подставлять путь: она автоматически получает локальные `TARGET` через `findmnt -n -l -t cifs -o TARGET`, без `-r/--raw`, поэтому кириллица не превращается в `\\xd0...`; TARGET читается одной колонкой без `awk`, поэтому пробелы в имени не создают ложный WARN; доступность проверяется фактическим минимальным чтением каталога через `find -print -quit` с timeout вместо metadata-only `stat -f`;\n'
if text.count(anchor) != 1:
    raise SystemExit('release CIFS anchor mismatch')
text = text.replace(anchor, new, 1)
p.write_text(text, encoding='utf-8')

# Final guards.
script = Path('arm_info.sh').read_text(encoding='utf-8')
required = [
    'run_timeout 5 find "$mnt" -mindepth 1 -maxdepth 1 -print -quit',
    'findmnt -n -l -t cifs -o TARGET 2>/dev/null',
    'проблемные TARGET:',
    'timeout 5 find \\"\\$m\\" -mindepth 1 -maxdepth 1 -print -quit',
]
for item in required:
    if item not in script:
        raise SystemExit(f'final guard missing: {item}')
for forbidden in [
    'findmnt -n -l -t cifs -o TARGET,SOURCE 2>/dev/null | awk',
    'run_timeout 4 stat -f "$mnt"',
]:
    if forbidden in script:
        raise SystemExit(f'forbidden CIFS implementation remains: {forbidden}')
