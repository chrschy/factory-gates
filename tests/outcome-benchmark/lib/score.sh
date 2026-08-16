#!/usr/bin/env bash
# Scoring mechanics for tests/outcome-benchmark. Sourced by run-trial.sh.

set -euo pipefail

# Usage: parse_unittest_output <output-file>
# Pure text parser -- no subprocess, no network. Reads the output of
# `python3 <script> -v` (unittest's verbose format) from <output-file>.
# Extracts the total test count from a "Ran N tests" line, and the passed
# count as: total (if a bare "OK" line follows), or total - failures -
# errors (if a "FAILED (failures=N[, errors=M])" line follows). Prints
# "<passed> <total>" to stdout. Prints "0 0" if no recognizable summary
# line is found (crashed or truncated output).
parse_unittest_output() {
    local output_file="$1"
    local total
    total="$(grep -oE '^Ran [0-9]+ tests? in' "$output_file" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"

    if [ -z "$total" ]; then
        echo "0 0"
        return
    fi

    if tail -n 5 "$output_file" 2>/dev/null | grep -qE '^OK$'; then
        echo "$total $total"
        return
    fi

    local failed_line
    failed_line="$(grep -E '^FAILED \(' "$output_file" 2>/dev/null | head -1 || true)"
    if [ -n "$failed_line" ]; then
        local failures errors
        failures="$(printf '%s' "$failed_line" | grep -oE 'failures=[0-9]+' | grep -oE '[0-9]+' || true)"
        errors="$(printf '%s' "$failed_line" | grep -oE 'errors=[0-9]+' | grep -oE '[0-9]+' || true)"
        failures="${failures:-0}"
        errors="${errors:-0}"
        echo "$((total - failures - errors)) $total"
        return
    fi

    echo "0 0"
}
