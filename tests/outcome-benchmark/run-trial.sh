#!/usr/bin/env bash
# Run a single outcome-benchmark trial for one condition.
# Usage: run-trial.sh <treatment|baseline> <trial-output-dir>
#
# treatment: brainstorming -> architecture-gate -> program-design-gate ->
#   writing-plans -> vertical-slices-gate (factory-gates loaded)
# baseline: brainstorming -> writing-plans only (factory-gates NOT loaded)
#
# Both conditions then go through one identical, plugin-free execution
# step and are scored against the same fixed acceptance test suite. See
# docs/superpowers/specs/2026-08-16-outcome-benchmark-design.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../gate-routing/lib/common.sh
source "$SCRIPT_DIR/../gate-routing/lib/common.sh"
# shellcheck source=lib/turns.sh
source "$SCRIPT_DIR/lib/turns.sh"
# shellcheck source=lib/execute.sh
source "$SCRIPT_DIR/lib/execute.sh"
# shellcheck source=lib/score.sh
source "$SCRIPT_DIR/lib/score.sh"

CONDITION="${1:-}"
TRIAL_DIR="${2:-}"

if [ "$CONDITION" != "treatment" ] && [ "$CONDITION" != "baseline" ]; then
    echo "Usage: $0 <treatment|baseline> <trial-output-dir>" >&2
    exit 1
fi
if [ -z "$TRIAL_DIR" ]; then
    echo "Usage: $0 <treatment|baseline> <trial-output-dir>" >&2
    exit 1
fi

SUPERPOWERS_DIR="$(resolve_superpowers_dir)"
FACTORY_GATES_DIR="$(resolve_factory_gates_dir)"

if [ "$CONDITION" = "treatment" ]; then
    TURNS=("${TREATMENT_TURNS[@]}")
    RUN_FACTORY_GATES_DIR="$FACTORY_GATES_DIR"
else
    TURNS=("${BASELINE_TURNS[@]}")
    RUN_FACTORY_GATES_DIR=""
fi

mkdir -p "$TRIAL_DIR"
PROJECT_DIR="$(setup_trial_dir "$TRIAL_DIR")"

BRAINSTORMING_TRIGGERED=false
ARCHITECTURE_GATE_TRIGGERED=false
PROGRAM_DESIGN_GATE_TRIGGERED=false
VERTICAL_SLICES_GATE_TRIGGERED=false
TURNS_USED=0

for i in "${!TURNS[@]}"; do
    TURN_NUM=$((i + 1))
    TURNS_USED=$TURN_NUM
    PROMPT="${TURNS[$i]}"
    LOG_FILE="$TRIAL_DIR/turn${TURN_NUM}.json"

    if [ "$TURN_NUM" = "1" ]; then
        run_turn "$PROJECT_DIR" "$PROMPT" 0 "$SUPERPOWERS_DIR" "$RUN_FACTORY_GATES_DIR" "$LOG_FILE"
    else
        run_turn "$PROJECT_DIR" "$PROMPT" 1 "$SUPERPOWERS_DIR" "$RUN_FACTORY_GATES_DIR" "$LOG_FILE"
    fi

    if [ "$BRAINSTORMING_TRIGGERED" = "false" ] && skill_invoked_in "$LOG_FILE" "brainstorming"; then
        BRAINSTORMING_TRIGGERED=true
    fi
    if [ "$ARCHITECTURE_GATE_TRIGGERED" = "false" ] && skill_invoked_in "$LOG_FILE" "architecture-gate"; then
        ARCHITECTURE_GATE_TRIGGERED=true
    fi
    if [ "$PROGRAM_DESIGN_GATE_TRIGGERED" = "false" ] && skill_invoked_in "$LOG_FILE" "program-design-gate"; then
        PROGRAM_DESIGN_GATE_TRIGGERED=true
    fi
    if [ "$VERTICAL_SLICES_GATE_TRIGGERED" = "false" ] && skill_invoked_in "$LOG_FILE" "vertical-slices-gate"; then
        VERTICAL_SLICES_GATE_TRIGGERED=true
    fi
done

PLAN_PATH="$(find "$PROJECT_DIR/docs/superpowers/plans" -name '*.md' -print -quit 2>/dev/null || true)"
SPEC_PATH="$(find "$PROJECT_DIR/docs/superpowers/specs" -name '*-design.md' -print -quit 2>/dev/null || true)"

PLAN_FOUND=false
if [ -n "$PLAN_PATH" ]; then
    PLAN_FOUND=true
fi
SPEC_FOUND=false
if [ -n "$SPEC_PATH" ]; then
    SPEC_FOUND=true
fi

EXECUTION_COMPLETED=false
TESTS_PASSED=0
TESTS_TOTAL=0

if [ "$PLAN_FOUND" = "true" ] && [ "$SPEC_FOUND" = "true" ]; then
    EXECUTION_LOG="$TRIAL_DIR/execution.json"
    SERVE_PY_EXISTS="$(run_execution_step "$PROJECT_DIR" "$PLAN_PATH" "$SPEC_PATH" "$EXECUTION_LOG")"
    if [ "$SERVE_PY_EXISTS" = "true" ]; then
        EXECUTION_COMPLETED=true
        SCORE_LOG="$TRIAL_DIR/acceptance-test-output.txt"
        read -r TESTS_PASSED TESTS_TOTAL <<< "$(run_acceptance_tests "$PROJECT_DIR" "$SCORE_LOG")"
        TESTS_PASSED="${TESTS_PASSED:-0}"
        TESTS_TOTAL="${TESTS_TOTAL:-0}"
    fi
fi

OUTCOME="inconclusive"
if [ "$PLAN_FOUND" = "true" ] && [ "$SPEC_FOUND" = "true" ] && [ "$EXECUTION_COMPLETED" = "true" ] && [ "$TESTS_TOTAL" -gt 0 ]; then
    if [ "$TESTS_PASSED" -eq "$TESTS_TOTAL" ]; then
        OUTCOME="pass"
    else
        OUTCOME="fail"
    fi
fi

cat > "$TRIAL_DIR/result.json" <<EOF
{
  "trial_dir": "$TRIAL_DIR",
  "condition": "$CONDITION",
  "brainstorming_triggered": $BRAINSTORMING_TRIGGERED,
  "architecture_gate_triggered": $ARCHITECTURE_GATE_TRIGGERED,
  "program_design_gate_triggered": $PROGRAM_DESIGN_GATE_TRIGGERED,
  "vertical_slices_gate_triggered": $VERTICAL_SLICES_GATE_TRIGGERED,
  "plan_found": $PLAN_FOUND,
  "plan_path": "${PLAN_PATH:-}",
  "execution_completed": $EXECUTION_COMPLETED,
  "tests_passed": $TESTS_PASSED,
  "tests_total": $TESTS_TOTAL,
  "turns_used": $TURNS_USED,
  "outcome": "$OUTCOME"
}
EOF

echo "Trial complete: condition=$CONDITION outcome=$OUTCOME tests=$TESTS_PASSED/$TESTS_TOTAL turns_used=$TURNS_USED"
echo "Result: $TRIAL_DIR/result.json"

if [ "$OUTCOME" = "pass" ]; then
    exit 0
else
    exit 1
fi
