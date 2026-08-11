#!/usr/bin/env bash
# Unit tests for lib/judge.sh's parse_judge_verdict and build_judge_prompt.
# Pure text parsing/templating, no live claude -p calls -- fast and
# deterministic. Usage: ./test-judge.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/judge.sh
source "$SCRIPT_DIR/lib/judge.sh"

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

# --- parse_judge_verdict ---

cat > "$TMPFILE" <<'EOF'
## Architecture Doc Review

**Status:** Approved

**Issues (if any):**
None.
EOF
assert_eq "Approved status -> pass" "pass" "$(parse_judge_verdict "$TMPFILE")"

cat > "$TMPFILE" <<'EOF'
## Architecture Doc Review

**Status:** Issues Found

**Issues (if any):**
- Component boundaries: the "data store" is never named as its own component -- unclear if it's owned by one of the two services or a third thing.
EOF
assert_eq "Issues Found status -> fail" "fail" "$(parse_judge_verdict "$TMPFILE")"

cat > "$TMPFILE" <<'EOF'
This is not a real review, just some rambling text with no Status line
and no recognizable structure at all.
EOF
assert_eq "malformed output, no header -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE")"

cat > "$TMPFILE" <<'EOF'
## Architecture Doc Review

I think this looks fine overall.
EOF
assert_eq "header present but no Status line -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE")"

: > "$TMPFILE"
assert_eq "empty file -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE")"

# --- build_judge_prompt ---

cat > "$TMPFILE" <<'EOF'
# My Feature -- Architecture

## Components
- Foo -- does foo things
EOF
PROMPT_OUTPUT="$(build_judge_prompt "$TMPFILE")"
if printf '%s' "$PROMPT_OUTPUT" | grep -q "## Rubric" && printf '%s' "$PROMPT_OUTPUT" | grep -q "Foo -- does foo things"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: build_judge_prompt embeds both the rubric and the document content"
fi

echo ""
echo "Passed: $PASS, Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
