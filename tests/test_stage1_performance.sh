#!/usr/bin/env bash
# Behavioral regression fixtures and deterministic subprocess-count budgets.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
awk '/^have\(\)/{copy=1} /^check_software\(\)/{copy=0} copy' "$ROOT/arm_info.sh" >"$TMP/functions.sh"
# shellcheck disable=SC1091
source "$TMP/functions.sh"
# shellcheck source=tests/render_cases.sh
source "$ROOT/tests/render_cases.sh"
for locale_name in C C.utf8; do
    case "$locale_name" in C) fixture=c;; *) fixture=utf8;; esac
    if [[ $fixture == utf8 ]] && ! LC_ALL=$locale_name locale charmap 2>/dev/null | grep -qi UTF-8; then
        echo 'SKIP: UTF-8 locale unavailable'; continue
    fi
    (export LC_ALL=$locale_name; unset REPORT_WIDTH; render_cases) >"$TMP/render"
    cmp "$TMP/render" "$ROOT/tests/fixtures/render-$fixture.txt" || fail "render changed: $locale_name"
done

# Fast-path rows must not launch fold/tput when report width is known.
fold() { echo fold >>"$TMP/render-calls"; command fold "$@"; }
tput() { echo tput >>"$TMP/render-calls"; printf '110\n'; }
REPORT_WIDTH=110
for ((i=0;i<1000;i++)); do
    print_check_row "Package $i" '[INFO]' '1.2.3-1.x86_64'
done >"$TMP/large-report"
[[ $(wc -l <"$TMP/large-report") == 1000 ]] || fail 'large report truncated'
[[ ! -s $TMP/render-calls ]] || fail 'short rows spawned external formatting commands'
unset REPORT_WIDTH
unset -f fold tput

# emit_text must resolve terminal width once for the whole report.
awk '/^emit_text\(\)/{copy=1} /^emit_json\(\)/{copy=0} copy' "$ROOT/arm_info.sh" >"$TMP/emit.sh"
# shellcheck disable=SC1091
source "$TMP/emit.sh"
(
    unset COLUMNS REPORT_WIDTH
    tput() { echo tput >>"$TMP/width-calls"; printf '110\n'; }
    VERSION=test; PROFILE=enterprise; PRIVACY=1; OUTPUT_PATH=''; SAVE_REPORT=0
    KEYS=(first second); LABELS=('Параметр' 'Another'); VALUES=(value value)
    SECTIONS=(section section); SEVERITIES=(info warn); DETAILS=('' detail)
    REC_KEYS=(); CRIT_COUNT=0; WARN_COUNT=1; UNKNOWN_COUNT=0
    emit_text >"$TMP/report"
)
[[ $(wc -l <"$TMP/width-calls") == 1 ]] || fail 'terminal width queried for every row'

# Cache is keyed by UUID and field; preserve empty and old nmcli escaped values.
nmcli() {
    printf '%s\n' "$*" >>"$TMP/nm-calls"
    local field id
    if [[ $1 == -e ]]; then field=$4; id=$8
    else field=$2; id=$6; fi
    case "$field" in
        empty) return 0;;
        failed) return 10;;
        escaped)
            [[ $1 == -e ]] && return 2
            printf '%s\n' 'file\:///certs/a\\b.pem';;
        multiline) printf 'first\nsecond\n';;
        *) printf '%s/%s' "$id" "$field";;
    esac
}
cache_pass() {
    local -A NM_802_CACHE=()
    local NM_802_VALUE='' i
    for ((i=0;i<20;i++)); do
        nm_802_value client uuid-1
        [[ $NM_802_VALUE == uuid-1/client ]] || fail 'normal value'
        nm_802_value client uuid-2
        [[ $NM_802_VALUE == uuid-2/client ]] || fail 'UUID collision'
        nm_802_value empty uuid-1
        [[ -z $NM_802_VALUE ]] || fail 'empty value'
        nm_802_value escaped uuid-1
        [[ $NM_802_VALUE == 'file:///certs/a\b.pem' ]] || fail 'escaped fallback'
        nm_802_value failed uuid-1
        [[ -z $NM_802_VALUE ]] || fail 'failed query changed baseline'
        nm_802_value multiline uuid-1
        [[ $NM_802_VALUE == first ]] || fail 'multiline changed baseline'
    done
}
cache_pass
[[ $(wc -l <"$TMP/nm-calls") == 9 ]] || fail 'repeated properties were queried again'
cache_pass
[[ $(wc -l <"$TMP/nm-calls") == 18 ]] || fail 'cache leaked across collections'
echo 'Stage 1 rendering and query-cache tests OK'
