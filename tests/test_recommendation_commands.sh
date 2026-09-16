#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/arm_info.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

grep -q 'base_print_rec_commands' "$SCRIPT" || fail 'base command splitter missing'
grep -q 'ИЗМЕНЯЕТ СОСТОЯНИЕ' "$SCRIPT" || fail 'state-changing command warning missing'
grep -q 'DOMAIN_FQDN' "$SCRIPT" || fail 'safe domain placeholder missing'
grep -q 'PROFILE_NAME' "$SCRIPT" || fail '802.1X profile placeholder missing'
grep -q 'CERT_PATH' "$SCRIPT" || fail 'certificate placeholder missing'
grep -q 'MD_DEVICE' "$SCRIPT" || fail 'RAID placeholder missing'
grep -q 'UNIT_NAME' "$SCRIPT" || fail 'systemd unit placeholder missing'
grep -q 'DEVICE_PATH' "$SCRIPT" || fail 'device placeholder missing'
grep -q 'USER_NAME' "$SCRIPT" || fail 'user-context placeholder missing'

! grep -Fq 'nmcli -f NAME,IP4.DOMAIN,IP4.DNS connection show --active' "$SCRIPT" || fail 'invalid nmcli active-list fields remain'
! grep -Fq 'nmcli -f NAME,TYPE,802-1x.eap,802-1x.ca-cert,802-1x.client-cert connection show' "$SCRIPT" || fail 'invalid nmcli 802.1X list fields remain'
! grep -Fq 'rpm -qf "$(command -v lpstat' "$SCRIPT" || fail 'guaranteed-fail lpstat rpm query remains'
! grep -Fq 'mdadm --detail /dev/md0' "$SCRIPT" || fail 'hard-coded md0 remains'
! grep -Fq 'REC_COMMAND="klist -A|find /tmp -maxdepth 1 -type f -name' "$SCRIPT" || fail 'FILE-cache-only Kerberos recommendation remains'
! grep -Fq '<DOMAIN>' "$SCRIPT" || fail 'shell-redirection-style DOMAIN placeholder remains'
! grep -Fq '<MOUNT>' "$SCRIPT" || fail 'shell-redirection-style MOUNT placeholder remains'
! grep -Fq '<QUEUE>' "$SCRIPT" || fail 'shell-redirection-style QUEUE placeholder remains'
! grep -Fq '<JOB_ID>' "$SCRIPT" || fail 'shell-redirection-style JOB placeholder remains'

# Representative copy/paste commands must be valid Bash after replacing service markers.
commands=(
  "nmcli -f GENERAL.CONNECTION,IP4.DNS,IP4.DOMAIN device show"
  "nmcli connection show 'PROFILE_NAME' | grep -E '^802-1x\\.(eap|identity|ca-cert|client-cert|phase2-ca-cert|phase2-client-cert|private-key|system-ca-certs):'"
  "openssl x509 -in \"CERT_PATH\" -noout -subject -issuer -dates"
  "timeout 5 nc -vz DC_FQDN 88"
  "findmnt -t cifs -o TARGET,SOURCE,OPTIONS"
  "lpstat -W not-completed -o"
  "dnf provides '/usr/bin/lpstat'"
  "systemctl status UNIT_NAME --no-pager -l"
  "journalctl -u UNIT_NAME -b --no-pager | tail -120"
  "mdadm --detail MD_DEVICE"
  "top -b -n1 | head -30"
)
for cmd in "${commands[@]}"; do
  bash -n -c "$cmd" || fail "invalid command syntax: $cmd"
done

echo 'recommendation command audit tests: OK'
