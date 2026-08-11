#!/usr/bin/env bash
# Unit tests for .github/scripts/lib/version-calc.sh
# Pure bash logic, no network/git/gh calls -- fast and deterministic.
# Usage: tests/release/test-version-calc.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../.github/scripts/lib/version-calc.sh
source "$REPO_ROOT/.github/scripts/lib/version-calc.sh"

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

assert_true() {
    local description="$1"
    if [ "$2" = "0" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $description (expected success/exit 0)"
    fi
}

assert_false() {
    local description="$1"
    if [ "$2" != "0" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $description (expected failure/nonzero exit)"
    fi
}

# --- classify_commit_message ---

assert_eq "feat header -> feat" "feat" "$(classify_commit_message 'feat: add thing')"
assert_eq "feat with scope -> feat" "feat" "$(classify_commit_message 'feat(architecture-gate): add thing')"
assert_eq "fix header -> fix" "fix" "$(classify_commit_message 'fix: correct thing')"
assert_eq "perf header -> fix" "fix" "$(classify_commit_message 'perf: speed up thing')"
assert_eq "docs header -> other" "other" "$(classify_commit_message 'docs: update readme')"
assert_eq "chore header -> other" "other" "$(classify_commit_message 'chore(meta): bump deps')"
assert_eq "feat with ! -> breaking" "breaking" "$(classify_commit_message 'feat!: remove old API')"
assert_eq "fix with scope and ! -> breaking" "breaking" "$(classify_commit_message 'fix(scope)!: remove old API')"
assert_eq "BREAKING CHANGE footer -> breaking" "breaking" "$(classify_commit_message 'feat: add thing

BREAKING CHANGE: removes the old thing entirely')"
assert_eq "feat header, unrelated body text -> feat (no false breaking match)" "feat" "$(classify_commit_message 'feat: add thing

This is a normal body paragraph that happens to mention breaking things
informally but is not a real footer.')"

# --- parse_version ---

assert_eq "parse with v prefix" "1 2 3" "$(parse_version 'v1.2.3')"
assert_eq "parse without v prefix" "1 2 3" "$(parse_version '1.2.3')"

# --- compute_next_version ---

assert_eq "patch bump" "1.2.4" "$(compute_next_version "1.2.3" 0 0 1)"
assert_eq "minor bump" "1.3.0" "$(compute_next_version "1.2.3" 0 1 0)"
assert_eq "major bump (post-1.0)" "2.0.0" "$(compute_next_version "1.2.3" 1 0 0)"
assert_eq "breaking pre-1.0 -> minor bump, not major" "0.2.0" "$(compute_next_version "0.1.0" 1 0 0)"
assert_eq "breaking + feat present -> breaking wins" "2.0.0" "$(compute_next_version "1.2.3" 1 1 0)"
assert_eq "feat + fix present -> feat wins" "1.3.0" "$(compute_next_version "1.2.3" 0 1 1)"
assert_eq "only other commits -> patch fallback" "1.2.4" "$(compute_next_version "1.2.3" 0 0 0)"
assert_eq "resets minor/patch on major bump" "2.0.0" "$(compute_next_version "1.9.9" 1 0 0)"
assert_eq "resets patch on minor bump" "1.3.0" "$(compute_next_version "1.2.9" 0 1 0)"

# --- error handling (regression: parse_version failures must propagate) ---

rc=0; (compute_next_version "not-a-version" 0 0 1) >/dev/null 2>&1 || rc=$?
assert_false "compute_next_version rejects invalid version string" "$rc"

rc=0; (version_gt "1.2.3" "not-a-version") >/dev/null 2>&1 || rc=$?
assert_false "version_gt rejects invalid second argument" "$rc"

# --- version_gt ---

if version_gt "1.2.3" "1.2.2"; then rc=0; else rc=1; fi
assert_true "1.2.3 > 1.2.2" "$rc"
if version_gt "1.3.0" "1.2.9"; then rc=0; else rc=1; fi
assert_true "1.3.0 > 1.2.9" "$rc"
if version_gt "2.0.0" "1.9.9"; then rc=0; else rc=1; fi
assert_true "2.0.0 > 1.9.9" "$rc"
if version_gt "1.2.3" "1.2.3"; then rc=0; else rc=1; fi
assert_false "1.2.3 not > 1.2.3 (equal)" "$rc"
if version_gt "1.2.2" "1.2.3"; then rc=0; else rc=1; fi
assert_false "1.2.2 not > 1.2.3" "$rc"

echo ""
echo "Passed: $PASS, Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
