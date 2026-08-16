#!/usr/bin/env bash
# Unit tests for lib/score.sh's parse_unittest_output. Pure text parsing,
# no subprocess, no network, no live claude -p calls -- fast and
# deterministic. Usage: ./test-scoring.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/score.sh
source "$SCRIPT_DIR/lib/score.sh"
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

cat > "$TMPFILE" <<'EOF'
test_create_then_redirect (acceptance_tests.AcceptanceTests.test_create_then_redirect) ... ok
test_unknown_code_returns_404 (acceptance_tests.AcceptanceTests.test_unknown_code_returns_404) ... ok

----------------------------------------------------------------------
Ran 2 tests in 0.014s

OK
EOF
assert_eq "all pass -> passed == total" "2 2" "$(parse_unittest_output "$TMPFILE")"

cat > "$TMPFILE" <<'EOF'
test_create_then_redirect (acceptance_tests.AcceptanceTests.test_create_then_redirect) ... ok
test_unknown_code_returns_404 (acceptance_tests.AcceptanceTests.test_unknown_code_returns_404) ... FAIL

======================================================================
FAIL: test_unknown_code_returns_404 (acceptance_tests.AcceptanceTests.test_unknown_code_returns_404)
----------------------------------------------------------------------
AssertionError: 200 != 404

----------------------------------------------------------------------
Ran 2 tests in 0.014s

FAILED (failures=1)
EOF
assert_eq "one failure -> passed = total - failures" "1 2" "$(parse_unittest_output "$TMPFILE")"

cat > "$TMPFILE" <<'EOF'
test_create_then_redirect (acceptance_tests.AcceptanceTests.test_create_then_redirect) ... ERROR

----------------------------------------------------------------------
Ran 5 tests in 0.041s

FAILED (failures=1, errors=1)
EOF
assert_eq "failures and errors both subtracted" "3 5" "$(parse_unittest_output "$TMPFILE")"

cat > "$TMPFILE" <<'EOF'
Traceback (most recent call last):
  File "acceptance_tests.py", line 4, in <module>
    import nonexistent_module
ModuleNotFoundError: No module named 'nonexistent_module'
EOF
assert_eq "crashed output, no summary line -> 0 0" "0 0" "$(parse_unittest_output "$TMPFILE")"

: > "$TMPFILE"
assert_eq "empty file -> 0 0" "0 0" "$(parse_unittest_output "$TMPFILE")"

echo ""
echo "Passed: $PASS, Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
