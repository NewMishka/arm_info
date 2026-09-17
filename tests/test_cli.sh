#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/arm_info.sh"
EXPECTED_VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")

die() { echo "TEST FAIL: $*" >&2; exit 1; }

bash -n "$SCRIPT" || die "bash -n"
[[ $(bash "$SCRIPT" --version) == "arm_info $EXPECTED_VERSION" ]] || die "--version"
bash "$SCRIPT" --help | grep -q -- '--privacy' || die "--help"

grep -q 'print_wrapped "Возможные причины:"' "$SCRIPT" || die "base recommendation causes"
grep -q 'print_wrapped "Что проверить:"' "$SCRIPT" || die "base recommendation checks"
grep -q 'print_wrapped "Контроль результата:"' "$SCRIPT" || die "base recommendation verification"
grep -q 'base_print_rec_commands' "$SCRIPT" || die "base recommendation multi-command renderer"
grep -q 'base_split_commands' "$SCRIPT" || die "base recommendation command splitter"
grep -q 'label_w=23' "$SCRIPT" || die "base recommendation corporate-style alignment"
grep -q 'base_command_description' "$SCRIPT" || die "base command descriptions"
grep -q 'base_print_command_line' "$SCRIPT" || die "base commands must use copy-safe renderer"
grep -q 'print_wrapped "$REC_NUM. \[${REC_LEVELS\[$i\]}\]"' "$SCRIPT" || die "base recommendation aligned title"
grep -Fq 'Температура CPU|${CPU_TEMP}°C (медиана)' "$SCRIPT" || die "CPU median label"
grep -q 'SYSTEM_DISKS=' "$SCRIPT" || die "system disk resolver"
grep -q 'lsblk -srno NAME,TYPE' "$SCRIPT" || die "system disk resolver must use raw lsblk output"
grep -q 'Оптический (вне индекса)' "$SCRIPT" || die "optical drive must be outside index"
grep -q 'disk_is_removable' "$SCRIPT" || die "removable disk classifier"
grep -q 'USB-накопитель' "$SCRIPT" || die "USB disk type"
grep -q 'Съёмный (вне индекса)' "$SCRIPT" || die "removable disk role"
grep -q 'SYSTEM_DISK_SCORE' "$SCRIPT" || die "system disk priority score"
grep -q 'SECONDARY_WORST_KNOWN_SCORE' "$SCRIPT" || die "secondary disk weighted score"
grep -q 'REMOVABLE_FS_COUNT' "$SCRIPT" || die "removable filesystem exclusion"
grep -q 'section "СТАБИЛЬНОСТЬ СИСТЕМЫ"' "$SCRIPT" || die "stability section"
grep -q 'STAB_PENALTY_FAILED' "$SCRIPT" || die "stability failed-unit penalty"
grep -q 'STAB_PENALTY_HW' "$SCRIPT" || die "stability hardware penalty"
grep -q 'Штраф, баллов' "$SCRIPT" || die "stability transparent penalty table"
grep -q '"penalty_hardware"' "$SCRIPT" || die "stability JSON penalty details"
grep -q 'Съёмных ФС вне индекса' "$SCRIPT" || die "removable filesystem report"
grep -q '^run_smart() {' "$SCRIPT" || die "SMART wrapper missing"
grep -Fq 'timeout 8 smartctl "$@"' "$SCRIPT" || die "SMART wrapper timeout contract"
grep -Fq 'SMART_ALL=$(run_smart -a "$DEV"' "$SCRIPT" || die "SMART collection must use wrapper"
! grep -Fq '(медиана; максимум ${CPU_TEMP_MAX}°C)' "$SCRIPT" || die "CPU maximum must not be shown with median"
grep -q '"possible_causes"' "$SCRIPT" || die "base recommendation JSON causes"
grep -q '"verification"' "$SCRIPT" || die "base recommendation JSON verification"
grep -Fq 'RX_MISSED_TOTAL=$((RX_MISSED_TOTAL+RXM))' "$SCRIPT" || die "network: rx_missed must be collected"
grep -Fq 'SCORED_LOSSES_TOTAL=$((RX_MISSED_TOTAL+TX_DROPS_TOTAL))' "$SCRIPT" || die "network: scored losses must use rx_missed + tx_dropped"
grep -Fq 'NET_RX_DROP_PPM_RAW=$((RX_DROPS_TOTAL*1000000/RX_PACKETS_TOTAL))' "$SCRIPT" || die "network: raw rx_dropped ppm missing"
! grep -Fq 'RXTX_DROPS=$((RX_DROPS_TOTAL+TX_DROPS_TOTAL))' "$SCRIPT" || die "network: rx_dropped returned to scored loss aggregate"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
set +e
bash "$SCRIPT" --json --privacy --no-save >"$TMP"
RC=$?
set -e
((RC>=0 && RC<=3)) || die "unexpected diagnostic exit code: $RC"

python3 - "$TMP" <<'PY' || die "JSON schema/privacy/recommendations"
import json,sys
with open(sys.argv[1], encoding='utf-8') as f:
    d=json.load(f)
assert d['schema_version']==1 and d['privacy'] is True
assert d['system']['hostname']=='ARM-REDACTED'
assert isinstance(d['summary']['score'], int)
assert isinstance(d.get('recommendations'), list)
for r in d['recommendations']:
    for k in ('level','title','possible_causes','impact','checks','action','command','verification'):
        assert k in r, (k,r)
PY

echo "OK: CLI, JSON, privacy and standard report contract tests passed"
