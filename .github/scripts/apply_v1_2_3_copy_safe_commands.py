from pathlib import Path

root = Path('.')
p = root / 'arm_info.sh'
s = p.read_text(encoding='utf-8')

old = '''print_rec_commands() {
    local text=$1 cmd desc idx=0
    while IFS= read -r cmd; do
        [[ -n $cmd ]] || continue
        idx=$((idx+1))
        desc=$(command_description "$cmd")
        print_rec_field "Команда $idx:" "$cmd ($desc)"
    done < <(split_rec_commands "$text")
}'''
new = '''print_rec_command_line() {
    # Команда печатается одной физической строкой. Терминал может визуально
    # перенести её по ширине окна, но в вывод не вставляется перевод строки,
    # поэтому копирование длинной команды не разрывает shell pipeline/аргументы.
    local label=$1 cmd=$2 desc=$3 indent=3 label_w=23
    printf '%*s%s %s\\n' "$indent" '' "$(pad_right "$label" "$label_w")" "$cmd"
    print_rec_field '' "($desc)"
}

print_rec_commands() {
    local text=$1 cmd desc idx=0
    while IFS= read -r cmd; do
        [[ -n $cmd ]] || continue
        idx=$((idx+1))
        desc=$(command_description "$cmd")
        print_rec_command_line "Команда $idx:" "$cmd" "$desc"
    done < <(split_rec_commands "$text")
}'''
if old not in s:
    raise SystemExit('corporate command renderer marker not found')
s = s.replace(old, new, 1)

old2 = '''base_command_description() {
    local cmd=$1'''
new2 = '''base_print_command_line() {
    # Как и в корпоративном отчёте, команда остаётся одной физической строкой.
    # Перенос выполняет только терминал визуально, что сохраняет копируемую строку.
    local label=$1 cmd=$2 desc=$3 indent=3 label_w=23
    printf '%*s%s %s\\n' "$indent" '' "$(base_pad_right "$label" "$label_w")" "$cmd"
    print_wrapped '' "($desc)"
}

base_command_description() {
    local cmd=$1'''
if old2 not in s:
    raise SystemExit('base command description marker not found')
s = s.replace(old2, new2, 1)

old3 = '''   if [ -n "${REC_CHECKS[$i]}" ]; then
       _rec_cmd_desc=$(base_command_description "${REC_CHECKS[$i]}")
       print_wrapped "Команда 1:" "${REC_CHECKS[$i]} ($_rec_cmd_desc)"
   fi'''
new3 = '''   if [ -n "${REC_CHECKS[$i]}" ]; then
       _rec_cmd_desc=$(base_command_description "${REC_CHECKS[$i]}")
       base_print_command_line "Команда 1:" "${REC_CHECKS[$i]}" "$_rec_cmd_desc"
   fi'''
if old3 not in s:
    raise SystemExit('base recommendation command marker not found')
s = s.replace(old3, new3, 1)

p.write_text(s, encoding='utf-8')

# Regression guards.
t = root / 'tests/test_enterprise.sh'
x = t.read_text(encoding='utf-8')
needle = "grep -Fq 'done < <(split_rec_commands \"$text\")' \"$SCRIPT\" || die \"corporate text commands must preserve pipelines\"\n"
addition = "grep -q 'print_rec_command_line' \"$SCRIPT\" || die \"corporate commands must use copy-safe renderer\"\ngrep -Fq 'printf '\"'\"'%*s%s %s\\\\n'\"'\"'' \"$SCRIPT\" || die \"copy-safe command physical line\"\n"
if addition.strip() not in x:
    if needle not in x:
        raise SystemExit('enterprise test insertion marker not found')
    x = x.replace(needle, needle + addition, 1)
t.write_text(x, encoding='utf-8')

u = root / 'tests/test_cli.sh'
y = u.read_text(encoding='utf-8')
marker = "grep -q 'Контроль результата:' \"$SCRIPT\" || die \"base recommendation verification field\"\n"
add = "grep -q 'base_print_command_line' \"$SCRIPT\" || die \"base commands must use copy-safe renderer\"\n"
if add.strip() not in y:
    if marker not in y:
        # Fallback: append before final success line.
        marker = 'echo "OK:'
        pos = y.find(marker)
        if pos < 0:
            raise SystemExit('base test insertion marker not found')
        y = y[:pos] + add + y[pos:]
    else:
        y = y.replace(marker, marker + add, 1)
u.write_text(y, encoding='utf-8')

# Release notes and changelog.
rel = root / 'docs/releases/v1.2.3.md'
r = rel.read_text(encoding='utf-8')
line = '- команды в рекомендациях выводятся одной физической строкой без принудительного `fold`; длинная команда может визуально переноситься терминалом, но при копировании остаётся цельной; пояснение к команде выводится отдельной строкой в скобках.\n'
if line not in r:
    anchor = '- стандартный блок рекомендаций использует такое же выравнивание полей и команд, как корпоративный;\n'
    if anchor not in r:
        raise SystemExit('release notes insertion marker not found')
    r = r.replace(anchor, anchor + line, 1)
rel.write_text(r, encoding='utf-8')

ch = root / 'CHANGELOG.md'
c = ch.read_text(encoding='utf-8')
line2 = '- Исправлено копирование длинных команд из рекомендаций: команды больше не разбиваются `fold` на физические строки; описание команды остаётся отдельной строкой в скобках.\n'
if line2 not in c:
    anchor2 = '### Changed\n'
    if anchor2 not in c:
        raise SystemExit('changelog marker not found')
    c = c.replace(anchor2, anchor2 + line2, 1)
ch.write_text(c, encoding='utf-8')
