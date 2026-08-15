#!/usr/bin/env bash
# Unit tests for lib/judge.sh's build_judge_prompt (vertical-slices-gate's
# rubric) and the shared parse_judge_verdict it inherits. Pure text
# parsing/templating, no live claude -p calls -- fast and deterministic.
# Usage: ./test-judge.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/judge.sh
source "$SCRIPT_DIR/lib/judge.sh"
set +e

PASS=0
FAIL=0

assert_eq() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $description"
        echo "  expected: $expected"
        echo "  actual:   $actual"
    fi
}

TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

# --- parse_judge_verdict (shared function, vertical-slices-gate's header) ---

cat > "$TMPFILE" <<'EOF'
## Vertical Slices Gate Review

**Status:** Approved

**Issues (if any):**
None.
EOF
assert_eq "Approved status -> pass" "pass" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

cat > "$TMPFILE" <<'EOF'
## Vertical Slices Gate Review

**Status:** Issues Found

**Issues (if any):**
- Coordination risk: plan spans two services but no deploy-order dependency is stated.
EOF
assert_eq "Issues Found status -> fail" "fail" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

cat > "$TMPFILE" <<'EOF'
This is not a real review, just some rambling text with no Status line
and no recognizable structure at all.
EOF
assert_eq "malformed output, no header -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

cat > "$TMPFILE" <<'EOF'
## Vertical Slices Gate Review

I think this looks fine overall.
EOF
assert_eq "header present but no Status line -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

: > "$TMPFILE"
assert_eq "empty file -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

cat > "$TMPFILE" <<'EOF'
## Vertical Slices Gate Review

**Status:** Approved | Issues Found

**Issues (if any):**
- [Category]: [specific issue]
EOF
assert_eq "placeholder Status line -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

cat > "$TMPFILE" <<'EOF'
## Program Design Doc Review

**Status:** Approved
EOF
assert_eq "wrong gate's header -> unparseable (header mismatch)" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

# --- build_judge_prompt (vertical-slices-gate's own rubric) ---

TRANSCRIPT="Build order:
1. redirect service -- demoable via curl once deployed
2. admin API -- demoable via POST once deployed

Confirm this order, or would you like to reorder?"

PROMPT_OUTPUT="$(build_judge_prompt "$TRANSCRIPT")"
if printf '%s' "$PROMPT_OUTPUT" | grep -q "## Rubric" && printf '%s' "$PROMPT_OUTPUT" | grep -q "redirect service -- demoable via curl"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: build_judge_prompt embeds both the rubric and the transcript content"
fi

if printf '%s' "$PROMPT_OUTPUT" | grep -q "Vertical Slices Gate Review"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: build_judge_prompt's output format asks for the vertical-slices-gate-specific header"
fi

echo ""
echo "Passed: $PASS, Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
