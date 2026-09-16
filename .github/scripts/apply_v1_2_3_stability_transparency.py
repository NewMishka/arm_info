from pathlib import Path

root = Path('.')
p = root / 'arm_info.sh'
s = p.read_text(encoding='utf-8')

old = '''STAB_SCORE=100
if ((FAILED_COUNT==1)); then STAB_SCORE=$((STAB_SCORE-5)); elif ((FAILED_COUNT<=3 && FAILED_COUNT>=2)); then STAB_SCORE=$((STAB_SCORE-10)); elif ((FAILED_COUNT>3)); then STAB_SCORE=$((STAB_SCORE-20)); fi
if ((HW_ERR_COUNT<=2 && HW_ERR_COUNT>=1)); then STAB_SCORE=$((STAB_SCORE-10)); elif ((HW_ERR_COUNT<=5 && HW_ERR_COUNT>=3)); then STAB_SCORE=$((STAB_SCORE-20)); elif ((HW_ERR_COUNT>5)); then STAB_SCORE=$((STAB_SCORE-35)); fi
if ((JOURNAL_ERR_COUNT>=6 && JOURNAL_ERR_COUNT<=15)); then STAB_SCORE=$((STAB_SCORE-5)); elif ((JOURNAL_ERR_COUNT>=16 && JOURNAL_ERR_COUNT<=30)); then STAB_SCORE=$((STAB_SCORE-10)); elif ((JOURNAL_ERR_COUNT>30)); then STAB_SCORE=$((STAB_SCORE-15)); fi
((OOM_DETECTED==1))&&STAB_SCORE=$((STAB_SCORE-10))
[ "$TIME_SYNC" = "Нет" ] && STAB_SCORE=$((STAB_SCORE-5))
((UNCLEAN_BOOT_SIGNS>0)) && STAB_SCORE=$((STAB_SCORE-5))
((ECC_CE>0)) && STAB_SCORE=$((STAB_SCORE-5))
((ECC_UE>0)) && STAB_SCORE=$(min_score "$STAB_SCORE" 30)
STAB_SCORE=$(clamp_score "$STAB_SCORE")'''

new = '''# Стабильность системы: прозрачная модель штрафов от 100 баллов.
# Это не оценка качества/целостности самой ОС: сюда входят runtime-сигналы
# systemd, kernel journal, OOM, время и ECC, то есть устойчивость АРМ в целом.
STAB_SCORE=100
STAB_PENALTY_FAILED=0
STAB_PENALTY_HW=0
STAB_PENALTY_JOURNAL=0
STAB_PENALTY_OOM=0
STAB_PENALTY_TIME=0
STAB_PENALTY_UNCLEAN=0
STAB_PENALTY_ECC_CE=0
STAB_ECC_UE_CAP=0

if ((FAILED_COUNT==1)); then STAB_PENALTY_FAILED=5
elif ((FAILED_COUNT>=2 && FAILED_COUNT<=3)); then STAB_PENALTY_FAILED=10
elif ((FAILED_COUNT>3)); then STAB_PENALTY_FAILED=20
fi

if ((HW_ERR_COUNT>=1 && HW_ERR_COUNT<=2)); then STAB_PENALTY_HW=10
elif ((HW_ERR_COUNT>=3 && HW_ERR_COUNT<=5)); then STAB_PENALTY_HW=20
elif ((HW_ERR_COUNT>5)); then STAB_PENALTY_HW=35
fi

if ((JOURNAL_ERR_COUNT>=6 && JOURNAL_ERR_COUNT<=15)); then STAB_PENALTY_JOURNAL=5
elif ((JOURNAL_ERR_COUNT>=16 && JOURNAL_ERR_COUNT<=30)); then STAB_PENALTY_JOURNAL=10
elif ((JOURNAL_ERR_COUNT>30)); then STAB_PENALTY_JOURNAL=15
fi

((OOM_DETECTED==1)) && STAB_PENALTY_OOM=10
[ "$TIME_SYNC" = "Нет" ] && STAB_PENALTY_TIME=5
((UNCLEAN_BOOT_SIGNS>0)) && STAB_PENALTY_UNCLEAN=5
((ECC_CE>0)) && STAB_PENALTY_ECC_CE=5

STAB_SCORE=$((STAB_SCORE - STAB_PENALTY_FAILED - STAB_PENALTY_HW - STAB_PENALTY_JOURNAL - STAB_PENALTY_OOM - STAB_PENALTY_TIME - STAB_PENALTY_UNCLEAN - STAB_PENALTY_ECC_CE))
if ((ECC_UE>0)); then
    STAB_ECC_UE_CAP=30
    STAB_SCORE=$(min_score "$STAB_SCORE" "$STAB_ECC_UE_CAP")
fi
STAB_SCORE=$(clamp_score "$STAB_SCORE")

if ((STAB_SCORE>=90)); then STAB_STATUS="Норма"
elif ((STAB_SCORE>=75)); then STAB_STATUS="Незначительные отклонения"
elif ((STAB_SCORE>=50)); then STAB_STATUS="Требует внимания"
else STAB_STATUS="Сниженная стабильность"
fi'''

if old not in s:
    raise SystemExit('stability scoring marker not found')
s = s.replace(old, new, 1)

anchor = '''section "СЕТЬ"
if ((${#NET_ROWS[@]})); then'''
section = '''section "СТАБИЛЬНОСТЬ СИСТЕМЫ"
{
 echo "Оценка|$STAB_SCORE / 100|вес в общем индексе 15%"
 echo "Состояние|$STAB_STATUS|-"
 echo "Failed-службы|$FAILED_COUNT|$STAB_PENALTY_FAILED"
 echo "Ошибки ядра HW/storage|$HW_ERR_COUNT|$STAB_PENALTY_HW"
 echo "Уникальные journal err..alert|$JOURNAL_ERR_COUNT|$STAB_PENALTY_JOURNAL"
 echo "OOM-killer|$([ "$OOM_DETECTED" -eq 1 ] && echo Да || echo Нет)|$STAB_PENALTY_OOM"
 echo "Синхронизация времени|$TIME_SYNC|$STAB_PENALTY_TIME"
 echo "Признаки аварийной загрузки|$UNCLEAN_BOOT_SIGNS|$STAB_PENALTY_UNCLEAN"
 echo "ECC corrected / uncorrectable|$ECC_CE / $ECC_UE|$STAB_PENALTY_ECC_CE"
 if ((STAB_ECC_UE_CAP>0)); then echo "Ограничение из-за ECC UE|оценка не выше $STAB_ECC_UE_CAP|критический фактор"; fi
} | { printf 'Показатель|Значение|Штраф, баллов\\n'; cat; } | table

echo "Примечание: показатель отражает устойчивость работы АРМ по системным событиям;"
echo "он не означает, что сама установленная ОС повреждена или неисправна."

section "СЕТЬ"
if ((${#NET_ROWS[@]})); then'''
if anchor not in s:
    raise SystemExit('stability output insertion marker not found')
s = s.replace(anchor, section, 1)

# Enrich JSON stability details without changing schema_version.
old_json = '''    printf '  "stability": {"failed_units":%s,"hardware_errors":%s,"journal_errors":%s,"score":%s},\\n' \\
        "$FAILED_COUNT" "$HW_ERR_COUNT" "$JOURNAL_ERR_COUNT" "$STAB_SCORE"'''
new_json = '''    printf '  "stability": {"failed_units":%s,"hardware_errors":%s,"journal_errors":%s,"oom_detected":%s,"time_sync":"%s","unclean_boot_signs":%s,"ecc_ce":%s,"ecc_ue":%s,"penalty_failed_units":%s,"penalty_hardware":%s,"penalty_journal":%s,"penalty_oom":%s,"penalty_time":%s,"penalty_unclean_boot":%s,"penalty_ecc_ce":%s,"ecc_ue_score_cap":%s,"score":%s},\\n' \\
        "$FAILED_COUNT" "$HW_ERR_COUNT" "$JOURNAL_ERR_COUNT" "$([ "$OOM_DETECTED" -eq 1 ] && echo true || echo false)" "$(json_escape "$TIME_SYNC")" "$UNCLEAN_BOOT_SIGNS" "$ECC_CE" "$ECC_UE" \\
        "$STAB_PENALTY_FAILED" "$STAB_PENALTY_HW" "$STAB_PENALTY_JOURNAL" "$STAB_PENALTY_OOM" "$STAB_PENALTY_TIME" "$STAB_PENALTY_UNCLEAN" "$STAB_PENALTY_ECC_CE" "$STAB_ECC_UE_CAP" "$STAB_SCORE"'''
if old_json not in s:
    raise SystemExit('stability json marker not found')
s = s.replace(old_json, new_json, 1)

p.write_text(s, encoding='utf-8')

# Base CLI regression tests.
t = root / 'tests/test_cli.sh'
x = t.read_text(encoding='utf-8')
insert = '''grep -q 'section "СТАБИЛЬНОСТЬ СИСТЕМЫ"' "$SCRIPT" || die "stability section"
grep -q 'STAB_PENALTY_FAILED' "$SCRIPT" || die "stability failed-unit penalty"
grep -q 'STAB_PENALTY_HW' "$SCRIPT" || die "stability hardware penalty"
grep -q 'Штраф, баллов' "$SCRIPT" || die "stability transparent penalty table"
grep -q '"penalty_hardware"' "$SCRIPT" || die "stability JSON penalty details"
'''
marker = "grep -q 'REMOVABLE_FS_COUNT' \"$SCRIPT\" || die \"removable filesystem exclusion\"\n"
if insert.strip() not in x:
    if marker not in x:
        raise SystemExit('test_cli marker not found')
    x = x.replace(marker, marker + insert, 1)
t.write_text(x, encoding='utf-8')

# Scoring documentation.
d = root / 'docs/SCORING.md'
y = d.read_text(encoding='utf-8')
y = y.replace('| OS stability | 15% |', '| Стабильность системы | 15% |')
old_doc = '''### Стабильность

Учитываются failed systemd units, уникальные hardware/storage errors в kernel journal, уникальные `err..alert`, OOM, проблемы синхронизации времени, признаки аварийной предыдущей загрузки и EDAC/ECC.'''
new_doc = '''### Стабильность системы

Это оценка **устойчивости работы АРМ по системным событиям**, а не утверждение о повреждении или качестве самой установленной ОС. Группа имеет вес 15% в итоговом индексе и начинается со 100 баллов.

Штрафы отображаются непосредственно в текстовом отчёте:

| Сигнал | Условие | Штраф |
|---|---|---:|
| failed systemd units | 1 / 2–3 / >3 | 5 / 10 / 20 |
| hardware/storage errors в kernel journal | 1–2 / 3–5 / >5 | 10 / 20 / 35 |
| уникальные `err..alert` в journal | 6–15 / 16–30 / >30 | 5 / 10 / 15 |
| OOM-killer | обнаружен | 10 |
| синхронизация времени | `Нет` | 5 |
| признаки аварийной предыдущей загрузки | >0 | 5 |
| EDAC/ECC corrected errors (CE) | >0 | 5 |
| EDAC/ECC uncorrectable errors (UE) | >0 | итог stability ограничивается максимум 30 |

Например, 1 failed-служба, 13 hardware/storage errors и 155 уникальных `err..alert` дают `100 - 5 - 35 - 15 = 45/100`. Это означает наличие серьёзных системных событий, требующих разбора; само по себе значение не доказывает неисправность ОС.'''
if old_doc not in y:
    raise SystemExit('SCORING stability section marker not found')
y = y.replace(old_doc, new_doc, 1)
d.write_text(y, encoding='utf-8')

# Changelog/release notes.
ch = root / 'CHANGELOG.md'
c = ch.read_text(encoding='utf-8')
line = '- Оценка `Стабильность` переименована в `Стабильность системы` и стала прозрачной: отчёт показывает исходные сигналы и штраф в баллах для failed units, kernel HW/storage errors, journal, OOM, времени, аварийной загрузки и ECC; формула оценки не изменена.\n'
if line not in c:
    c = c.replace('### Changed\n', '### Changed\n' + line, 1)
ch.write_text(c, encoding='utf-8')

rel = root / 'docs/releases/v1.2.3.md'
r = rel.read_text(encoding='utf-8')
line2 = '- оценка стабильности переименована в `Стабильность системы`: в отчёте показываются `100/100`, каждый учитываемый сигнал и его штраф; формула/пороги не менялись, изменена прозрачность представления.\n'
if line2 not in r:
    anchor2 = '## Что изменено\n'
    if anchor2 not in r:
        raise SystemExit('release note marker not found')
    r = r.replace(anchor2, anchor2 + '\n' + line2, 1)
rel.write_text(r, encoding='utf-8')
