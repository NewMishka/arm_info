from pathlib import Path

p = Path('arm_info.sh')
s = p.read_text()

if 'domain.dc.node.$dc_index' not in s:
    start = s.index('        targets=$(printf', s.index('krb_srv=$(_srv_records'))
    end = s.index('\n    else\n        add_check "$section" "dns.srv"', start)
    new = '''        targets=$(printf '%s\\
%s\\
' "$ldap_srv" "$krb_srv" | awk 'NF{print $NF}' | sed 's/\\.$//' | sort -u | head -n3)
        local dc_index=0 krb_ok ldap_ok dc_sev dc_display krb_text ldap_text
        while IFS= read -r target; do
            [[ -n $target ]] || continue
            dc_index=$((dc_index+1))
            krb_ok=0; ldap_ok=0

            if _tcp_ok "$target" 88; then
                krb_ok=1; reachable=$((reachable+1))
            fi
            tested=$((tested+1))

            if _tcp_ok "$target" 389; then
                ldap_ok=1; reachable=$((reachable+1))
            fi
            tested=$((tested+1))

            if ((krb_ok)); then krb_text='доступен'; else krb_text='недоступен'; fi
            if ((ldap_ok)); then ldap_text='доступен'; else ldap_text='недоступен'; fi
            if ((krb_ok && ldap_ok)); then
                dc_sev=ok
            elif ((krb_ok || ldap_ok)); then
                dc_sev=warn
            else
                dc_sev=crit
            fi
            if ((PRIVACY)); then dc_display='скрыто'; else dc_display=$target; fi
            add_check "$section" "domain.dc.node.$dc_index" "Контроллер #$dc_index" \\
              "$dc_display — Kerberos 88: $krb_text; LDAP 389: $ldap_text" "$dc_sev"
        done <<<"$targets"
        if ((tested>0)); then
            if ((reachable==tested)); then rc=ok; elif ((reachable>0)); then rc=warn; else rc=crit; fi
            add_check "$section" "domain.dc.ports" "KDC/LDAP доступность" "$reachable из $tested TCP-проверок" "$rc"
        else
            add_check "$section" "domain.dc.ports" "KDC/LDAP доступность" "не проверена" unknown "Нужны SRV-записи и nc/timeout"
        fi'''
    s = s[:start] + new + s[end:]

old_local = '    local gw ifaces idx=0 row iface ip mac speed duplex link dns_domain cifs_count=0 cifs_ok=0 cifs_bad=0 cifs_unknown=0 mnt gvfs_count=0 gvfs_bad=0 g dir'
new_local = '    local gw ifaces idx=0 row iface ip mac speed duplex link dns_domain cifs_count=0 cifs_ok=0 cifs_bad=0 cifs_unknown=0 mnt gvfs_count=0 gvfs_bad=0 gvfs_unknown=0 g dir gvfs_uid gvfs_user gvfs_dirs gvfs_state'
if old_local in s:
    s = s.replace(old_local, new_local, 1)

start = s.index('    for g in /run/user/*/gvfs; do')
end = s.index('    proc_caja=', start)
new = '''    for g in /run/user/*/gvfs; do
        [[ -d $g ]] || continue
        gvfs_uid=${g#/run/user/}; gvfs_uid=${gvfs_uid%%/*}
        gvfs_user=''
        if have getent; then gvfs_user=$(getent passwd "$gvfs_uid" 2>/dev/null | cut -d: -f1 | head -n1); fi
        [[ -n $gvfs_user ]] || gvfs_user=$(id -nu "$gvfs_uid" 2>/dev/null || true)

        if [[ -n $gvfs_user ]]; then
            gvfs_dirs=$(_cifs_exec_as "$gvfs_user" find "$g" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null || true)
        else
            gvfs_dirs=$(find "$g" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null || true)
        fi

        while IFS= read -r dir; do
            [[ -n $dir ]] || continue
            gvfs_count=$((gvfs_count+1))
            _cifs_probe "$dir" "$gvfs_user"
            gvfs_state=$CIFS_PROBE_STATE
            case "$gvfs_state" in
                OK) ;;
                INCONCLUSIVE) gvfs_unknown=$((gvfs_unknown+1)) ;;
                *) gvfs_bad=$((gvfs_bad+1)) ;;
            esac
        done <<<"$gvfs_dirs"
    done
    if ((gvfs_count==0)); then
        add_check "SMB / GVFS" "network.gvfs" "GVFS mounts" "нет" info
    elif ((gvfs_bad==0 && gvfs_unknown==0)); then
        add_check "SMB / GVFS" "network.gvfs" "GVFS mounts" "$gvfs_count, доступны" ok
    elif ((gvfs_bad==0)); then
        add_check "SMB / GVFS" "network.gvfs" "GVFS mounts" "$gvfs_count; не проверены: $gvfs_unknown" unknown
    else
        add_check "SMB / GVFS" "network.gvfs" "GVFS mounts" "$gvfs_count; проблемы: $gvfs_bad; не проверены: $gvfs_unknown" warn
    fi
'''
s = s[:start] + new + s[end:]
p.write_text(s)

t = Path('tests/test_enterprise.sh')
ts = t.read_text()
marker = 'grep -q \'enterprise) check_domain; check_network; check_print ;;\' "$SCRIPT" || die "enterprise profile must exclude software inventory"\n'
extra = '''grep -Fq 'domain.dc.node.$dc_index' "$SCRIPT" || die "per-DC detail key"\ngrep -Fq '"Контроллер #$dc_index"' "$SCRIPT" || die "per-DC detail label"\ngrep -Fq '_cifs_probe "$dir" "$gvfs_user"' "$SCRIPT" || die "GVFS must use real directory probe"\n! grep -Fq 'run_timeout 4 stat -f "$dir"' "$SCRIPT" || die "GVFS must not use metadata-only stat -f"\n'''
if 'per-DC detail key' not in ts:
    ts = ts.replace(marker, marker + extra, 1)
t.write_text(ts)

d = Path('docs/ENTERPRISE_PROFILES.md')
ds = d.read_text()
needle = '- доступность найденных контроллеров по TCP 88/389.\n'
repl = '- доступность найденных контроллеров по TCP 88/389; каждый найденный DC выводится отдельной строкой `Контроллер #N` со статусом Kerberos 88 и LDAP 389, после чего сохраняется общий итог TCP-проверок.\n'
if needle in ds:
    ds = ds.replace(needle, repl, 1)
old = 'Проверка CIFS/GVFS использует короткий timeout, чтобы сама диагностика не зависла на недоступном ресурсе. Для CIFS проверяется не только наличие mount: `arm_info` получает TARGET одной колонкой и выполняет минимальное чтение каталога. Это позволяет отличить смонтированный, но фактически не открывающийся ресурс; TARGET с пробелами и кириллицей сохраняются без разбиения/hex-экранирования.\n'
new = 'Проверка CIFS/GVFS использует короткий timeout, чтобы сама диагностика не зависла на недоступном ресурсе. Для CIFS проверяется не только наличие mount: `arm_info` получает TARGET одной колонкой и выполняет полный readdir каталога плюс metadata lookup одного элемента. GVFS-подключения теперь проверяются тем же фактическим чтением в контексте владельца `/run/user/<UID>/gvfs`, а не через metadata-only `stat -f`. Это позволяет выявлять зависший/недоступный ресурс Caja/GVFS и не выдавать ложный OK; TARGET с пробелами и кириллицей сохраняются без разбиения/hex-экранирования.\n'
if old in ds:
    ds = ds.replace(old, new, 1)
d.write_text(ds)

c = Path('CHANGELOG.md')
cs = c.read_text()
if '## Unreleased' not in cs:
    cs = cs.replace('# Changelog\n', '# Changelog\n\n## Unreleased\n\n### Changed\n- В корпоративном `DNS / Domains` каждый найденный контроллер домена выводится отдельной строкой со статусами TCP 88 (Kerberos) и 389 (LDAP), общий итог `N из M TCP-проверок` сохранён.\n- GVFS-подключения больше не считаются доступными по одному `stat -f`: выполняется реальный readdir + metadata lookup в пользовательском контексте, аналогично усиленной CIFS-проверке.\n', 1)
c.write_text(cs)
