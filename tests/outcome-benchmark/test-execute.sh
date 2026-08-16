#!/usr/bin/env bash
# Unit tests for lib/execute.sh's _build_execution_prompt. Pure string
# templating, no live claude -p calls. Usage: ./test-execute.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/execute.sh
source "$SCRIPT_DIR/lib/execute.sh"
set +e

PASS=0
FAIL=0

PROMPT_OUTPUT="$(_build_execution_prompt "/tmp/project/docs/superpowers/plans/plan.md" "/tmp/project/docs/superpowers/specs/spec-design.md")"

check() {
    local description="$1"
    local needle="$2"
    if printf '%s' "$PROMPT_OUTPUT" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $description"
    fi
}

check "embeds the plan path" "/tmp/project/docs/superpowers/plans/plan.md"
check "embeds the spec path" "/tmp/project/docs/superpowers/specs/spec-design.md"
check "pins the POST contract" "POST /api/links"
check "pins the redirect contract" "GET /<code> -> 302"
check "pins the 404 contract" "unknown code -> 404"
check "pins the exact startup command" "python3 serve.py"

echo ""
echo "Passed: $PASS, Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
