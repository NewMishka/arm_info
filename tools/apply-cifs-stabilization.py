#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
arm = root / "arm_info.sh"
text = arm.read_text(encoding="utf-8")
old = '''            cifs_state=$CIFS_PROBE_STATE
            cifs_text=$(_cifs_state_text "$cifs_state")
            cifs_detail="контекст: $cifs_context; multiuser: $cifs_multiuser"
            [[ -n $CIFS_PROBE_ERR ]] && cifs_detail="$cifs_detail; $CIFS_PROBE_ERR"
'''
new = '''            cifs_state=$CIFS_PROBE_STATE
            cifs_text=$(_cifs_state_text "$cifs_state")
            if ((PRIVACY)); then
                cifs_detail="контекст: скрыто; multiuser: $cifs_multiuser"
            else
                cifs_detail="контекст: $cifs_context; multiuser: $cifs_multiuser"
            fi
            [[ -n $CIFS_PROBE_ERR ]] && cifs_detail="$cifs_detail; $CIFS_PROBE_ERR"
'''
if old not in text:
    raise SystemExit("privacy target not found")
text = text.replace(old, new, 1)
arm.write_text(text, encoding="utf-8")

test = root / "tests/test_cifs_probe.sh"
t = test.read_text(encoding="utf-8")
needle = "grep -Fq 'network.cifs.mount.$cifs_count' \"$SCRIPT\" || fail 'per-share report rows missing'\n"
extra = needle + "grep -Fq 'cifs_detail=\"контекст: скрыто; multiuser: $cifs_multiuser\"' \"$SCRIPT\" || fail 'CIFS privacy context masking missing'\n"
if "CIFS privacy context masking missing" not in t:
    if needle not in t:
        raise SystemExit("test insertion point not found")
    t = t.replace(needle, extra, 1)
test.write_text(t, encoding="utf-8")
