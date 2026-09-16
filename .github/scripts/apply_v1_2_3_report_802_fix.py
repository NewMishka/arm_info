from pathlib import Path
import re

ROOT = Path('.')
script = ROOT / 'arm_info.sh'
s = script.read_text(encoding='utf-8')


def replace_once(old: str, new: str, label: str):
    global s
    if old not in s:
        raise SystemExit(f'marker not found: {label}')
    s = s.replace(old, new, 1)

# Corporate header: user-facing wording is Russian; internal profile key/schema remains enterprise.
replace_once(
    "    printf 'ARM_INFO ENTERPRISE %s\\n' \"$VERSION\"\n    printf 'Профиль: %s\\n' \"$PROFILE\"",
    "    printf 'ARM_INFO КОРПОРАТИВНЫЙ %s\\n' \"$VERSION\"\n    if [[ $PROFILE == enterprise ]]; then\n        printf 'Профиль: корпоративный\\n'\n    else\n        printf 'Профиль: %s\\n' \"$PROFILE\"\n    fi",
    'corporate header',
)

# Standard recommendations: use the same visual alignment model as corporate recommendations.
old_wrap = '''print_wrapped() {
    local label="$1" text="$2" indent=3 label_w=19 gap=1 value_w first=1 ln
    value_w=$((WIDTH-indent-label_w-gap))
    ((value_w<32)) && value_w=32
    while IFS= read -r ln || [[ -n $ln ]]; do
        if ((first)); then
            printf '%*s%-*s %s\\n' "$indent" '' "$label_w" "$label" "$ln"
            first=0
        else
            printf '%*s%-*s %s\\n' "$indent" '' "$label_w" '' "$ln"
        fi
    done < <(printf '%s\\n' "$text" | fold -s -w "$value_w")
    ((first==0)) || printf '%*s%s\\n' "$indent" '' "$label"
}
'''
new_wrap = '''base_pad_right() {
    local value=$1 width=$2 len=${#1}
    printf '%s' "$value"
    ((len<width)) && printf '%*s' "$((width-len))" ''
}

print_wrapped() {
    local label="$1" text="$2" indent=3 label_w=23 gap=1 value_w first=1 ln
    value_w=$((WIDTH-indent-label_w-gap))
    ((value_w<32)) && value_w=32
    while IFS= read -r ln || [[ -n $ln ]]; do
        if ((first)); then
            printf '%*s%s %s\\n' "$indent" '' "$(base_pad_right "$label" "$label_w")" "$ln"
            first=0
        else
            printf '%*s%s %s\\n' "$indent" '' "$(base_pad_right '' "$label_w")" "$ln"
        fi
    done < <(printf '%s\\n' "$text" | fold -s -w "$value_w")
    ((first==0)) || printf '%*s%s\\n' "$indent" '' "$label"
}
'''
replace_once(old_wrap, new_wrap, 'standard recommendation alignment')

old_render = '''   print_wrapped "Причины:" "${REC_CAUSES[$i]}"
   print_wrapped "Влияние:" "${REC_IMPACTS[$i]}"
   print_wrapped "Проверить:" "${REC_DIAGNOSTICS[$i]}"
   print_wrapped "Действие:" "${REC_ACTIONS[$i]}"
   if [ -n "${REC_CHECKS[$i]}" ]; then
       _rec_cmd_desc=$(base_command_description "${REC_CHECKS[$i]}")
       print_wrapped "Команда:" "${REC_CHECKS[$i]} ($_rec_cmd_desc)"
   fi
   print_wrapped "Контроль:" "${REC_VERIFICATIONS[$i]}"'''
new_render = '''   print_wrapped "Возможные причины:" "${REC_CAUSES[$i]}"
   print_wrapped "Влияние:" "${REC_IMPACTS[$i]}"
   print_wrapped "Что проверить:" "${REC_DIAGNOSTICS[$i]}"
   print_wrapped "Действие:" "${REC_ACTIONS[$i]}"
   if [ -n "${REC_CHECKS[$i]}" ]; then
       _rec_cmd_desc=$(base_command_description "${REC_CHECKS[$i]}")
       print_wrapped "Команда 1:" "${REC_CHECKS[$i]} ($_rec_cmd_desc)"
   fi
   print_wrapped "Контроль результата:" "${REC_VERIFICATIONS[$i]}"'''
replace_once(old_render, new_render, 'standard recommendation labels/command')

# Expand locals needed by robust 802.1X certificate inspection.
old_locals = '''    local eap_count=0 cert_global_min=-1 cert_unknown=0 cert_seen=0 cert_index=0 uuid type eap conn_name ca_cert client_cert cert_kind certpath cert_display cert_label cert_validity_label
    local cert_start cert_end start_fmt end_fmt end_epoch now days cert_cmd_path sev proc_caja proc_gvfs'''
new_locals = '''    local eap_count=0 cert_global_min=-1 cert_unknown=0 cert_seen=0 cert_index=0 system_ca_profiles=0 uuid type eap conn_name
    local cert_spec cert_kind cert_field cert_label certref certpath cert_display cert_start cert_end start_fmt end_fmt end_epoch now days cert_cmd_path sev
    local cert_meta cert_subject cert_issuer cert_inform phase2_auth phase2_autheap system_ca ca_path private_key phase2_private_key
    local client_ref phase2_client_ref proc_caja proc_gvfs'''
replace_once(old_locals, new_locals, '802 locals')

start_marker = '''    if have nmcli; then
        while IFS=: read -r uuid type; do'''
end_marker = '''

    if have findmnt; then'''
start = s.find(start_marker)
if start < 0:
    raise SystemExit('802 block start not found')
end = s.find(end_marker, start)
if end < 0:
    raise SystemExit('802 block end not found')

new_802 = r'''    if have nmcli; then
        # -g включает terse output; на ряде версий NetworkManager двоеточия в file://
        # экранируются. Сначала запрашиваем --escape no, затем используем fallback.
        nm_802_value() {
            local field=$1 id=$2 v
            v=$(nmcli -e no -g "$field" connection show uuid "$id" 2>/dev/null | head -n1)
            if [[ -z $v ]]; then
                v=$(nmcli -g "$field" connection show uuid "$id" 2>/dev/null | head -n1)
                v=${v//\\:/:}
                v=${v//\\\\/\\}
            fi
            printf '%s' "$v"
        }

        while IFS=: read -r uuid type; do
            [[ -n $uuid ]] || continue
            case "$type" in ethernet|802-11-wireless|wifi) ;; *) continue;; esac
            eap=$(nm_802_value 802-1x.eap "$uuid")
            [[ -n $eap ]] || continue

            eap_count=$((eap_count+1))
            conn_name=$(nm_802_value connection.id "$uuid")
            if ((PRIVACY)); then conn_name="профиль $eap_count (скрыто)"; fi
            add_check "802.1X" "network.8021x.profile.$eap_count" "Профиль 802.1X #$eap_count" "${conn_name:-$uuid}" info
            add_check "802.1X" "network.8021x.eap.$eap_count" "EAP-метод" "$eap" info

            phase2_auth=$(nm_802_value 802-1x.phase2-auth "$uuid")
            phase2_autheap=$(nm_802_value 802-1x.phase2-autheap "$uuid")
            [[ -n $phase2_auth ]] && add_check "802.1X" "network.8021x.phase2-auth.$eap_count" "Phase2 auth" "$phase2_auth" info
            [[ -n $phase2_autheap ]] && add_check "802.1X" "network.8021x.phase2-autheap.$eap_count" "Phase2 EAP" "$phase2_autheap" info

            system_ca=$(nm_802_value 802-1x.system-ca-certs "$uuid")
            ca_path=$(nm_802_value 802-1x.ca-path "$uuid")
            if [[ $system_ca == yes || $system_ca == true || $system_ca == 1 ]]; then
                system_ca_profiles=$((system_ca_profiles+1))
                add_check "802.1X" "network.8021x.system-ca.$eap_count" "Системное хранилище CA" "используется" info
            fi
            if [[ -n $ca_path ]]; then
                if ((PRIVACY)); then ca_path='<CA_PATH>'; fi
                add_check "802.1X" "network.8021x.ca-path.$eap_count" "Каталог CA" "$ca_path" info
            fi

            client_ref=$(nm_802_value 802-1x.client-cert "$uuid")
            phase2_client_ref=$(nm_802_value 802-1x.phase2-client-cert "$uuid")
            private_key=$(nm_802_value 802-1x.private-key "$uuid")
            phase2_private_key=$(nm_802_value 802-1x.phase2-private-key "$uuid")

            # Проверяем внешний и phase2 наборы сертификатов. Поддерживаются file://,
            # обычные пути, PEM и DER. PKCS#11/blob отображаются, но без интерактивного
            # запроса PIN их срок не считается достоверно доступным.
            for cert_spec in \
                "client|802-1x.client-cert|Клиентский сертификат" \
                "ca|802-1x.ca-cert|CA-сертификат" \
                "phase2-client|802-1x.phase2-client-cert|Phase2 клиентский сертификат" \
                "phase2-ca|802-1x.phase2-ca-cert|Phase2 CA-сертификат"
            do
                IFS='|' read -r cert_kind cert_field cert_label <<<"$cert_spec"
                certref=$(nm_802_value "$cert_field" "$uuid")
                [[ -n $certref ]] || continue

                cert_seen=$((cert_seen+1)); cert_index=$((cert_index+1))
                certpath=$certref
                certpath=${certpath#file://}
                certpath=${certpath#file:}
                cert_display=$certref
                if ((PRIVACY)); then
                    case "$cert_kind" in
                        client) cert_display='<CLIENT_CERT>' ;;
                        ca) cert_display='<CA_CERT>' ;;
                        phase2-client) cert_display='<PHASE2_CLIENT_CERT>' ;;
                        *) cert_display='<PHASE2_CA_CERT>' ;;
                    esac
                fi
                add_check "802.1X" "network.8021x.cert.$cert_index.path" "$cert_label" "$cert_display" info

                case "$certref" in
                    pkcs11:*)
                        cert_unknown=$((cert_unknown+1))
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Даты — $cert_label" "не проверены автоматически: сертификат задан PKCS#11 URI" unknown
                        continue
                        ;;
                    blob:*|blob://*)
                        cert_unknown=$((cert_unknown+1))
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Даты — $cert_label" "не проверены автоматически: сертификат хранится как blob" unknown
                        continue
                        ;;
                esac

                if [[ -r $certpath ]] && have openssl; then
                    cert_inform=''
                    cert_meta=$(openssl x509 -in "$certpath" -noout -startdate -enddate -subject -issuer 2>/dev/null || true)
                    if [[ $cert_meta != *notAfter=* ]]; then
                        cert_meta=$(openssl x509 -inform DER -in "$certpath" -noout -startdate -enddate -subject -issuer 2>/dev/null || true)
                        [[ $cert_meta == *notAfter=* ]] && cert_inform='-inform DER '
                    fi

                    if [[ $cert_meta == *notAfter=* ]]; then
                        cert_start=$(printf '%s\n' "$cert_meta" | sed -n 's/^notBefore=//p' | head -n1)
                        cert_end=$(printf '%s\n' "$cert_meta" | sed -n 's/^notAfter=//p' | head -n1)
                        cert_subject=$(printf '%s\n' "$cert_meta" | sed -n 's/^subject=//p' | head -n1)
                        cert_issuer=$(printf '%s\n' "$cert_meta" | sed -n 's/^issuer=//p' | head -n1)
                        start_fmt=$(date -d "$cert_start" '+%d.%m.%Y %H:%M:%S %Z' 2>/dev/null || printf '%s' "$cert_start")
                        end_fmt=$(date -d "$cert_end" '+%d.%m.%Y %H:%M:%S %Z' 2>/dev/null || printf '%s' "$cert_end")
                        end_epoch=$(date -d "$cert_end" +%s 2>/dev/null || true); now=$(date +%s)

                        if ((PRIVACY)); then cert_subject='скрыто'; cert_issuer='скрыто'; fi
                        [[ -n $cert_subject ]] && add_check "802.1X" "network.8021x.cert.$cert_index.subject" "Subject — $cert_label" "$cert_subject" info
                        [[ -n $cert_issuer ]] && add_check "802.1X" "network.8021x.cert.$cert_index.issuer" "Issuer — $cert_label" "$cert_issuer" info
                        add_check "802.1X" "network.8021x.cert.$cert_index.not_before" "Начало действия — $cert_label" "$start_fmt" info

                        if [[ $end_epoch =~ ^[0-9]+$ ]]; then
                            days=$(((end_epoch-now)/86400))
                            ((cert_global_min<0 || days<cert_global_min)) && cert_global_min=$days
                            if ((days<14)); then sev=crit; elif ((days<30)); then sev=warn; else sev=ok; fi
                            add_check "802.1X" "network.8021x.cert.$cert_index.not_after" "Окончание действия — $cert_label" "$end_fmt" "$sev"
                            add_check "802.1X" "network.8021x.cert.$cert_index.remaining" "Осталось — $cert_label" "${days} дн." "$sev"
                        else
                            cert_unknown=$((cert_unknown+1))
                            add_check "802.1X" "network.8021x.cert.$cert_index.not_after" "Окончание действия — $cert_label" "$end_fmt (дату не удалось преобразовать)" unknown
                        fi

                        cert_cmd_path=$certpath; ((PRIVACY)) && cert_cmd_path='<CERT>'
                        add_check "802.1X" "network.8021x.cert.$cert_index.command" "Проверка срока" "openssl x509 ${cert_inform}-in \"$cert_cmd_path\" -noout -dates -subject -issuer" info
                    else
                        cert_unknown=$((cert_unknown+1))
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Даты — $cert_label" "не прочитаны как PEM или DER" unknown
                        cert_cmd_path=$certpath; ((PRIVACY)) && cert_cmd_path='<CERT>'
                        add_check "802.1X" "network.8021x.cert.$cert_index.command" "Проверка PEM/DER" "openssl x509 -in \"$cert_cmd_path\" -noout -dates || openssl x509 -inform DER -in \"$cert_cmd_path\" -noout -dates" info
                    fi
                else
                    cert_unknown=$((cert_unknown+1))
                    if ! have openssl; then
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Даты — $cert_label" "не проверены: openssl отсутствует" unknown
                    else
                        add_check "802.1X" "network.8021x.cert.$cert_index.validity" "Даты — $cert_label" "не проверены: файл сертификата недоступен: $cert_display" unknown
                    fi
                fi
            done

            # Если EAP-TLS/phase2 TLS использует private-key/PKCS#12, но client-cert
            # отдельно не задан, показываем источник, чтобы профиль не выглядел пустым.
            if [[ -z $client_ref && -n $private_key ]]; then
                cert_display=$private_key; ((PRIVACY)) && cert_display='<PRIVATE_KEY_OR_PKCS12>'
                add_check "802.1X" "network.8021x.private-key.$eap_count" "Источник ключа/PKCS#12" "$cert_display" info
            fi
            if [[ -z $phase2_client_ref && -n $phase2_private_key ]]; then
                cert_display=$phase2_private_key; ((PRIVACY)) && cert_display='<PHASE2_PRIVATE_KEY_OR_PKCS12>'
                add_check "802.1X" "network.8021x.phase2-private-key.$eap_count" "Phase2 ключ/PKCS#12" "$cert_display" info
            fi
            if [[ ($eap == *tls* || $phase2_auth == tls || $phase2_autheap == tls) && -z $client_ref && -z $phase2_client_ref && -z $private_key && -z $phase2_private_key ]]; then
                add_check "802.1X" "network.8021x.client-cert.missing.$eap_count" "Клиентский сертификат" "для TLS не найден в профиле" warn
            fi
        done < <(nmcli -t -f UUID,TYPE connection show --active 2>/dev/null)

        if ((eap_count>0)); then
            if ((cert_global_min>=0)); then
                if ((cert_global_min<14)); then sev=crit
                elif ((cert_global_min<30)); then sev=warn
                elif ((cert_unknown>0)); then sev=warn
                else sev=ok
                fi
                add_check "802.1X" "network.8021x" "Активные 802.1X" "$eap_count; минимальный остаток сертификата ${cert_global_min} дн.; непроверенных: $cert_unknown" "$sev"
            elif ((cert_seen>0)); then
                add_check "802.1X" "network.8021x" "Активные 802.1X" "$eap_count; сертификаты найдены, но даты не определены; непроверенных: $cert_unknown" unknown
            elif ((system_ca_profiles>0)); then
                add_check "802.1X" "network.8021x" "Активные 802.1X" "$eap_count; используется системное хранилище CA; отдельные сертификаты не заданы" info
            else
                add_check "802.1X" "network.8021x" "Активные 802.1X" "$eap_count; ссылки на сертификаты в активном профиле не обнаружены" unknown
            fi
        else
            add_check "802.1X" "network.8021x" "Активные 802.1X" "не обнаружены" info
        fi
    else
        add_check "802.1X" "network.8021x" "802.1X" "nmcli отсутствует" unknown
    fi'''

s = s[:start] + new_802 + s[end:]

script.write_text(s, encoding='utf-8')

# Test contracts.
t = ROOT / 'tests/test_cli.sh'
x = t.read_text(encoding='utf-8')
x = x.replace("grep -q 'print_wrapped \"Причины:\"' \"$SCRIPT\" || die \"base recommendation causes\"\ngrep -q 'print_wrapped \"Проверить:\"' \"$SCRIPT\" || die \"base recommendation checks\"\ngrep -q 'print_wrapped \"Контроль:\"' \"$SCRIPT\" || die \"base recommendation verification\"",
              "grep -q 'print_wrapped \"Возможные причины:\"' \"$SCRIPT\" || die \"base recommendation causes\"\ngrep -q 'print_wrapped \"Что проверить:\"' \"$SCRIPT\" || die \"base recommendation checks\"\ngrep -q 'print_wrapped \"Контроль результата:\"' \"$SCRIPT\" || die \"base recommendation verification\"\ngrep -q 'print_wrapped \"Команда 1:\"' \"$SCRIPT\" || die \"base recommendation numbered command\"\ngrep -q 'label_w=23' \"$SCRIPT\" || die \"base recommendation corporate-style alignment\"")
t.write_text(x, encoding='utf-8')

t = ROOT / 'tests/test_enterprise.sh'
x = t.read_text(encoding='utf-8')
extra = '''\n# v1.2.3 corporate header and 802.1X certificate contract.\ngrep -q "ARM_INFO КОРПОРАТИВНЫЙ" "$SCRIPT" || die "corporate Russian header"\ngrep -q "Профиль: корпоративный" "$SCRIPT" || die "corporate profile label"\ngrep -q 'nmcli -e no -g' "$SCRIPT" || die "802.1X nmcli unescaped certificate path"\ngrep -q '802-1x.phase2-client-cert' "$SCRIPT" || die "802.1X phase2 client certificate"\ngrep -q 'Начало действия —' "$SCRIPT" || die "802.1X notBefore output"\ngrep -q 'Окончание действия —' "$SCRIPT" || die "802.1X notAfter output"\ngrep -q 'openssl x509 -inform DER' "$SCRIPT" || die "802.1X DER certificate support"\n'''
if 'v1.2.3 corporate header and 802.1X certificate contract' not in x:
    x += extra
t.write_text(x, encoding='utf-8')

# Documentation updates.
changes = ROOT / 'CHANGELOG.md'
x = changes.read_text(encoding='utf-8')
needle = '- JSON storage дополнен счётчиками системных, дополнительных и съёмных накопителей.\n'
addition = needle + '- Стандартные рекомендации выровнены по той же сетке, что и корпоративные; длинные команды выводятся с меткой `Команда 1:` и единым отступом.\n- В шапке `--corp`/`--profile enterprise` пользовательское название изменено с `ENTERPRISE` на `КОРПОРАТИВНЫЙ` (machine-readable profile/schema не меняются).\n- Проверка 802.1X корректно читает неэкранированные `file://` значения NetworkManager, поддерживает PEM/DER, phase2 certificates и отдельно показывает Subject/Issuer, начало, окончание и остаток срока.\n'
if 'Стандартные рекомендации выровнены по той же сетке' not in x:
    x = x.replace(needle, addition, 1)
changes.write_text(x, encoding='utf-8')

rel = ROOT / 'docs/releases/v1.2.3.md'
x = rel.read_text(encoding='utf-8')
marker = '- JSON storage содержит отдельные счётчики системных, дополнительных и съёмных накопителей.\n'
add = marker + '- стандартный блок рекомендаций использует такое же выравнивание полей и команд, как корпоративный;\n- корпоративная шапка отображается как `ARM_INFO КОРПОРАТИВНЫЙ`; внутренний ключ профиля `enterprise` и JSON schema v2 сохранены для совместимости;\n- 802.1X показывает сертификаты из основного и phase2 профиля, поддерживает PEM/DER и выводит Subject/Issuer, даты начала/окончания и остаток срока; `nmcli` запрашивается без escape для корректной обработки `file://`.\n'
if 'корпоративная шапка отображается' not in x:
    x = x.replace(marker, add, 1)
rel.write_text(x, encoding='utf-8')

usage = ROOT / 'docs/USAGE.md'
x = usage.read_text(encoding='utf-8')
append = '''\n### Формат рекомендаций и 802.1X в 1.2.3\n\nСтандартный анализ использует ту же сетку рекомендаций, что и корпоративный: `Возможные причины`, `Влияние`, `Что проверить`, `Действие`, `Команда N`, `Контроль результата`. Для корпоративного профиля пользовательская шапка содержит слово `КОРПОРАТИВНЫЙ`; CLI-ключ `--profile enterprise` сохранён.\n\nВ сетевом/корпоративном профиле 802.1X выводятся основной и phase2 client/CA certificate, Subject/Issuer, `notBefore`, `notAfter` и остаток срока, когда сертификат доступен как PEM/DER-файл. PKCS#11/blob отображаются как источник, но срок помечается как непроверенный без интерактивного доступа к токену.\n'''
if '### Формат рекомендаций и 802.1X в 1.2.3' not in x:
    x += append
usage.write_text(x, encoding='utf-8')

testing = ROOT / 'docs/TESTING.md'
x = testing.read_text(encoding='utf-8')
append = '''\n## Дополнительный smoke-test 1.2.3: 802.1X\n\nНа АРМ с активным 802.1X-профилем проверить `sudo bash arm_info.sh --profile network` и `sudo bash arm_info.sh --corp`. Для file-based PEM/DER сертификата отчёт должен показать путь/источник, Subject/Issuer, даты начала и окончания действия и остаток дней. Отдельно проверить phase2 certificate, если он используется. В privacy-режиме путь и Subject/Issuer не должны раскрываться.\n'''
if '## Дополнительный smoke-test 1.2.3: 802.1X' not in x:
    x += append
testing.write_text(x, encoding='utf-8')

ent = ROOT / 'docs/ENTERPRISE_PROFILES.md'
x = ent.read_text(encoding='utf-8')
append = '''\n## Отображение 802.1X сертификатов\n\n`network` и `enterprise` проверяют `802-1x.client-cert`, `802-1x.ca-cert`, `802-1x.phase2-client-cert` и `802-1x.phase2-ca-cert`. Для PEM/DER-файлов выводятся Subject/Issuer, дата начала, дата окончания и остаток срока. Значения `file://` читаются через `nmcli --escape no`; PKCS#11/blob фиксируются как источник без попытки интерактивного запроса PIN.\n'''
if '## Отображение 802.1X сертификатов' not in x:
    x += append
ent.write_text(x, encoding='utf-8')

print('v1.2.3 report/header/802.1X patch applied')
