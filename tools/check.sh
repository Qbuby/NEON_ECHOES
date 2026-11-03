#!/usr/bin/env bash
# Run every gate. Fails on the first non-zero exit.
#
#   bash tools/check.sh
#
# Each gate prints its own PASS/FAIL summary; this script only aggregates.
set -uo pipefail
cd "$(dirname "$0")/.."
GD="${GD:-C:/Users/14798/gamedev/bin/gd}"
fails=0

run() {
  local name="$1"; shift
  printf '%-28s ' "$name"
  if "$@" >/tmp/gate.log 2>&1; then
    tail -1 /tmp/gate.log | cut -c1-96
  else
    echo "FAILED"
    tail -20 /tmp/gate.log
    fails=$((fails + 1))
  fi
}

run "projection (iso grid)"  "$GD" --headless --path game -s res://tests/test_iso_grid.gd
run "acceptance suite"       "$GD" --headless --path game -s res://tests/run_suite.gd
run "16 screens"             "$GD" --headless --path game -s res://tests/test_screens.gd
run "isometric gameplay"     "$GD" --headless --path game -s res://tests/test_iso_play.gd
run "audio wiring"           "$GD" --headless --path game -s res://tests/test_audio_wired.gd
run "performance (1080p)"    "$GD" --headless --resolution 1920x1080 --path game -s res://tests/run_perf.gd
run "100 map switches"     "$GD" --headless --path game -s res://tests/run_soak.gd

printf '%-28s ' "frame lighting signature"
python tools/measure_frame.py game/evidence/iso_probe.png 2>/dev/null | grep -o 'ok$\|LOW$' | tail -1

echo
if [ "$fails" -eq 0 ]; then
  echo "ALL GATES PASSED"
else
  echo "$fails GATE(S) FAILED"
fi
exit "$fails"
