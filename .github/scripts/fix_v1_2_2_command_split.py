from pathlib import Path

root = Path(__file__).resolve().parents[2]
path = root / "arm_info.sh"
text = path.read_text(encoding="utf-8")

old = r'''print_rec_commands() {
    local text=$1 cmd desc idx=0
    while IFS='|' read -r cmd; do
        [[ -n $cmd ]] || continue
        idx=$((idx+1))
        desc=$(command_description "$cmd")
        print_rec_field "Команда $idx:" "$cmd ($desc)"
    done <<<"${text//|/$'\n'}"
}
'''
new = r'''split_rec_commands() {
    # REC_COMMAND historical format uses an unquoted | as a list separator.
    # Preserve real shell pipelines (" | ") and regex pipes inside quotes.
    local s=$1 current="" quote="" i ch prev next len=${#1}
    for ((i=0; i<len; i++)); do
        ch=${s:i:1}
        if [[ $ch == "'" && $quote != '"' ]]; then
            if [[ $quote == "'" ]]; then quote=""; else quote="'"; fi
            current+=$ch
            continue
        fi
        if [[ $ch == '"' && $quote != "'" ]]; then
            if [[ $quote == '"' ]]; then quote=""; else quote='"'; fi
            current+=$ch
            continue
        fi
        if [[ $ch == '|' && -z $quote ]]; then
            prev=""; next=""
            ((i>0)) && prev=${s:i-1:1}
            ((i+1<len)) && next=${s:i+1:1}
            if [[ $prev != [[:space:]] && $next != [[:space:]] && $prev != '|' && $next != '|' ]]; then
                printf '%s\n' "$current"
                current=""
                continue
            fi
        fi
        current+=$ch
    done
    [[ -n $current ]] && printf '%s\n' "$current"
}

print_rec_commands() {
    local text=$1 cmd desc idx=0
    while IFS= read -r cmd; do
        [[ -n $cmd ]] || continue
        idx=$((idx+1))
        desc=$(command_description "$cmd")
        print_rec_field "Команда $idx:" "$cmd ($desc)"
    done < <(split_rec_commands "$text")
}
'''
if text.count(old) != 1:
    raise SystemExit(f"print_rec_commands match count={text.count(old)}")
text = text.replace(old, new, 1)

old_json = r'''        while IFS='|' read -r cmd; do
            [[ -n $cmd ]] || continue
            printf '%s"%s"' "$ccomma" "$(json_escape "$cmd")"
            ccomma=','
        done <<<"${REC_COMMANDS[i]//|/$'\n'}"
'''
new_json = r'''        while IFS= read -r cmd; do
            [[ -n $cmd ]] || continue
            printf '%s"%s"' "$ccomma" "$(json_escape "$cmd")"
            ccomma=','
        done < <(split_rec_commands "${REC_COMMANDS[i]}")
'''
if text.count(old_json) != 1:
    raise SystemExit(f"JSON command splitter match count={text.count(old_json)}")
text = text.replace(old_json, new_json, 1)

path.write_text(text, encoding="utf-8")
