from pathlib import Path

arm = Path('arm_info.sh')
text = arm.read_text(encoding='utf-8')

wrapper = '''run_smart() {
    if command -v timeout >/dev/null 2>&1; then timeout 8 smartctl "$@"; else smartctl "$@"; fi
}

'''

if 'run_smart() {' not in text:
    marker = 'read_cpu_temp_once() {'
    if marker not in text:
        raise SystemExit('read_cpu_temp_once marker not found')
    text = text.replace(marker, wrapper + marker, 1)

arm.write_text(text, encoding='utf-8')

test = Path('tests/test_cli.sh')
t = test.read_text(encoding='utf-8')
checks = '''grep -q '^run_smart() {' "$SCRIPT" || die "SMART wrapper missing"
grep -Fq 'timeout 8 smartctl "$@"' "$SCRIPT" || die "SMART wrapper timeout contract"
grep -Fq 'SMART_ALL=$(run_smart -a "$DEV"' "$SCRIPT" || die "SMART collection must use wrapper"
'''
anchor = 'grep -q \'Съёмных ФС вне индекса\' "$SCRIPT" || die "removable filesystem report"\n'
if 'SMART wrapper missing' not in t:
    if anchor not in t:
        raise SystemExit('test anchor not found')
    t = t.replace(anchor, anchor + checks, 1)

test.write_text(t, encoding='utf-8')
