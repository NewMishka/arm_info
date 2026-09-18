#!/usr/bin/env bash
# Mail profile: generic prefs discovery, bounded DNS/TCP/TLS and privacy.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
ORIGINAL_PATH=$PATH
trap 'PATH=$ORIGINAL_PATH; rm -rf -- "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

sed -n '/^_arm_run_limited() {/,/^}/p' "$ROOT/arm_info.sh" >"$TMP/runner.sh"
awk '/^have\(\)/{copy=1} /^check_software\(\)/{copy=0} copy' "$ROOT/arm_info.sh" >"$TMP/functions.sh"
# shellcheck disable=SC1091
source "$TMP/runner.sh"
# shellcheck disable=SC1091
source "$TMP/functions.sh"

reset_checks() {
    KEYS=(); LABELS=(); VALUES=(); SEVERITIES=(); SECTIONS=(); DETAILS=()
    WARN_COUNT=0; CRIT_COUNT=0; UNKNOWN_COUNT=0
    REC_KEYS=(); REC_COMMANDS=()
}

cat >"$TMP/prefs.js" <<'PREFS'
user_pref("mail.server.server1.hostname", "mail.example.test");
user_pref("mail.server.server1.port", 993);
user_pref("mail.server.server1.socketType", 3);
user_pref("mail.server.server1.type", "imap");
user_pref("mail.server.server1.authMethod", 5);
user_pref("mail.server.server1.userName", "worker@example.test");
user_pref("mail.smtpserver.smtp1.hostname", "mail.example.test");
user_pref("mail.smtpserver.smtp1.port", 587);
user_pref("mail.smtpserver.smtp1.try_ssl", 2);
user_pref("mail.smtpserver.smtp1.authMethod", 5);
user_pref("mail.smtpserver.smtp1.username", "worker@example.test");
PREFS

mkdir "$TMP/bin"
cat >"$TMP/bin/getent" <<'MOCK'
#!/usr/bin/env bash
if [[ $1 == passwd ]]; then
    printf '%s:x:1000:1000::/nonexistent:/bin/bash\n' "$2"
elif [[ $1 == ahosts ]]; then
    printf '192.0.2.25 STREAM %s\n' "$2"
    printf '%s\n' "$2" >>"$MAIL_TEST_TMP/getent-calls"
else
    exit 2
fi
MOCK
cat >"$TMP/bin/nc" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MAIL_TEST_TMP/nc-calls"
exit 0
MOCK
cat >"$TMP/bin/dig" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
    *' example.test MX') printf '10 mx.example.test.\n' ;;
    *'_imaps._tcp.example.test SRV') printf '0 1 993 mail.example.test.\n' ;;
    *'_submission._tcp.example.test SRV') printf '0 1 587 mail.example.test.\n' ;;
    *) exit 0 ;;
esac
MOCK
cat >"$TMP/bin/openssl" <<'MOCK'
#!/usr/bin/env bash
if [[ $1 == s_client && $2 == -help ]]; then
    echo '-verify_hostname -verify_ip'
    exit 0
fi
if [[ $1 == s_client ]]; then
    printf '%s\n' "$*" >>"$MAIL_TEST_TMP/openssl-calls"
    cat <<'OUT'
-----BEGIN CERTIFICATE-----
RklYVFVSRQ==
-----END CERTIFICATE-----
Verify return code: 0 (ok)
* CAPABILITY IMAP4rev1 AUTH=GSSAPI AUTH=PLAIN
250-AUTH GSSAPI PLAIN
OUT
    exit 0
fi
if [[ $1 == x509 ]]; then
    cat <<OUT
subject=CN = mail.example.test
issuer=CN = Fixture CA
notAfter=$MAIL_TEST_CERT_END
OUT
    exit 0
fi
exit 2
MOCK
chmod +x "$TMP/bin/getent" "$TMP/bin/nc" "$TMP/bin/dig" "$TMP/bin/openssl"
export MAIL_TEST_TMP=$TMP
export MAIL_TEST_CERT_END
MAIL_TEST_CERT_END=$(date -d '+180 days' '+%b %d %H:%M:%S %Y GMT')
PATH="$TMP/bin:$ORIGINAL_PATH"
hash -r

PRIVACY=0
PROFILE=mail
ARM_INFO_SELF_CMD=arm_info
ARM_INFO_NETWORK_BUDGET=30
ARM_INFO_DC_PROBE_TIMEOUT=3
NETWORK_PROBE_DEADLINE=0
ARM_INFO_MAIL_PREFS="$TMP/prefs.js"
ARM_INFO_MAIL_ENDPOINTS=''
ARM_INFO_MAIL_DOMAINS=''
MAIL_ENDPOINT_SPECS=()
MAIL_DOMAIN_SPECS=()
reset_checks
check_mail

[[ ${VALUES[*]} == *'обнаружено: 2'* ]] || fail 'prefs endpoints not discovered'
[[ ${VALUES[*]} == *'IMAP mail.example.test:993; TLS'* ]] || fail 'implicit IMAP TLS not detected'
[[ ${VALUES[*]} == *'SMTP mail.example.test:587; STARTTLS'* ]] || fail 'SMTP STARTTLS not detected'
[[ ${VALUES[*]} == *'профиль: GSSAPI/Kerberos'* ]] || fail 'configured GSSAPI not reported'
[[ ${VALUES[*]} == *'цепочка и имя подтверждены'* ]] || fail 'verified TLS not reported'
[[ ${VALUES[*]} == *'10 mx.example.test.'* ]] || fail 'MX result missing'
[[ $(wc -l <"$TMP/getent-calls") == 1 ]] || fail 'DNS cache did not deduplicate the shared host'
[[ $(wc -l <"$TMP/nc-calls") == 2 ]] || fail 'both endpoint ports must be checked'
grep -q -- '-starttls smtp' "$TMP/openssl-calls" || fail 'SMTP STARTTLS option missing'
grep -q -- '-verify_hostname mail.example.test' "$TMP/openssl-calls" || fail 'TLS hostname verification missing'
[[ ${!KEYS[*]} ]] || fail 'mail checks empty'
[[ $(printf '%s\n' "${KEYS[@]}" | sort | uniq -d | wc -l) == 0 ]] || fail 'duplicate mail keys'

# Privacy must hide hosts, domains and certificate identities without changing checks.
PRIVACY=1
NETWORK_PROBE_DEADLINE=0
: >"$TMP/getent-calls"; : >"$TMP/nc-calls"; : >"$TMP/openssl-calls"
reset_checks
check_mail
[[ ${VALUES[*]} == *'mail-host-1'* && ${VALUES[*]} == *'mail-domain-1'* ]] || fail 'privacy placeholders missing'
[[ ${VALUES[*]} != *example.test* && ${DETAILS[*]} != *example.test* ]] || fail 'mail privacy leak'
[[ ${DETAILS[*]} == *'Subject/Issuer скрыты'* ]] || fail 'certificate identity privacy note missing'

# Expiring leaf certificate must warn, but authentication is still never attempted.
PRIVACY=0
MAIL_TEST_CERT_END=$(date -d '+10 days' '+%b %d %H:%M:%S %Y GMT')
export MAIL_TEST_CERT_END
NETWORK_PROBE_DEADLINE=0
reset_checks
check_mail
for i in "${!KEYS[@]}"; do
    if [[ ${KEYS[i]} == mail.endpoint.*.tls.* ]]; then
        [[ ${SEVERITIES[i]} == warn ]] || fail 'expiring mail certificate must warn'
    fi
done
[[ ${VALUES[*]} == *'Проверка почтового ящика'* || ${LABELS[*]} == *'Проверка почтового ящика'* ]] || fail 'non-authentication scope missing'

# Invalid/credential-bearing URI is rejected and exhausted budget stays bounded.
_mail_reset
! _mail_parse_endpoint_uri 'imaps://user:secret@mail.example.test:993' || fail 'credential-bearing URI accepted'
[[ ${#MAIL_HOSTS[@]} == 0 ]] || fail 'invalid URI produced endpoint'
_mail_reset
_mail_add_endpoint imap mail.example.test 993 implicit test '' || fail 'fixture endpoint rejected'
ARM_INFO_NETWORK_BUDGET=1
SECONDS=2
NETWORK_PROBE_DEADLINE=1
_mail_dns_probe mail.example.test
[[ $MAIL_DNS_STATE == BUDGET ]] || fail 'mail DNS ignored exhausted common budget'

echo 'Mail profile regression tests OK'
