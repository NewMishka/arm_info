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

for fn in collect_base_snapshot evaluate_base_disk_scores evaluate_base_disk_findings \
    evaluate_base_network_status evaluate_base_snapshot prepare_base_output_view \
    emit_base_text emit_base_json run_base_pipeline; do
    declare -F "$fn" >/dev/null || fail "$fn missing"
done

# Collectors capture and normalize facts only. Recommendations, thresholds,
# status classification and scoring belong to checks/scoring.
collector_body=$(declare -f collect_base_snapshot)
! grep -Fq 'add_rec ' <<<"$collector_body" || \
    fail 'base collector mixes collection with recommendations'
! grep -Eq '(^|[^[:alnum:]_])[A-Z0-9_]+_SCORE[[:space:]]*=' <<<"$collector_body" || \
    fail 'base collector performs score calculation'
! grep -Eq 'min_score|clamp_score|NET_STATUS[[:space:]]*=|NET_BAD_IFACES\+=' <<<"$collector_body" || \
    fail 'base collector performs checks/status evaluation'

declare -f evaluate_base_snapshot | grep -Fq 'evaluate_base_disk_scores' || \
    fail 'base evaluator bypasses normalized disk scoring'
declare -f evaluate_base_snapshot | grep -Fq 'evaluate_base_disk_findings' || \
    fail 'base evaluator bypasses normalized disk findings'
declare -f evaluate_base_snapshot | grep -Fq 'evaluate_base_network_status' || \
    fail 'base evaluator bypasses normalized network status'
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

# Disk scoring is reconstructed from normalized facts, outside the collector.
HDD_TEMP_WARN=50
HDD_TEMP_HIGH=60
HDD_TEMP_CRIT=70
SSD_TEMP_WARN=60
SSD_TEMP_HIGH=70
SSD_TEMP_CRIT=80
NVME_TEMP_WARN=70
NVME_TEMP_HIGH=80
NVME_TEMP_CRIT=90
FIXED_DISKS=2
DISK_CHECK_ROWS=(
    'sda|/dev/sda|Системный|HDD|FAIL|2|1|0|0|0|-|45000|55|-1|-1'
    'nvme0n1|/dev/nvme0n1|Дополнительный|NVMe SSD|OK|0|0|0|1|3|9%|1000|75|2|5'
)
evaluate_base_disk_scores
[[ $SYSTEM_DISK_SCORE -eq 0 ]] || fail "system disk score: $SYSTEM_DISK_SCORE"
[[ $DISK_WORST_SCORE -eq 0 ]] || fail "worst disk score: $DISK_WORST_SCORE"
[[ $SECONDARY_WORST_KNOWN_SCORE -eq 9 ]] || fail "secondary disk score: $SECONDARY_WORST_KNOWN_SCORE"
[[ $SECONDARY_KNOWN_COUNT -eq 1 ]] || fail "secondary known count: $SECONDARY_KNOWN_COUNT"
[[ $SECONDARY_CRITICAL -eq 1 ]] || fail "secondary critical flag: $SECONDARY_CRITICAL"

# Network threshold classification also belongs to evaluation, not collection.
ACTIVE_NET=2
NET_ERROR_PPM=120
NET_DROP_PPM=20
NET_ERROR_WARN_PPM=100
NET_ERROR_CRIT_PPM=1000
NET_DROP_WARN_PPM=100
NET_DROP_CRIT_PPM=1000
NET_IFACE_PPM_ROWS=('eth0|1500' 'eth1|500')
evaluate_base_network_status
[[ $NET_STATUS == 'Требует внимания' ]] || fail "network status: $NET_STATUS"
[[ ${#NET_BAD_IFACES[@]} -eq 1 && ${NET_BAD_IFACES[0]} == 'eth0:1500ppm' ]] || \
    fail 'network bad-interface classification changed'

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
    'sda|/dev/sda|Системный|HDD|FAIL|2|1|0|0|0|-|45000|55|-1|-1'
    'nvme0n1|/dev/nvme0n1|Дополнительный|NVMe SSD|OK|0|0|0|1|3|9%|1000|75|2|5'
)
evaluate_base_disk_findings
[[ ${#REC_TITLES[@]} -eq 9 ]] || fail "disk findings count: ${#REC_TITLES[@]}"
[[ ${REC_TITLES[0]} == 'Накопитель sda: SMART сообщает отказ' ]] || fail 'SMART failure order changed'
[[ ${REC_TITLES[1]} == 'Накопитель sda: переназначенные сектора — 2' ]] || fail 'reallocated finding missing'
[[ ${REC_TITLES[4]} == 'Накопитель sda: повышенная температура 55°C' ]] || fail 'HDD temperature finding missing'
[[ ${REC_TITLES[5]} == 'NVMe nvme0n1: Critical Warning=1' ]] || fail 'NVMe critical warning missing'
[[ ${REC_TITLES[7]} == 'Накопитель nvme0n1: остаточный ресурс 9%' ]] || fail 'NVMe resource finding missing'

echo 'Stage 4 base pipeline architecture tests OK'
