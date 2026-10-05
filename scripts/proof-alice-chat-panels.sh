#!/bin/bash
# Proof: Alice's native chat-panels scenario runs with its lab window on the vscreen virtual display
# while Adam's frontmost app stays in front.
#
#   ALICE_WT=<Alice checkout with the ALICE_LAB_WINDOW_ORIGIN hook> scripts/proof-alice-chat-panels.sh
#
# Evidence goes to proof/<stamp>/: frontmost.tsv (sampled every 0.2 s), windows.jsonl (the lab window's
# frame and display over time), paired shots of the virtual display and the main display taken at the
# same moment mid-scenario, the scenario log, and summary.json with the verdict. Exit 0 only on PASS.
set -uo pipefail

ALICE="${ALICE_WT:?set ALICE_WT to an Alice checkout with the ALICE_LAB_WINDOW_ORIGIN hook}"
VS="${VSCREEN:-vscreen}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${PROOF_DIR:-$ROOT/proof}/$(date +%Y%m%dT%H%M%S)"
SHOT_AT="${PROOF_SHOT_AT:-45 120 240}" # seconds after the lab window first shows on the virtual display
mkdir -p "$OUT"

now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
front() { # bundle<TAB>name<TAB>pid of the frontmost app
  lsappinfo info -only bundleid,name,pid "$(lsappinfo front)" |
    sed -n -e 's/^"CFBundleIdentifier"="\(.*\)"$/b=\1/p' -e 's/^"LSDisplayName"="\(.*\)"$/n=\1/p' -e 's/^"pid"=\(.*\)$/p=\1/p' |
    awk -F= '{v[$1]=$2} END {printf "%s\t%s\t%s\n", v["b"], v["n"], v["p"]}'
}
lab_pid() { pgrep -f "^$ALICE/target/debug/Alice\$" | head -1; }

"$VS" doctor > "$OUT/doctor-before.json"
"$VS" display start > "$OUT/display.json" || { echo "display start failed" >&2; exit 1; }
read -r VID VX VY VW VH < <(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); f=d["frame"]; print(d["displayID"], int(f["x"]), int(f["y"]), int(f["width"]), int(f["height"]))' "$OUT/display.json")
MAIN_ID="$(python3 -c 'import ctypes; print(ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics").CGMainDisplayID())')"
OX=$((VX + (VW - 880) / 2)); OY=$((VY + (VH - 600) / 2))
echo "virtual display $VID at $VX,$VY ${VW}x$VH; main display $MAIN_ID; lab window origin $OX,$OY" | tee "$OUT/setup.txt"

printf '%s\tbefore\t%s\n' "$(now_ms)" "$(front)" > "$OUT/frontmost.tsv"

# Frontmost sampler.
( while :; do printf '%s\tduring\t%s\n' "$(now_ms)" "$(front)"; sleep 0.2; done ) >> "$OUT/frontmost.tsv" &
SAMPLER=$!

# Lab window watcher: one line per change of the lab window's display/frame/on-screen state.
( last=""; while :; do
    pid="$(lab_pid)"
    if [ -n "$pid" ]; then
      grep -qx "$pid" "$OUT/lab-pids" 2>/dev/null || echo "$pid" >> "$OUT/lab-pids"
      line="$("$VS" window list --pid "$pid" 2>/dev/null | python3 -c '
import json, os, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
ws = [w for w in d.get("windows", []) if w.get("layer") == 0 and (w.get("frame") or {}).get("width", 0) > 100]
if any(w.get("onScreen") and w.get("display") == int(sys.argv[1]) for w in ws):
    open(os.path.join(sys.argv[2], ".lab-on-virtual"), "a").close()
print(json.dumps([{k: w.get(k) for k in ("id", "onScreen", "display", "frame")} for w in ws], sort_keys=True))' "$VID" "$OUT")"
      if [ -n "$line" ] && [ "$line" != "$last" ]; then
        printf '{"t":%s,"pid":%s,"windows":%s}\n' "$(now_ms)" "$pid" "$line"
        last="$line"
      fi
    fi
    sleep 0.1
  done ) >> "$OUT/windows.jsonl" &
WATCHER=$!

# Paired shots: the virtual display and the main display at the same moment.
( first=""; n=0
  until [ -n "$first" ]; do
    [ -e "$OUT/.lab-on-virtual" ] && first=$(date +%s)
    sleep 0.5
  done
  for at in $SHOT_AT; do
    while [ $(( $(date +%s) - first )) -lt "$at" ]; do sleep 0.5; done
    [ -n "$(lab_pid)" ] || break
    n=$((n + 1))
    t="$(now_ms)"
    "$VS" shot --display virtual -o "$OUT/shot-$n-a-virtual.png" > "$OUT/shot-$n-a.json" &
    "$VS" shot --display "$MAIN_ID" --allow-main -o "$OUT/shot-$n-b-main.png" > "$OUT/shot-$n-b.json" &
    wait
    printf '%s\tshot-%s\t%s\n' "$t" "$n" "$(front)" >> "$OUT/shots.tsv"
  done ) &
SHOOTER=$!

START="$(now_ms)"
( cd "$ALICE" && ALICE_LAB_WINDOW_ORIGIN="$OX,$OY" sh scripts/debug/native-chat-panels.sh ) > "$OUT/scenario.log" 2>&1
CODE=$?
END="$(now_ms)"
kill "$SHOOTER" 2>/dev/null; wait "$SHOOTER" 2>/dev/null
sleep 1
kill "$SAMPLER" "$WATCHER" 2>/dev/null; wait "$SAMPLER" "$WATCHER" 2>/dev/null
printf '%s\tafter\t%s\n' "$(now_ms)" "$(front)" >> "$OUT/frontmost.tsv"
"$VS" doctor > "$OUT/doctor-after.json"

RUN_DIR="$(sed -n 's/^chat panels: evidence in //p' "$OUT/scenario.log" | tail -1)"
[ -n "$RUN_DIR" ] && [ -d "$ALICE/$RUN_DIR" ] && cp -R "$ALICE/$RUN_DIR" "$OUT/alice-run"

python3 - "$OUT" "$CODE" "$START" "$END" "$VID" "$MAIN_ID" <<'EOF'
import json, os, sys
out, code, start, end, vid, main_id = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6])
samples = [l.rstrip("\n").split("\t") for l in open(os.path.join(out, "frontmost.tsv")) if l.strip()]
lab_pids = {l.strip() for l in open(os.path.join(out, "lab-pids"))} if os.path.exists(os.path.join(out, "lab-pids")) else set()
def is_lab(s):  # the lab process itself (by pid), or anything announcing the automation-lab identity
    bundle, name, pid = (s + ["", "", "", "", ""])[2:5]
    return pid in lab_pids or "automation-lab" in bundle.lower() or name == "Alice Automation Lab"
lab_front = [s for s in samples if is_lab(s)]
alice_named = [s for s in samples if (s + ["", ""])[3] == "Alice"]
apps = sorted({s[3] for s in samples if len(s) > 3})
windows = [json.loads(l) for l in open(os.path.join(out, "windows.jsonl")) if l.strip()]
off_virtual = [w for w in windows for x in w["windows"] if x.get("onScreen") and x.get("display") != vid]
on_virtual = [w for w in windows for x in w["windows"] if x.get("onScreen") and x.get("display") == vid]
shots = sorted(f for f in os.listdir(out) if f.startswith("shot-") and f.endswith(".png"))
summary = {
    "verdict": "PASS" if code == 0 and not lab_front and not off_virtual and on_virtual and shots else "FAIL",
    "scenarioExit": code,
    "durationSeconds": round((end - start) / 1000, 1),
    "virtualDisplay": vid,
    "mainDisplay": main_id,
    "frontmost": {
        "before": samples[0][2:] if samples else None,
        "after": samples[-1][2:] if samples else None,
        "samples": len(samples),
        "appsSeen": apps,
        "labFrontmostSamples": len(lab_front),
        "otherAliceAppFrontmostSamples": len(alice_named) - len([s for s in alice_named if is_lab(s)]),
        "labPids": sorted(lab_pids),
    },
    "labWindow": {
        "firstSeen": windows[0] if windows else None,
        "changes": len(windows),
        "everOnScreenOutsideVirtualDisplay": bool(off_virtual),
        "onVirtualDisplay": bool(on_virtual),
    },
    "shots": shots,
}
json.dump(summary, open(os.path.join(out, "summary.json"), "w"), indent=2)
print(json.dumps(summary, indent=2))
sys.exit(0 if summary["verdict"] == "PASS" else 1)
EOF
