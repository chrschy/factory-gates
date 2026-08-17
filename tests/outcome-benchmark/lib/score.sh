#!/usr/bin/env bash
# Scoring mechanics for tests/outcome-benchmark. Sourced by run-trial.sh.

set -euo pipefail

# Usage: parse_unittest_output <output-file>
# Pure text parser -- no subprocess, no network. Reads the output of
# `python3 <script> -v` (unittest's verbose format) from <output-file>.
# Extracts the total test count from a "Ran N tests" line, and the passed
# count as: total (if a bare "OK" or "OK (skipped=N)" line follows), or
# total - failures - errors (if a "FAILED (failures=N[, errors=M])" line
# follows). Prints
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

    if tail -n 5 "$output_file" 2>/dev/null | grep -qE '^OK$|^OK \(skipped=[0-9]+\)$'; then
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

# Usage: _port_8000_open
# True (exit 0) if something is listening on 127.0.0.1:8000, false otherwise.
_port_8000_open() {
    (exec 3<>/dev/tcp/127.0.0.1/8000) 2>/dev/null
}

# Usage: _stop_server <pid>
# Escalating teardown for the backgrounded serve.py process: SIGTERM, wait
# up to ~3s, SIGKILL if still alive, reap it, then re-probe port 8000 for
# up to ~5s so it is verifiably closed before this function returns. This
# guarantees the next trial in the same run-all.sh process starts from a
# clean port instead of racing a not-yet-dead predecessor.
_stop_server() {
    local pid="$1"

    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        local waited=0
        while [ "$waited" -lt 6 ] && kill -0 "$pid" 2>/dev/null; do
            sleep 0.5
            waited=$((waited + 1))
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    fi
    wait "$pid" 2>/dev/null || true

    local attempt
    for attempt in $(seq 1 10); do
        if ! _port_8000_open; then
            return
        fi
        sleep 0.5
    done
}

# Usage: run_acceptance_tests <project-dir> [output-log-file] [server-log-file]
# Independently re-checks for <project-dir>/serve.py (does not trust
# execute.sh's own "true"/"false" signal) and prints "0 0" immediately
# if it's missing.
#
# Before starting anything, probes 127.0.0.1:8000: if something is already
# listening, that is treated as an error state (a leaked process from a
# prior trial, or the current trial's own agent leaving a server running)
# and this prints "0 0" without starting serve.py, loudly on stderr.
#
# Otherwise starts `python3 serve.py` as a background subprocess in
# <project-dir>, polls 127.0.0.1:8000 for up to 10s (20 attempts, 0.5s
# apart). If the port never opens, tears the subprocess down and prints
# "0 0". If the port opens, it additionally verifies the harness's own
# backgrounded process is still alive (`kill -0`) before trusting that the
# open port is its server -- if the port is open but that process is
# already dead, this is the silent-substitution failure mode and is
# treated as "0 0", not passed through to scoring.
#
# If it's genuinely the harness's own server, runs
# fixtures/acceptance_tests.py -v against it, captures output to
# [output-log-file] (default /dev/null), always tears the subprocess down
# afterward via _stop_server, and prints parse_unittest_output's result.
#
# serve.py's own captured stdout/stderr is copied to [server-log-file]
# (default /dev/null) whenever the pre-launch conflict check trips or the
# port never opens, since that log is the diagnostic that would surface a
# bind failure (e.g. "Address already in use").
run_acceptance_tests() {
    local project_dir="$1"
    local output_log="${2:-/dev/null}"
    local server_log_dest="${3:-/dev/null}"
    local fixtures_dir
    fixtures_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"

    if [ ! -f "$project_dir/serve.py" ]; then
        echo "0 0"
        return
    fi

    if _port_8000_open; then
        local msg="run_acceptance_tests: port 8000 already in use before starting serve.py -- refusing to score against an unknown process (leaked process from a prior trial, or this trial's own agent left a server running)"
        echo "$msg" >&2
        printf '%s\n' "$msg" > "$server_log_dest" 2>/dev/null || true
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
        if _port_8000_open; then
            port_open=true
            break
        fi
        sleep 0.5
    done

    if [ "$port_open" != "true" ]; then
        echo "run_acceptance_tests: port 8000 never opened after starting serve.py -- see server log" >&2
        _stop_server "$server_pid"
        cp "$server_log" "$server_log_dest" 2>/dev/null || true
        rm -f "$server_log"
        echo "0 0"
        return
    fi

    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "run_acceptance_tests: port 8000 is open but the harness's own serve.py process ($server_pid) is not alive -- this is the silent-substitution failure mode, refusing to score" >&2
        cp "$server_log" "$server_log_dest" 2>/dev/null || true
        rm -f "$server_log"
        echo "0 0"
        return
    fi

    local test_output
    test_output="$(mktemp)"
    python3 "$fixtures_dir/acceptance_tests.py" -v > "$test_output" 2>&1 || true

    _stop_server "$server_pid"

    cp "$test_output" "$output_log" 2>/dev/null || true

    local counts
    counts="$(parse_unittest_output "$test_output")"
    rm -f "$server_log" "$test_output"
    echo "$counts"
}
