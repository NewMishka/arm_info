#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); SCRIPT="$ROOT/arm_info.sh"
die() { echo "TEST FAIL: $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; mkdir "$T/bin"
cat >"$T/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
*'list-unit-files sssd.service'*) echo 'sssd.service enabled';;
*'list-unit-files cups.service'*) echo 'cups.service enabled';;
*'is-active sssd'*|*'is-active cups'*) echo failed; exit 3;;
*'show sssd -p Result --value'*|*'show cups -p Result --value'*) echo exit-code;; esac
EOF
cat >"$T/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in *'-u sssd'*) printf '%s\n' 'sssd_be: Cannot resolve host' 'sssd_be: Cannot resolve host';; *'-u cups'*) echo 'cupsd: Unable to connect: timed out';; esac
EOF
cat >"$T/bin/timedatectl" <<'EOF'
#!/usr/bin/env bash
case "$*" in *NTPSynchronized*) echo no;; esac
EOF
cat >"$T/bin/lpstat" <<'EOF'
#!/usr/bin/env bash
echo 'printer accounting is idle'
EOF
chmod +x "$T/bin"/*; OUT="$T/out.json"; set +e; PATH="$T/bin:$PATH" bash "$SCRIPT" --json --privacy >"$OUT"; rc=$?; set -e; ((rc>=0 && rc<=3)) || die "exit $rc"
python3 - "$OUT" <<'PY' || die services
import json,sys
x=json.load(open(sys.argv[1]))['diagnostics']
assert x['sssd_result']=='exit-code' and x['sssd_error_count']==1 and 'Синхронизация времени' in x['sssd_likely_cause']
assert x['cups_result']=='exit-code' and x['cups_error_count']==1 and 'Сеть' in x['cups_likely_cause']
assert 'вероятная причина' in '\n'.join(r['impact'] for r in json.load(open(sys.argv[1]))['recommendations'])
PY
echo 'OK: service failure analysis passed'
