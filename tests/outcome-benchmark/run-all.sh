#!/usr/bin/env bash
# Run the full outcome-benchmark: N trials x 2 conditions (treatment,
# baseline), sequentially, and report a per-condition summary.
#
# Usage: run-all.sh [--trials N]
#   --trials N   Number of trials per condition (default: 3)

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
RUN_DIR="/tmp/factory-gates-outcome-benchmark/${TIMESTAMP}"
mkdir -p "$RUN_DIR"

echo "=== Outcome Benchmark Run ==="
echo "Trials per condition: $TRIALS"
echo "Output dir: $RUN_DIR"
echo ""

TREATMENT_RESULTS=()
for trial_num in $(seq 1 "$TRIALS"); do
    TRIAL_DIR="$RUN_DIR/treatment/trial-$trial_num"
    echo ">>> Running treatment trial $trial_num..."
    "$SCRIPT_DIR/run-trial.sh" treatment "$TRIAL_DIR" || true
    if [ -f "$TRIAL_DIR/result.json" ]; then
        TREATMENT_RESULTS+=("$TRIAL_DIR/result.json")
    else
        echo "WARNING: no result.json for treatment trial $trial_num (script likely crashed)" >&2
    fi
    echo ""
done

BASELINE_RESULTS=()
for trial_num in $(seq 1 "$TRIALS"); do
    TRIAL_DIR="$RUN_DIR/baseline/trial-$trial_num"
    echo ">>> Running baseline trial $trial_num..."
    "$SCRIPT_DIR/run-trial.sh" baseline "$TRIAL_DIR" || true
    if [ -f "$TRIAL_DIR/result.json" ]; then
        BASELINE_RESULTS+=("$TRIAL_DIR/result.json")
    else
        echo "WARNING: no result.json for baseline trial $trial_num (script likely crashed)" >&2
    fi
    echo ""
done

if [ "${#TREATMENT_RESULTS[@]}" -eq 0 ] || [ "${#BASELINE_RESULTS[@]}" -eq 0 ]; then
    echo "ERROR: at least one condition produced zero results -- the harness itself likely broke, not a measurement outcome" >&2
    exit 1
fi

summarize_condition() {
    local files=("$@")
    jq -s '
      {
        trials: length,
        pass: ([.[] | select(.outcome == "pass")] | length),
        fail: ([.[] | select(.outcome == "fail")] | length),
        inconclusive: ([.[] | select(.outcome == "inconclusive")] | length),
        mean_pass_rate: (
          [.[] | select(.outcome != "inconclusive") | (.tests_passed / .tests_total)] as $rates
          | if ($rates | length) > 0 then (($rates | add / ($rates | length)) * 100 | round) / 100 else null end
        )
      }
    ' "${files[@]}"
}

TREATMENT_SUMMARY="$(summarize_condition "${TREATMENT_RESULTS[@]}")"
BASELINE_SUMMARY="$(summarize_condition "${BASELINE_RESULTS[@]}")"

echo "=== Summary ==="
jq -n --argjson treatment "$TREATMENT_SUMMARY" --argjson baseline "$BASELINE_SUMMARY" \
    '{treatment: $treatment, baseline: $baseline}' | tee "$RUN_DIR/summary.json"

echo ""
echo "Full results: $RUN_DIR"
