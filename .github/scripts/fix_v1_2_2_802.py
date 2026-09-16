from pathlib import Path

root = Path(__file__).resolve().parents[2]
path = root / "arm_info.sh"
text = path.read_text(encoding="utf-8")

old_local = 'local eap_count=0 cert_global_min=-1 cert_unknown=0 cert_seen=0 cert_index=0 uuid type eap conn_name ca_cert client_cert cert_kind certpath cert_display cert_label'
new_local = old_local + ' cert_validity_label'
if old_local not in text:
    raise SystemExit('802 local declaration not found')
text = text.replace(old_local, new_local, 1)

old_client = 'certpath=$client_cert; cert_label="Клиентский сертификат"'
new_client = 'certpath=$client_cert; cert_label="Клиентский сертификат"; cert_validity_label="Срок клиентского сертификата"'
old_ca = 'certpath=$ca_cert; cert_label="CA-сертификат"'
new_ca = 'certpath=$ca_cert; cert_label="CA-сертификат"; cert_validity_label="Срок CA-сертификата"'
if old_client not in text or old_ca not in text:
    raise SystemExit('802 certificate labels not found')
text = text.replace(old_client, new_client, 1).replace(old_ca, new_ca, 1)

start = text.index('check_network() {')
end = text.index('\ncheck_print() {', start)
block = text[start:end]
block = block.replace('"Срок действия"', '"$cert_validity_label"')

lines = []
fixed_command = False
for line in block.splitlines(True):
    if '"Проверка срока"' in line and 'cert_cmd_path' in line:
        line = r'''                    add_check "802.1X" "network.8021x.cert.$cert_index.command" "Проверка срока" "openssl x509 -in \"$cert_cmd_path\" -noout -dates" info
'''
        fixed_command = True
    lines.append(line)
if not fixed_command:
    raise SystemExit('802 certificate command row not found')
block = ''.join(lines)
text = text[:start] + block + text[end:]
path.write_text(text, encoding="utf-8")
