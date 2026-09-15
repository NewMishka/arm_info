from pathlib import Path
import re

root = Path('.')
helper = root / 'arm_info-enterprise.sh'
s = helper.read_text(encoding='utf-8')

# 1) Kerberos: generic error counter, no hard-coded numeric codes.
s = s.replace(
    '    local d sssd_state join_state kstate cache_count sync_state chrony sssd_logs c6 c7 c15 sev\n',
    '    local d sssd_state join_state kstate cache_count sync_state chrony sssd_logs krb_errors sev\n',
    1,
)

old_kerb = '''    if have journalctl; then
        sssd_logs=$(journalctl -u sssd -b --no-pager 2>/dev/null || true)
        c6=$(grep -Eci '(krb5|kerberos).*(code|error)[^0-9-]*6([^0-9]|$)' <<<"$sssd_logs" || true)
        c7=$(grep -Eci '(krb5|kerberos).*(code|error)[^0-9-]*7([^0-9]|$)' <<<"$sssd_logs" || true)
        c15=$(grep -Eci '(krb5|kerberos).*(code|error)[^0-9-]*15([^0-9]|$)' <<<"$sssd_logs" || true)
        if ((c6+c7+c15>0)); then sev=warn; else sev=ok; fi
        add_check "ДОМЕН / KERBEROS" "kerberos.errors" "Kerberos 6/7/15 в SSSD" "6:$c6  7:$c7  15:$c15" "$sev" "Счётчики относятся только к текущей загрузке"
    else add_check "ДОМЕН / KERBEROS" "kerberos.errors" "Kerberos 6/7/15 в SSSD" "journalctl отсутствует" unknown; fi
'''
new_kerb = '''    if have journalctl; then
        sssd_logs=$(journalctl -u sssd -b --no-pager 2>/dev/null || true)
        krb_errors=$(awk 'BEGIN{IGNORECASE=1} /(krb5|kerberos)/ && /(error|fail|failure|failed|denied|reject|unable|cannot|expired|clock skew|preauth|not found|unreachable|timeout)/ {n++} END{print n+0}' <<<"$sssd_logs")
        if ((krb_errors>0)); then sev=warn; else sev=ok; fi
        add_check "ДОМЕН / KERBEROS" "kerberos.errors" "Ошибки Kerberos" "$krb_errors" "$sev" "Количество записей с признаками ошибок Kerberos за текущую загрузку"
    else add_check "ДОМЕН / KERBEROS" "kerberos.errors" "Ошибки Kerberos" "journalctl отсутствует" unknown; fi
'''
if old_kerb not in s:
    raise SystemExit('Kerberos block not found')
s = s.replace(old_kerb, new_kerb, 1)

# 2) Software inventory: global RPM inventory only, no vendor/application allow-list.
software_re = re.compile(r'''_rpm_matches\(\) \{.*?^\}\n\ncheck_software\(\) \{.*?^\}\n\n(?=emit_text\(\))''', re.S | re.M)
new_software = r'''check_software() {
    local rows count zombies processes pkg version key
    if have rpm; then
        rows=$(rpm -qa --qf '%{NAME}.%{ARCH}|%{VERSION}-%{RELEASE}\n' 2>/dev/null | LC_ALL=C sort -f)
        count=$(grep -c . <<<"$rows" 2>/dev/null || true)
        add_check "ИНВЕНТАРИЗАЦИЯ ПО" "software.total" "Установлено RPM-пакетов" "$count" info
        while IFS='|' read -r pkg version; do
            [[ -n $pkg ]] || continue
            key=$(printf '%s' "$pkg" | tr -c '[:alnum:]_.+-' '_')
            add_check "ИНВЕНТАРИЗАЦИЯ ПО" "software.package.$key" "$pkg" "$version" info
        done <<<"$rows"
    else
        add_check "ИНВЕНТАРИЗАЦИЯ ПО" "software.rpm" "RPM inventory" "rpm отсутствует" unknown
    fi

    processes=$(ps -e --no-headers 2>/dev/null | wc -l | tr -d ' ')
    [[ $processes =~ ^[0-9]+$ ]] || processes=0
    add_check "ПРОЦЕССЫ" "software.processes.total" "Активные процессы" "$processes" info

    zombies=$(ps -eo stat= 2>/dev/null | awk '$1 ~ /^Z/{n++} END{print n+0}')
    if ((zombies>0)); then
        add_check "ПРОЦЕССЫ" "software.zombies" "Zombie-процессы" "$zombies" warn
    else
        add_check "ПРОЦЕССЫ" "software.zombies" "Zombie-процессы" "0" ok
    fi
}

'''
s, n = software_re.subn(new_software, s, count=1)
if n != 1:
    raise SystemExit(f'software block replacement count={n}')

# Enterprise profile stays operational-focused; full software inventory is explicit only.
s = s.replace(
    '    enterprise) check_domain; check_network; check_print; check_software ;;',
    '    enterprise) check_domain; check_network; check_print ;;',
    1,
)
s = s.replace(
    '  software     версии корпоративного ПО и проблемные процессы\n  enterprise   domain + network + print + software\n',
    '  software     глобальная инвентаризация всех RPM-пакетов и общие процессы\n  enterprise   domain + network + print\n',
    1,
)
helper.write_text(s, encoding='utf-8')

# README: no named applications and no numeric Kerberos-code list.
p = root / 'README.md'
r = p.read_text(encoding='utf-8')
r = r.replace('enterprise-профили: AD/SSSD/Kerberos/DNS, 802.1X, CIFS/GVFS, CUPS и корпоративное ПО;',
              'enterprise-профили: AD/SSSD/Kerberos/DNS, 802.1X, CIFS/GVFS и CUPS;')
r = r.replace('`domain` — SSSD, AD join, Kerberos ticket/cache, Kerberos 6/7/15 в текущем журнале, time sync, DNS SRV и доступность KDC/LDAP;',
              '`domain` — SSSD, AD join, Kerberos ticket/cache, ошибки Kerberos в текущем журнале, time sync, DNS SRV и доступность KDC/LDAP;')
r = re.sub(r'`software` — .*?;',
           '`software` — глобальная инвентаризация всех установленных RPM-пакетов, общее число процессов и zombie-процессы;', r, count=1)
r = r.replace('`enterprise` — объединяет все перечисленные проверки.',
              '`enterprise` — объединяет `domain + network + print`; глобальная инвентаризация ПО запускается отдельно через `--profile software`.')
p.write_text(r, encoding='utf-8')

# Enterprise docs.
p = root / 'docs/ENTERPRISE_PROFILES.md'
d = p.read_text(encoding='utf-8')
d = d.replace('- наличие в журнале SSSD Kerberos error/code 6, 7 и 15 за текущую загрузку;',
              '- количество записей с признаками ошибок Kerberos в журнале SSSD за текущую загрузку;')
d = re.sub(
    r'''### `software`\n\n.*?\n\n### `enterprise`\n\nПоследовательно запускает `domain \+ network \+ print \+ software`\.''',
    '''### `software`\n\nВыполняет глобальную инвентаризацию всех установленных RPM-пакетов без списка заранее заданных приложений. Для каждого пакета фиксируются имя/архитектура и версия-релиз. Дополнительно выводятся общее число процессов и количество zombie-процессов.\n\nПрофиль предназначен для отдельного запуска, когда нужна инвентаризация или сравнение двух АРМ. В общий enterprise-отчёт он не включён, чтобы не раздувать оперативную диагностику сотнями строк.\n\n### `enterprise`\n\nПоследовательно запускает `domain + network + print`. Глобальная инвентаризация ПО выполняется отдельно через `--profile software`.''',
    d,
    count=1,
    flags=re.S,
)
p.write_text(d, encoding='utf-8')

# Changelog wording.
p = root / 'CHANGELOG.md'
c = p.read_text(encoding='utf-8')
if '## 1.2.0' not in c:
    c = '# Changelog\n\n## 1.2.0 — development\n\n### Changed\n- Kerberos diagnostics now reports generic Kerberos errors without hard-coded error-code lists.\n- Software profile performs global RPM inventory; no application/vendor allow-list is embedded.\n- Enterprise profile excludes full software inventory by default to keep operational reports compact.\n\n' + c.split('# Changelog\n',1)[1]
else:
    c = c.replace('Kerberos 6/7/15', 'ошибки Kerberos')
p.write_text(c, encoding='utf-8')

# Regression tests for this design decision.
p = root / 'tests/test_enterprise.sh'
t = p.read_text(encoding='utf-8')
anchor = 'bash "$SCRIPT" --help | grep -q -- \'--profile enterprise\' || die "--help profiles"\n'
extra = '''\n# No hard-coded application/vendor inventory and no hard-coded Kerberos error-code list.\nif grep -Eiq '(r7|remmina|freerdp|icaclient|citrix|basis|workplace|bsscrypto|cryptopro|cprocsp|jacarta|snx)' "$SCRIPT"; then\n  die "hard-coded software names found"\nfi\nif grep -Eq 'Kerberos 6/7/15|c6=|c7=|c15=' "$SCRIPT"; then\n  die "hard-coded Kerberos error codes found"\nfi\n'''
if 'hard-coded software names found' not in t:
    if anchor not in t:
        raise SystemExit('test anchor not found')
    t = t.replace(anchor, anchor + extra, 1)
p.write_text(t, encoding='utf-8')
