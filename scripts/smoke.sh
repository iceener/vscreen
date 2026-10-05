#!/bin/bash
# Smoke check of the installed vscreen: doctor, display start/status, the fixture window on
# the virtual display, display stop. Records the frontmost app before and after and fails if
# it changed. Leaves the virtual display stopped.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VS="${VSCREEN:-$HOME/.local/bin/vscreen}"
cd "$ROOT"
swift build --product vscreen-fixture >&2
FIXTURE="$(swift build --show-bin-path)/vscreen-fixture"

field() { plutil -extract "$1" raw -o - - ; }
front() { "$VS" doctor | field frontmostApp.bundleId; }

FIXTURE_PID=""
EVENTS="$(mktemp)"
cleanup() {
  [ -n "$FIXTURE_PID" ] && kill "$FIXTURE_PID" 2>/dev/null || true
  "$VS" display stop >/dev/null || true
  rm -f "$EVENTS"
}
trap cleanup EXIT

BEFORE="$(front)"
echo "doctor: $("$VS" doctor)"

START="$("$VS" display start)"
echo "start: $START"
DISPLAY_ID="$(echo "$START" | field displayID)"
echo "status: $("$VS" display status)"

"$FIXTURE" --display "$DISPLAY_ID" --exit-after 30 > "$EVENTS" &
FIXTURE_PID=$!
for _ in $(seq 100); do
  grep -q '"event":"ready"' "$EVENTS" && break
  sleep 0.1
done
READY="$(grep '"event":"ready"' "$EVENTS")"
echo "fixture: $READY"
[ "$(echo "$READY" | field screenDisplayID)" = "$DISPLAY_ID" ] || { echo "FAIL: fixture window is not on display $DISPLAY_ID" >&2; exit 1; }
[ "$(echo "$READY" | field appActive)" = "false" ] || { echo "FAIL: fixture app became active" >&2; exit 1; }
MID="$(front)"

kill "$FIXTURE_PID"
FIXTURE_PID=""
echo "stop: $("$VS" display stop)"
echo "status: $("$VS" display status)"
AFTER="$(front)"

echo "frontmost before=$BEFORE during=$MID after=$AFTER"
[ "$BEFORE" = "$MID" ] && [ "$MID" = "$AFTER" ] || { echo "FAIL: frontmost app changed" >&2; exit 1; }
echo "smoke ok"
