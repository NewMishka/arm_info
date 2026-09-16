from pathlib import Path

root = Path('.')
p = root / 'arm_info.sh'
s = p.read_text(encoding='utf-8')

# 1) Root/system disk resolution: lsblk tree glyphs (└─) must never become part of NAME.
s = s.replace(
    'SYSTEM_DISKS=$(lsblk -sno NAME,TYPE "$ROOT_BLOCK" 2>/dev/null | awk \'$2=="disk"{print $1}\' | sort -u)',
    'SYSTEM_DISKS=$(lsblk -srno NAME,TYPE "$ROOT_BLOCK" 2>/dev/null | awk \'$2=="disk"{print $1}\' | sort -u)'
)
s = s.replace(
    '[[ -n "$ROOT_NODE" ]] && SYSTEM_DISKS=$(lsblk -sno NAME,TYPE "$ROOT_NODE" 2>/dev/null | awk \'$2=="disk"{print $1}\' | sort -u)',
    '[[ -n "$ROOT_NODE" ]] && SYSTEM_DISKS=$(lsblk -srno NAME,TYPE "$ROOT_NODE" 2>/dev/null | awk \'$2=="disk"{print $1}\' | sort -u)'
)

# Defensive normalization for older util-linux variants that may still decorate names.
old = '''SYSTEM_DISK_TEXT=$(printf '%s\n' "$SYSTEM_DISKS" | sed '/^$/d' | paste -sd ',' -)
[ -z "$SYSTEM_DISK_TEXT" ] && SYSTEM_DISK_TEXT="Не определён"'''
new = '''SYSTEM_DISKS=$(printf '%s\\n' "$SYSTEM_DISKS" | sed -E 's/^[^[:alnum:]_./-]+//' | sed '/^$/d' | sort -u)
SYSTEM_DISK_TEXT=$(printf '%s\\n' "$SYSTEM_DISKS" | sed '/^$/d' | paste -sd ',' -)
[ -z "$SYSTEM_DISK_TEXT" ] && SYSTEM_DISK_TEXT="Не определён"'''
if old not in s:
    raise SystemExit('system disk text marker not found')
s = s.replace(old, new, 1)

# Optical drives are visible inventory only and explicitly outside the technical index.
s = s.replace(
    'DISK_OPTICAL_ROWS+=("$NAME|Оптический|CD/DVD||$MODEL|-|-|-|-")',
    'DISK_OPTICAL_ROWS+=("$NAME|Оптический (вне индекса)|CD/DVD||$MODEL|-|-|-|-")'
)

# 2) 802.1X: inspect all configured NM profiles, not only currently active ones.
old_decl = '''    local eap_count=0 cert_global_min=-1 cert_unknown=0 cert_seen=0 cert_index=0 system_ca_profiles=0 uuid type eap conn_name
    local cert_spec cert_kind cert_field cert_label certref certpath cert_display cert_start cert_end start_fmt end_fmt end_epoch now days cert_cmd_path sev
    local cert_meta cert_subject cert_issuer cert_inform phase2_auth phase2_autheap system_ca ca_path private_key phase2_private_key
    local client_ref phase2_client_ref proc_caja proc_gvfs'''
new_decl = '''    local eap_count=0 active_eap_count=0 cert_global_min=-1 cert_unknown=0 cert_seen=0 cert_index=0 system_ca_profiles=0 uuid type eap conn_name
    local cert_spec cert_kind cert_field cert_label certref certpath cert_display cert_start cert_end start_fmt end_fmt end_epoch now days cert_cmd_path sev
    local cert_meta cert_subject cert_issuer cert_inform phase2_auth phase2_autheap system_ca ca_path private_key phase2_private_key
    local client_ref phase2_client_ref probe_client probe_ca probe_p2_client probe_p2_ca probe_key probe_p2_key active_uuid_list profile_state
    local fallback_cert_count=0 fallback_idx=0 fallback_fqdn fallback_short fallback_path fallback_meta fallback_start fallback_end fallback_start_fmt fallback_end_fmt fallback_end_epoch fallback_days
    local proc_caja proc_gvfs'''
if old_decl not in s:
    raise SystemExit('check_network declarations marker not found')
s = s.replace(old_decl, new_decl, 1)

old_loop_start = '''        while IFS=: read -r uuid type; do
            [[ -n $uuid ]] || continue
            case "$type" in ethernet|802-11-wireless|wifi) ;; *) continue;; esac
            eap=$(nm_802_value 802-1x.eap "$uuid")
            [[ -n $eap ]] || continue

            eap_count=$((eap_count+1))
            conn_name=$(nm_802_value connection.id "$uuid")
            if ((PRIVACY)); then conn_name="профиль $eap_count (скрыто)"; fi
            add_check "802.1X" "network.8021x.profile.$eap_count" "Профиль 802.1X #$eap_count" "${conn_name:-$uuid}" info
            add_check "802.1X" "network.8021x.eap.$eap_count" "EAP-метод" "$eap" info'''
new_loop_start = '''        active_uuid_list=$(nmcli -t -f UUID connection show --active 2>/dev/null || true)
        while IFS=: read -r uuid type; do
            [[ -n $uuid ]] || continue
            case "$type" in ethernet|802-11-wireless|wifi) ;; *) continue;; esac
            eap=$(nm_802_value 802-1x.eap "$uuid")
            probe_client=$(nm_802_value 802-1x.client-cert "$uuid")
            probe_ca=$(nm_802_value 802-1x.ca-cert "$uuid")
            probe_p2_client=$(nm_802_value 802-1x.phase2-client-cert "$uuid")
            probe_p2_ca=$(nm_802_value 802-1x.phase2-ca-cert "$uuid")
            probe_key=$(nm_802_value 802-1x.private-key "$uuid")
            probe_p2_key=$(nm_802_value 802-1x.phase2-private-key "$uuid")
            [[ -n $eap || -n $probe_client || -n $probe_ca || -n $probe_p2_client || -n $probe_p2_ca || -n $probe_key || -n $probe_p2_key ]] || continue

            eap_count=$((eap_count+1))
            profile_state="настроен, не активен"
            if grep -Fxq "$uuid" <<<"$active_uuid_list"; then
                profile_state="активен"
                active_eap_count=$((active_eap_count+1))
            fi
            conn_name=$(nm_802_value connection.id "$uuid")
            if ((PRIVACY)); then conn_name="профиль $eap_count (скрыто)"; fi
            add_check "802.1X" "network.8021x.profile.$eap_count" "Профиль 802.1X #$eap_count" "${conn_name:-$uuid}; $profile_state" info
            add_check "802.1X" "network.8021x.eap.$eap_count" "EAP-метод" "${eap:-не указан}" info'''
if old_loop_start not in s:
    raise SystemExit('802 loop start marker not found')
s = s.replace(old_loop_start, new_loop_start, 1)

s = s.replace(
    'done < <(nmcli -t -f UUID,TYPE connection show --active 2>/dev/null)',
    'done < <(nmcli -t -f UUID,TYPE connection show 2>/dev/null)',
    1
)

# Summary wording must no longer claim the counter is active-only.
s = s.replace(
    'add_check "802.1X" "network.8021x" "Активные 802.1X" "$eap_count; минимальный остаток сертификата ${cert_global_min} дн.; непроверенных: $cert_unknown" "$sev"',
    'add_check "802.1X" "network.8021x" "Профили 802.1X" "настроено: $eap_count; активных: $active_eap_count; минимальный остаток сертификата ${cert_global_min} дн.; непроверенных: $cert_unknown" "$sev"'
)
s = s.replace(
    'add_check "802.1X" "network.8021x" "Активные 802.1X" "$eap_count; сертификаты найдены, но даты не определены; непроверенных: $cert_unknown" unknown',
    'add_check "802.1X" "network.8021x" "Профили 802.1X" "настроено: $eap_count; активных: $active_eap_count; сертификаты найдены, но даты не определены; непроверенных: $cert_unknown" unknown'
)
s = s.replace(
    'add_check "802.1X" "network.8021x" "Активные 802.1X" "$eap_count; используется системное хранилище CA; отдельные сертификаты не заданы" info',
    'add_check "802.1X" "network.8021x" "Профили 802.1X" "настроено: $eap_count; активных: $active_eap_count; используется системное хранилище CA; отдельные сертификаты не заданы" info'
)
s = s.replace(
    'add_check "802.1X" "network.8021x" "Активные 802.1X" "$eap_count; ссылки на сертификаты в активном профиле не обнаружены" unknown',
    'add_check "802.1X" "network.8021x" "Профили 802.1X" "настроено: $eap_count; активных: $active_eap_count; ссылки на сертификаты не обнаружены" unknown'
)
s = s.replace(
    'add_check "802.1X" "network.8021x" "Активные 802.1X" "не обнаружены" info',
    'add_check "802.1X" "network.8021x" "Профили 802.1X NetworkManager" "не обнаружены" info'
)

# 3) Fallback for RED OS installations where 802.1X is configured outside the currently
# visible NM profile. The documented enterprise layout often stores a host certificate
# as /etc/pki/tls/<FQDN>.pem. We do not claim it is definitely bound to 802.1X; we show
# it as a candidate and expose its dates for the administrator.
marker = '''    else
        add_check "802.1X" "network.8021x" "802.1X" "nmcli отсутствует" unknown
    fi

    if have findmnt; then'''
fallback = '''    else
        add_check "802.1X" "network.8021x" "802.1X" "nmcli отсутствует" unknown
    fi

    # Дополнительный поиск сертификата АРМ. Нужен для РЕД ОС, где 802.1X может
    # быть задан legacy ifcfg/wpa_supplicant/внешним механизмом, а nmcli не показывает
    # 802-1x секцию активного профиля. Сертификат помечается как кандидат, пока связь
    # с конкретным профилем не подтверждена.
    if ((cert_seen==0)) && have openssl; then
        fallback_fqdn=$(hostname -f 2>/dev/null || true)
        fallback_short=$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)
        while IFS= read -r fallback_path; do
            [[ -n $fallback_path && -r $fallback_path ]] || continue
            fallback_meta=$(openssl x509 -in "$fallback_path" -noout -startdate -enddate -subject -issuer 2>/dev/null || true)
            [[ $fallback_meta == *notAfter=* ]] || continue
            fallback_cert_count=$((fallback_cert_count+1)); fallback_idx=$((fallback_idx+1))
            cert_display=$fallback_path; ((PRIVACY)) && cert_display='<HOST_CERT_CANDIDATE>'
            add_check "802.1X" "network.8021x.fallback.$fallback_idx.path" "Сертификат АРМ (кандидат 802.1X)" "$cert_display" info
            fallback_start=$(printf '%s\\n' "$fallback_meta" | sed -n 's/^notBefore=//p' | head -n1)
            fallback_end=$(printf '%s\\n' "$fallback_meta" | sed -n 's/^notAfter=//p' | head -n1)
            fallback_start_fmt=$(date -d "$fallback_start" '+%d.%m.%Y %H:%M:%S %Z' 2>/dev/null || printf '%s' "$fallback_start")
            fallback_end_fmt=$(date -d "$fallback_end" '+%d.%m.%Y %H:%M:%S %Z' 2>/dev/null || printf '%s' "$fallback_end")
            fallback_end_epoch=$(date -d "$fallback_end" +%s 2>/dev/null || true); now=$(date +%s)
            add_check "802.1X" "network.8021x.fallback.$fallback_idx.not_before" "Начало действия — сертификат АРМ" "$fallback_start_fmt" info
            if [[ $fallback_end_epoch =~ ^[0-9]+$ ]]; then
                fallback_days=$(((fallback_end_epoch-now)/86400))
                if ((fallback_days<14)); then sev=crit; elif ((fallback_days<30)); then sev=warn; else sev=ok; fi
                add_check "802.1X" "network.8021x.fallback.$fallback_idx.not_after" "Окончание действия — сертификат АРМ" "$fallback_end_fmt" "$sev"
                add_check "802.1X" "network.8021x.fallback.$fallback_idx.remaining" "Осталось — сертификат АРМ" "${fallback_days} дн." "$sev"
            else
                add_check "802.1X" "network.8021x.fallback.$fallback_idx.not_after" "Окончание действия — сертификат АРМ" "$fallback_end_fmt" unknown
            fi
            cert_cmd_path=$fallback_path; ((PRIVACY)) && cert_cmd_path='<CERT>'
            add_check "802.1X" "network.8021x.fallback.$fallback_idx.command" "Проверка срока" "openssl x509 -in \\\"$cert_cmd_path\\\" -noout -dates -subject -issuer" info
        done < <({
            [[ -n $fallback_fqdn ]] && printf '%s\\n' "/etc/pki/tls/${fallback_fqdn}.pem" "/etc/pki/tls/certs/${fallback_fqdn}.pem"
            if [[ -n $fallback_short && -d /etc/pki/tls ]]; then
                find /etc/pki/tls /etc/pki/tls/certs -maxdepth 1 -type f -iname "${fallback_short}*.pem" 2>/dev/null
            fi
        } | awk '!seen[$0]++' | head -n5)
        if ((fallback_cert_count>0)); then
            add_check "802.1X" "network.8021x.fallback.source" "Источник сертификата 802.1X" "профиль NetworkManager не подтвердил сертификат; найден host-named сертификат АРМ" unknown
        fi
    fi

    if have findmnt; then'''
if marker not in s:
    raise SystemExit('802 fallback insertion marker not found')
s = s.replace(marker, fallback, 1)

p.write_text(s, encoding='utf-8')

# Docs/changelog: concise field-fix notes.
def append_after(path, marker, text):
    q = root / path
    x = q.read_text(encoding='utf-8')
    if text.strip() in x:
        return
    if marker not in x:
        raise SystemExit(f'marker not found in {path}')
    x = x.replace(marker, marker + text, 1)
    q.write_text(x, encoding='utf-8')

append_after('CHANGELOG.md', '### Changed\n', '- Исправлено определение системного диска на LVM/device-mapper: tree-префикс `lsblk` больше не попадает в имя устройства; диск корневой ФС корректно получает роль **Системный**.\n- Оптические приводы помечаются как **Оптический (вне индекса)**.\n- 802.1X анализирует все настроенные NetworkManager-профили, отдельно показывает число активных, а при отсутствии certificate reference выполняет безопасный fallback-поиск host-named X.509 в `/etc/pki/tls` и выводит даты как сертификат-кандидат.\n')
append_after('docs/releases/v1.2.3.md', '## Что изменено\n', '- Исправлена полевая ошибка: имя системного диска очищается от tree-префикса `lsblk`, поэтому root-диск не может ошибочно стать `Дополнительный`.\n- Оптические устройства явно выводятся `вне индекса`.\n- 802.1X больше не ограничивается только активными NM-профилями: проверяются все настроенные профили и host-named certificate fallback в `/etc/pki/tls`.\n')

# Tests: lock the regressions.
q = root / 'tests/test_cli.sh'
x = q.read_text(encoding='utf-8')
anchor = "grep -q 'SYSTEM_DISKS=' \"$SCRIPT\" || die \"system disk resolver\"\n"
ins = "grep -q 'lsblk -srno NAME,TYPE' \"$SCRIPT\" || die \"system disk resolver must use raw lsblk output\"\ngrep -q 'Оптический (вне индекса)' \"$SCRIPT\" || die \"optical drive must be outside index\"\n"
if ins not in x:
    if anchor not in x: raise SystemExit('test_cli anchor missing')
    x = x.replace(anchor, anchor + ins, 1)
q.write_text(x, encoding='utf-8')

q = root / 'tests/test_enterprise.sh'
x = q.read_text(encoding='utf-8')
anchor = "grep -q 'split_rec_commands' \"$SCRIPT\" || die \"corporate command splitter\"\n"
ins = "grep -Fq 'nmcli -t -f UUID,TYPE connection show 2>/dev/null' \"$SCRIPT\" || die \"802.1X must inspect all configured NM profiles\"\ngrep -q 'Сертификат АРМ (кандидат 802.1X)' \"$SCRIPT\" || die \"802.1X host certificate fallback\"\ngrep -q 'Профили 802.1X' \"$SCRIPT\" || die \"802.1X configured/active summary\"\n"
if ins not in x:
    if anchor not in x: raise SystemExit('test_enterprise anchor missing')
    x = x.replace(anchor, anchor + ins, 1)
q.write_text(x, encoding='utf-8')
