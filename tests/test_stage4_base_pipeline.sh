#!/usr/bin/env bash
# Stage 4: base collectors -> normalized snapshot -> checks/scoring -> emitters.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# The base pipeline is intentionally a contiguous group of function definitions.
# Stop before its single top-level invocation so this test never probes the host.
awk '/^collect_base_snapshot\(\)/{copy=1} /^run_base_pipeline$/{copy=0} copy' \
    "$ROOT/arm_info.sh" >"$TMP/functions.sh"
# shellcheck disable=SC1091
source "$TMP/functions.sh"

for fn in collect_base_snapshot evaluate_base_disk_findings evaluate_base_snapshot \
    prepare_base_output_view emit_base_text emit_base_json run_base_pipeline; do
    declare -F "$fn" >/dev/null || fail "$fn missing"
done

# Collectors capture/normalize facts. Recommendations belong to checks/scoring.
! declare -f collect_base_snapshot | grep -Fq 'add_rec ' || \
    fail 'base collector mixes collection with recommendations'
declare -f evaluate_base_snapshot | grep -Fq 'evaluate_base_disk_findings' || \
    fail 'base evaluator bypasses normalized disk findings'
declare -f evaluate_base_snapshot | grep -Fq 'add_rec ' || \
    fail 'base evaluator does not create recommendations'

# Emitters consume the snapshot only: they must not repeat hardware/system probes.
for fn in emit_base_text emit_base_json; do
    body=$(declare -f "$fn")
    ! grep -Eq '(\$\(|<\(|^|[;&|])[[:space:]]*(lscpu|lsblk|findmnt|journalctl|systemctl|dmidecode|nmcli|resolvectl|ip)([[:space:]]|$)' <<<"$body" || \
        fail "$fn performs discovery while rendering"
    ! grep -Eq 'command -v smartctl|id -u' <<<"$body" || \
        fail "$fn repeats capability discovery"
done

# One pipeline invocation must execute each stage exactly once and select one emitter.
TRACE=()
collect_base_snapshot() { TRACE+=(collect); }
evaluate_base_snapshot() { TRACE+=(evaluate); }
prepare_base_output_view() { TRACE+=(view); }
emit_base_text() { TRACE+=(text); }
emit_base_json() { TRACE+=(json); }
JSON_MODE=0
run_base_pipeline
[[ ${TRACE[*]} == 'collect evaluate view text' ]] || fail "TXT pipeline order: ${TRACE[*]}"
TRACE=()
JSON_MODE=1
run_base_pipeline
[[ ${TRACE[*]} == 'collect evaluate view json' ]] || fail "JSON pipeline order: ${TRACE[*]}"

# Disk recommendations are reconstructed from normalized collector rows and retain
# the previous per-disk order and thresholds.
REC_TITLES=()
add_rec() { REC_TITLES+=("$2"); }
SSD_LIFE_CRIT=10
SSD_LIFE_WARN=20
SSD_LIFE_PLAN=30
HDD_TEMP_WARN=50
SSD_TEMP_WARN=60
NVME_TEMP_WARN=70
DISK_CHECK_ROWS=(
    'sda|/dev/sda|HDD|FAIL|2|1|0|0|0|-|45000|55'
    'nvme0n1|/dev/nvme0n1|NVMe SSD|OK|0|0|0|1|3|9%|1000|75'
)
evaluate_base_disk_findings
[[ ${#REC_TITLES[@]} -eq 9 ]] || fail "disk findings count: ${#REC_TITLES[@]}"
[[ ${REC_TITLES[0]} == 'Накопитель sda: SMART сообщает отказ' ]] || fail 'SMART failure order changed'
[[ ${REC_TITLES[1]} == 'Накопитель sda: переназначенные сектора — 2' ]] || fail 'reallocated finding missing'
[[ ${REC_TITLES[4]} == 'Накопитель sda: повышенная температура 55°C' ]] || fail 'HDD temperature finding missing'
[[ ${REC_TITLES[5]} == 'NVMe nvme0n1: Critical Warning=1' ]] || fail 'NVMe critical warning missing'
[[ ${REC_TITLES[7]} == 'Накопитель nvme0n1: остаточный ресурс 9%' ]] || fail 'NVMe resource finding missing'

echo 'Stage 4 base pipeline architecture tests OK'
