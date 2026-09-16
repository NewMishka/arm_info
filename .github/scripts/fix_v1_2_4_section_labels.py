from pathlib import Path

path = Path('arm_info.sh')
text = path.read_text(encoding='utf-8')
old = 'echo "Стабильность ОС|$STAB_SCORE / 100|15%"'
new = 'echo "Стабильность системы|$STAB_SCORE / 100|15%"'

if old in text:
    text = text.replace(old, new)
elif new not in text:
    raise SystemExit('stability summary label not found')

path.write_text(text, encoding='utf-8')
