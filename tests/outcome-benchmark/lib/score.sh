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

# Usage: run_acceptance_tests <project-dir> [output-log-file]
# Independently re-checks for <project-dir>/serve.py (does not trust
# execute.sh's own "true"/"false" signal) and prints "0 0" immediately
# if it's missing. Otherwise starts `python3 serve.py` as a background
# subprocess in <project-dir>, polls 127.0.0.1:8000 for up to 10s (20
# attempts, 0.5s apart). If the port never opens, kills the subprocess
# and prints "0 0". If it opens, runs fixtures/acceptance_tests.py -v
# against it, captures output to [output-log-file] (default /dev/null),
# always kills the subprocess afterward, and prints
# parse_unittest_output's result.
run_acceptance_tests() {
    local project_dir="$1"
    local output_log="${2:-/dev/null}"
    local fixtures_dir
    fixtures_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"

    if [ ! -f "$project_dir/serve.py" ]; then
        echo "0 0"
        return
    fi

    local server_log
    server_log="$(mktemp)"
    (cd "$project_dir" && exec python3 serve.py) > "$server_log" 2>&1 &
    local server_pid=$!

    local port_open=false
    local attempt
    for attempt in $(seq 1 20); do
        if (exec 3<>/dev/tcp/127.0.0.1/8000) 2>/dev/null; then
            port_open=true
            break
        fi
        sleep 0.5
    done

    if [ "$port_open" != "true" ]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
        rm -f "$server_log"
        echo "0 0"
        return
    fi

    local test_output
    test_output="$(mktemp)"
    python3 "$fixtures_dir/acceptance_tests.py" -v > "$test_output" 2>&1 || true

    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true

    cp "$test_output" "$output_log" 2>/dev/null || true

    local counts
    counts="$(parse_unittest_output "$test_output")"
    rm -f "$server_log" "$test_output"
    echo "$counts"
}
