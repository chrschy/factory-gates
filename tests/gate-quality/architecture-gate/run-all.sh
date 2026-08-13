#!/usr/bin/env bash
# Run the full architecture-gate quality trial batch and report pass/fail/
# inconclusive rates.
#
# Usage: run-all.sh [--trials N]
#   --trials N   Number of trials (default: 3)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TRIALS=3

while [ $# -gt 0 ]; do
    case "$1" in
        --trials)
            TRIALS="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

TIMESTAMP=$(date +%s)
RUN_DIR="/tmp/factory-gates-gate-quality-tests/${TIMESTAMP}"
mkdir -p "$RUN_DIR"

echo "=== Architecture-Gate Quality Test Run ==="
echo "Trials: $TRIALS"
echo "Output dir: $RUN_DIR"
echo ""

RESULT_FILES=()

for trial_num in $(seq 1 "$TRIALS"); do
    TRIAL_DIR="$RUN_DIR/trial-$trial_num"
    echo ">>> Running trial $trial_num..."
    "$SCRIPT_DIR/run-trial.sh" "$TRIAL_DIR" || true
    if [ -f "$TRIAL_DIR/result.json" ]; then
        RESULT_FILES+=("$TRIAL_DIR/result.json")
    else
        echo "WARNING: no result.json for trial $trial_num (script likely crashed)" >&2
    fi
    echo ""
done

if [ "${#RESULT_FILES[@]}" -eq 0 ]; then
    echo "ERROR: no trials produced results" >&2
    exit 1
fi

echo "=== Summary ==="
jq -s '
  {
    trials: length,
    pass: ([.[] | select(.outcome == "pass")] | length),
    fail: ([.[] | select(.outcome == "fail")] | length),
    inconclusive: ([.[] | select(.outcome == "inconclusive")] | length)
  }
' "${RESULT_FILES[@]}" | tee "$RUN_DIR/summary.json"

echo ""
echo "Full results: $RUN_DIR"

FAIL_COUNT=$(jq -s '[.[] | select(.outcome == "fail")] | length' "${RESULT_FILES[@]}")
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "NOTE: $FAIL_COUNT trial(s) had the judge find issues in the architecture doc. Check judge_output_file in each trial's result.json for details."
    exit 1
fi
