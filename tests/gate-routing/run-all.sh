#!/usr/bin/env bash
# Run the full gate-routing trial matrix and report pass/fail/inconclusive
# rates per scenario.
#
# Usage: run-all.sh [--scenario bare|explicit] [--trials N]
#   --scenario   Run only this scenario (default: both bare and explicit)
#   --trials N   Trials per scenario (default: 3)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCENARIOS=(bare explicit)
TRIALS=3

while [ $# -gt 0 ]; do
    case "$1" in
        --scenario)
            SCENARIOS=("$2")
            shift 2
            ;;
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
RUN_DIR="/tmp/factory-gates-tests/${TIMESTAMP}"
mkdir -p "$RUN_DIR"

echo "=== Gate-Routing Test Run ==="
echo "Scenarios: ${SCENARIOS[*]}"
echo "Trials per scenario: $TRIALS"
echo "Output dir: $RUN_DIR"
echo ""

RESULT_FILES=()

for scenario in "${SCENARIOS[@]}"; do
    for trial_num in $(seq 1 "$TRIALS"); do
        TRIAL_DIR="$RUN_DIR/$scenario/trial-$trial_num"
        echo ">>> Running $scenario trial $trial_num..."
        "$SCRIPT_DIR/run-trial.sh" "$scenario" "$TRIAL_DIR" || true
        if [ -f "$TRIAL_DIR/result.json" ]; then
            RESULT_FILES+=("$TRIAL_DIR/result.json")
        else
            echo "WARNING: no result.json for $scenario trial $trial_num (script likely crashed)" >&2
        fi
        echo ""
    done
done

if [ "${#RESULT_FILES[@]}" -eq 0 ]; then
    echo "ERROR: no trials produced results" >&2
    exit 1
fi

echo "=== Summary ==="
jq -s '
  group_by(.scenario) | map({
    scenario: .[0].scenario,
    trials: length,
    pass: ([.[] | select(.outcome == "pass")] | length),
    fail: ([.[] | select(.outcome == "fail")] | length),
    inconclusive: ([.[] | select(.outcome == "inconclusive")] | length)
  })
' "${RESULT_FILES[@]}" | tee "$RUN_DIR/summary.json"

echo ""
echo "Full results: $RUN_DIR"

FAIL_COUNT=$(jq -s '[.[] | select(.outcome == "fail")] | length' "${RESULT_FILES[@]}")
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "WARNING: $FAIL_COUNT trial(s) hit the failure mode (writing-plans invoked without architecture-gate)."
    exit 1
fi
