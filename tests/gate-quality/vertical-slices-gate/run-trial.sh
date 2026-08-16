#!/usr/bin/env bash
# Run a single vertical-slices-gate quality trial.
# Usage: run-trial.sh <trial-output-dir>
#
# Drives a real brainstorming -> architecture-gate -> program-design-gate
# -> writing-plans -> vertical-slices-gate conversation on a toy
# URL-shortener feature, extracts the assistant's text from the turn
# vertical-slices-gate fires in, and scores it with a headless LLM judge
# against the rubric in
# docs/superpowers/specs/2026-08-15-vertical-slices-gate-quality-tests-design.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../gate-routing/lib/common.sh
source "$SCRIPT_DIR/../../gate-routing/lib/common.sh"
# shellcheck source=lib/judge.sh
source "$SCRIPT_DIR/lib/judge.sh"

TRIAL_DIR="${1:-}"

if [ -z "$TRIAL_DIR" ]; then
    echo "Usage: $0 <trial-output-dir>" >&2
    exit 1
fi

SUPERPOWERS_DIR="$(resolve_superpowers_dir)"
FACTORY_GATES_DIR="$(resolve_factory_gates_dir)"

mkdir -p "$TRIAL_DIR"
PROJECT_DIR="$(setup_trial_dir "$TRIAL_DIR")"

FEATURE_REQUEST="I want to build a small URL shortener, implemented in Python using only the standard library. Two components: a public redirect service that takes a short code and 302-redirects to the original URL, and an admin API for creating new short links (POST with a target URL, returns a short code). Both read/write the same data store (short code -> target URL mapping). Redirect latency matters -- it's on the hot path for every click. No user accounts, no analytics, no custom short codes (always generated). That's the complete design -- no open questions on my end."

TURNS=(
    "$FEATURE_REQUEST"
    "That approach looks good -- please continue."
    "Approved. Please write the spec and commit it."
    "I've reviewed the spec, it looks good, please proceed."
    "That architecture approach looks good -- please continue."
    "Approved. Please write the architecture doc."
    "I've reviewed the architecture doc, it looks good, please proceed."
    "Approved. Please write the program design doc."
    "I've reviewed the program design doc, it looks good, please proceed."
    "Approved. Please write the implementation plan."
    "I've reviewed the plan, it looks good."
    "Confirmed, that build order looks right."
)

BRAINSTORMING_TRIGGERED=false
ARCHITECTURE_GATE_TRIGGERED=false
PROGRAM_DESIGN_GATE_TRIGGERED=false
VERTICAL_SLICES_GATE_TRIGGERED=false
VERTICAL_SLICES_GATE_TURN=0
TURNS_USED=0

for i in "${!TURNS[@]}"; do
    TURN_NUM=$((i + 1))
    TURNS_USED=$TURN_NUM
    PROMPT="${TURNS[$i]}"
    LOG_FILE="$TRIAL_DIR/turn${TURN_NUM}.json"

    if [ "$TURN_NUM" = "1" ]; then
        run_turn "$PROJECT_DIR" "$PROMPT" 0 "$SUPERPOWERS_DIR" "$FACTORY_GATES_DIR" "$LOG_FILE"
    else
        run_turn "$PROJECT_DIR" "$PROMPT" 1 "$SUPERPOWERS_DIR" "$FACTORY_GATES_DIR" "$LOG_FILE"
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
        VERTICAL_SLICES_GATE_TURN=$TURN_NUM
    fi
done

TRANSCRIPT=""
if [ "$VERTICAL_SLICES_GATE_TRIGGERED" = "true" ]; then
    TRANSCRIPT="$(extract_assistant_text "$TRIAL_DIR/turn${VERTICAL_SLICES_GATE_TURN}.json")"
fi

OUTCOME="inconclusive"
JUDGE_OUTPUT_FILE=""

if [ "$VERTICAL_SLICES_GATE_TRIGGERED" = "true" ] && [ -n "$TRANSCRIPT" ]; then
    JUDGE_OUTPUT_FILE="$TRIAL_DIR/judge-output.txt"
    JUDGE_PROMPT="$(build_judge_prompt "$TRANSCRIPT")"
    run_judge "$JUDGE_PROMPT" "$JUDGE_OUTPUT_FILE"
    VERDICT="$(parse_judge_verdict "$JUDGE_OUTPUT_FILE" "Vertical Slices Gate Review")"
    case "$VERDICT" in
        pass) OUTCOME="pass" ;;
        fail) OUTCOME="fail" ;;
        *) OUTCOME="inconclusive" ;;
    esac
fi

cat > "$TRIAL_DIR/result.json" <<EOF
{
  "trial_dir": "$TRIAL_DIR",
  "brainstorming_triggered": $BRAINSTORMING_TRIGGERED,
  "architecture_gate_triggered": $ARCHITECTURE_GATE_TRIGGERED,
  "program_design_gate_triggered": $PROGRAM_DESIGN_GATE_TRIGGERED,
  "vertical_slices_gate_triggered": $VERTICAL_SLICES_GATE_TRIGGERED,
  "vertical_slices_gate_turn": $VERTICAL_SLICES_GATE_TURN,
  "judge_output_file": "${JUDGE_OUTPUT_FILE:-}",
  "turns_used": $TURNS_USED,
  "outcome": "$OUTCOME"
}
EOF

echo "Trial complete: outcome=$OUTCOME turns_used=$TURNS_USED vertical_slices_gate_triggered=$VERTICAL_SLICES_GATE_TRIGGERED"
echo "Result: $TRIAL_DIR/result.json"

if [ "$OUTCOME" = "pass" ]; then
    exit 0
else
    exit 1
fi
