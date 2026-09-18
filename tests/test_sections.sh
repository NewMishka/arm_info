#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/arm_info.sh"

die() { echo "TEST FAIL: $*" >&2; exit 1; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

run_diag() {
    local out=$1; shift
    local rc
    set +e
    if command -v timeout >/dev/null 2>&1; then
        timeout 90 bash "$SCRIPT" "$@" >"$out"
        rc=$?
    else
        bash "$SCRIPT" "$@" >"$out"
        rc=$?
    fi
    set -e
    ((rc>=0 && rc<=3)) || die "unexpected exit code $rc for: $*"
}

assert_section_once() {
    local file=$1 section=$2 count
    count=$(grep -Fxc "$section" "$file" || true)
    [[ $count -eq 1 ]] || die "section '$section' expected once in $(basename "$file"), got $count"
}

assert_contains() {
    local file=$1 text=$2
    grep -Fq "$text" "$file" || die "missing '$text' in $(basename "$file")"
}

# -------------------- Standard TXT report: every user-visible section --------------------
BASE_TXT="$TMPDIR/base.txt"
run_diag "$BASE_TXT" --privacy

BASE_SECTIONS=(
    "СИСТЕМА"
    "ПРОЦЕССОР"
    "ОПЕРАТИВНАЯ ПАМЯТЬ"
    "СТАБИЛЬНОСТЬ СИСТЕМЫ"
    "СЕТЬ"
    "ДОПОЛНИТЕЛЬНЫЕ ПРОВЕРКИ"
    "ОПЦИОНАЛЬНЫЕ СЕРВИСЫ"
    "НАКОПИТЕЛИ"
    "ФАЙЛОВЫЕ СИСТЕМЫ"
    "СВОДКА СОСТОЯНИЯ"
    "КЛЮЧЕВЫЕ ПОКАЗАТЕЛИ"
    "ЗАКЛЮЧЕНИЕ"
    "РЕКОМЕНДАЦИИ"
)
for section in "${BASE_SECTIONS[@]}"; do
    assert_section_once "$BASE_TXT" "$section"
done

# One or more stable anchors from every standard section.
assert_contains "$BASE_TXT" "Хост"
assert_contains "$BASE_TXT" "Ядро"
assert_contains "$BASE_TXT" "Ядер / потоков"
assert_contains "$BASE_TXT" "Всего / занято / доступно"
assert_contains "$BASE_TXT" "Failed-службы"
assert_contains "$BASE_TXT" "Ошибки ядра HW/storage"
assert_contains "$BASE_TXT" "Общая учитываемая доля"
assert_contains "$BASE_TXT" "Software RAID"
assert_contains "$BASE_TXT" "Kerberos"
assert_contains "$BASE_TXT" "Системный накопитель:"
assert_contains "$BASE_TXT" "Ресурс"
assert_contains "$BASE_TXT" "SMART"
assert_contains "$BASE_TXT" "Корневой раздел"
assert_contains "$BASE_TXT" "Индекс по доступным данным"
assert_contains "$BASE_TXT" "Стабильность системы"
assert_contains "$BASE_TXT" "SMART системного накопителя"
assert_contains "$BASE_TXT" "Полнота проверки"
! grep -Fq "Стабильность ОС" "$BASE_TXT" || die "obsolete stability label returned in summary"

# -------------------- Standard JSON: machine-readable counterpart of all groups --------------------
BASE_JSON="$TMPDIR/base.json"
run_diag "$BASE_JSON" --json --privacy
python3 - "$BASE_JSON" <<'PY' || exit 1
import json,sys
p=sys.argv[1]
with open(p, encoding='utf-8') as f:
    d=json.load(f)
required={
    'schema_version','arm_info_version','privacy','system','cpu','memory','storage',
    'filesystem','network','stability','diagnostics','summary','recommendations'
}
missing=sorted(required-set(d))
assert not missing, f"missing base JSON groups: {missing}"
assert d['schema_version']==1
assert isinstance(d['system'],dict) and {'hostname','os','kernel','arch','install_date'} <= set(d['system'])
assert isinstance(d['cpu'],dict) and {'model','cores','threads','load1','temperature_c','score'} <= set(d['cpu'])
assert isinstance(d['memory'],dict) and {'available_percent','swap_used_percent','oom_detected','score'} <= set(d['memory'])
assert isinstance(d['storage'],dict) and {'score','known','system_disks','fixed_disks','removable_disks','system_smart_unknown'} <= set(d['storage'])
assert isinstance(d['filesystem'],dict) and {'root_use_percent','max_use_percent','max_inode_percent','score'} <= set(d['filesystem'])
assert isinstance(d['network'],dict) and {'active_interfaces','gateway','dns','rx_dropped','rx_missed','tx_dropped','error_ppm','rx_drop_ppm_raw','scored_loss_ppm','drop_ppm','score'} <= set(d['network'])
assert isinstance(d['stability'],dict) and {'failed_units','hardware_errors','journal_errors','oom_detected','time_sync','ecc_ce','ecc_ue','score'} <= set(d['stability'])
assert isinstance(d['diagnostics'],dict) and {'time_sync','raid','ecc','battery_health','sssd','kerberos','cups','support_tier'} <= set(d['diagnostics'])
assert isinstance(d['summary'],dict) and {'state','score','confidence','conclusion'} <= set(d['summary'])
assert isinstance(d['recommendations'],list)
PY

# -------------------- Corporate profiles: every section and route --------------------
check_profile_json() {
    local profile expected_csv out
    profile=$1
    expected_csv=$2
    out="$TMPDIR/${profile}.json"
    run_diag "$out" --profile "$profile" --json --privacy
    python3 - "$out" "$profile" "$expected_csv" <<'PY' || exit 1
import json,sys
path,profile,expected_csv=sys.argv[1:]
with open(path, encoding='utf-8') as f:
    d=json.load(f)
assert d['schema_version']==2
assert d['profile']==profile
assert isinstance(d.get('checks'),list) and d['checks'], profile
assert isinstance(d.get('recommendations'),list), profile
sections={x.get('section') for x in d['checks'] if isinstance(x,dict)}
keys=[x['key'] for x in d['checks']]
assert len(keys)==len(set(keys)), f'{profile}: duplicate check keys'
expected=set(expected_csv.split('|'))
if profile=='enterprise': assert 'DNS' not in sections
missing=sorted(expected-sections)
assert not missing, f"{profile}: missing sections {missing}; got {sorted(sections)}"
PY
}

check_profile_json domain "ДОМЕН / KERBEROS|DNS / DOMAIN"
check_profile_json network "СЕТЬ|DNS|802.1X|SMB / GVFS"
check_profile_json print "ПЕЧАТЬ / CUPS"
check_profile_json software "ИНВЕНТАРИЗАЦИЯ ПО|ПРОЦЕССЫ"
check_profile_json enterprise "ДОМЕН / KERBEROS|DNS / DOMAIN|СЕТЬ|802.1X|SMB / GVFS|ПЕЧАТЬ / CUPS"

CORP_TXT="$TMPDIR/corp.txt"
run_diag "$CORP_TXT" --corp --privacy
assert_contains "$CORP_TXT" "ARM_INFO КОРПОРАТИВНЫЙ"
assert_contains "$CORP_TXT" "Профиль: корпоративный"
for section in "ДОМЕН / KERBEROS" "DNS / DOMAIN" "СЕТЬ" "802.1X" "SMB / GVFS" "ПЕЧАТЬ / CUPS" "СВОДКА" "РЕКОМЕНДАЦИИ"; do
    assert_section_once "$CORP_TXT" "$section"
done
assert_contains "$CORP_TXT" "Параметр"
assert_contains "$CORP_TXT" "Статус"
assert_contains "$CORP_TXT" "Значение"

# Static guards for section-specific helpers that CI hardware cannot exercise reliably.
grep -q '^run_smart() {' "$SCRIPT" || die "storage: SMART wrapper missing"
grep -Fq 'SMART_ALL=$(run_smart -a "$DEV"' "$SCRIPT" || die "storage: SMART collection path missing"
grep -Fq 'SMART_H=$(run_smart -H "$DEV"' "$SCRIPT" || die "storage: SMART health collection path missing"
grep -Fq 'run_smart -l selftest "$DEV"' "$SCRIPT" || die "storage: SMART self-test collection path missing"
grep -q 'read_cpu_temp_once()' "$SCRIPT" || die "cpu: temperature reader missing"
grep -q 'STAB_PENALTY_HW' "$SCRIPT" || die "stability: hardware penalty missing"
grep -q 'mount_is_removable()' "$SCRIPT" || die "filesystem: removable filter missing"
grep -q 'disk_is_removable()' "$SCRIPT" || die "storage: removable disk filter missing"
grep -q 'check_domain()' "$SCRIPT" || die "enterprise: domain checker missing"
grep -q 'check_network()' "$SCRIPT" || die "enterprise: network checker missing"
grep -Fq 'done < <(findmnt -n -l -t cifs -o TARGET 2>/dev/null)' "$SCRIPT" || die "enterprise: CIFS TARGET-only enumeration missing"
grep -Fq 'ls -U -A -1 -- "$mnt/"' "$SCRIPT" || die "enterprise: CIFS full-directory readdir probe missing"
grep -Fq 'stat -L -- "$sample"' "$SCRIPT" || die "enterprise: CIFS metadata lookup probe missing"
grep -Fq 'network.cifs.mount.$cifs_count' "$SCRIPT" || die "enterprise: per-share CIFS report row missing"
! grep -Fq 'run_timeout 5 find "$mnt" -mindepth 1 -maxdepth 1 -print -quit' "$SCRIPT" || die "enterprise: old first-entry-only CIFS probe returned"
! grep -Fq "findmnt -n -l -t cifs -o TARGET,SOURCE 2>/dev/null | awk" "$SCRIPT" || die "enterprise: whitespace-splitting CIFS parser returned"
grep -q 'check_print()' "$SCRIPT" || die "enterprise: print checker missing"
grep -q 'check_software()' "$SCRIPT" || die "enterprise: software checker missing"

echo "OK: all standard and corporate report sections are covered"
