#!/usr/bin/env bash
# Run a single gate-routing trial.
# Usage: run-trial.sh <bare|explicit> <trial-output-dir>
#
# Drives a real brainstorming conversation (Superpowers + factory-gates
# both loaded) through to the brainstorming -> architecture-gate handoff
# point, and records which skill actually fires: architecture-gate
# (pass), writing-plans directly (fail), or neither (inconclusive).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SCENARIO="${1:-}"
TRIAL_DIR="${2:-}"

if [ -z "$SCENARIO" ] || [ -z "$TRIAL_DIR" ]; then
    echo "Usage: $0 <bare|explicit> <trial-output-dir>" >&2
    exit 1
fi

if [ "$SCENARIO" != "bare" ] && [ "$SCENARIO" != "explicit" ]; then
    echo "ERROR: scenario must be 'bare' or 'explicit', got '$SCENARIO'" >&2
    exit 1
fi

SUPERPOWERS_DIR="$(resolve_superpowers_dir)"
FACTORY_GATES_DIR="$(resolve_factory_gates_dir)"

mkdir -p "$TRIAL_DIR"
PROJECT_DIR="$(setup_trial_dir "$TRIAL_DIR")"

FEATURE_REQUEST="I want to build a small in-memory rate limiter for an API. Single component: a RateLimiter class with a check(key) method, fixed-window algorithm, 100 requests per 60 seconds, no persistence, no external dependencies, single file. That's the complete design -- no open questions on my end."

if [ "$SCENARIO" = "explicit" ]; then
    TURN1_PROMPT="Use the factory-gates workflow for this. $FEATURE_REQUEST"
else
    TURN1_PROMPT="$FEATURE_REQUEST"
fi

TURNS=(
    "$TURN1_PROMPT"
    "Yes, that approach looks good -- please continue."
    "Approved. Please write the spec and commit it."
    "I've reviewed the spec, it looks good, please proceed."
)

BRAINSTORMING_TRIGGERED=false
ARCHITECTURE_GATE_TRIGGERED=false
ARCHITECTURE_GATE_TURN=0
WRITING_PLANS_BEFORE_ARCHITECTURE=false
OUTCOME="inconclusive"
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

    if skill_invoked_in "$LOG_FILE" "architecture-gate"; then
        ARCHITECTURE_GATE_TRIGGERED=true
        ARCHITECTURE_GATE_TURN=$TURN_NUM
        OUTCOME="pass"
        break
    fi

    if skill_invoked_in "$LOG_FILE" "writing-plans"; then
        WRITING_PLANS_BEFORE_ARCHITECTURE=true
        OUTCOME="fail"
        break
    fi
done

if [ "$BRAINSTORMING_TRIGGERED" = "false" ]; then
    OUTCOME="inconclusive"
fi

cat > "$TRIAL_DIR/result.json" <<EOF
{
  "scenario": "$SCENARIO",
  "trial_dir": "$TRIAL_DIR",
  "brainstorming_triggered": $BRAINSTORMING_TRIGGERED,
  "architecture_gate_triggered": $ARCHITECTURE_GATE_TRIGGERED,
  "architecture_gate_turn": $ARCHITECTURE_GATE_TURN,
  "writing_plans_before_architecture": $WRITING_PLANS_BEFORE_ARCHITECTURE,
  "turns_used": $TURNS_USED,
  "outcome": "$OUTCOME"
}
EOF

echo "Trial complete: scenario=$SCENARIO outcome=$OUTCOME turns_used=$TURNS_USED"
echo "Result: $TRIAL_DIR/result.json"

if [ "$OUTCOME" = "pass" ]; then
    exit 0
else
    exit 1
fi
