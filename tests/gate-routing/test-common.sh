#!/usr/bin/env bash
# Unit tests for common.sh's _plugin_dir_flags -- pure text/array
# construction, no live claude calls, no subprocess.
# Usage: ./test-common.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
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

RESULT="$(_plugin_dir_flags "/path/to/superpowers" "/path/to/factory-gates")"
assert_eq "both dirs -> four lines, both --plugin-dir pairs" \
"--plugin-dir
/path/to/superpowers
--plugin-dir
/path/to/factory-gates" "$RESULT"

RESULT="$(_plugin_dir_flags "/path/to/superpowers" "")"
assert_eq "empty factory_gates_dir -> only the superpowers pair" \
"--plugin-dir
/path/to/superpowers" "$RESULT"

echo ""
echo "Passed: $PASS, Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
