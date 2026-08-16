#!/usr/bin/env bash
# Execution-phase mechanics for tests/outcome-benchmark. Sourced by
# run-trial.sh.

set -euo pipefail

# Usage: _build_execution_prompt <plan-path> <spec-path>
# Pure string template -- prints the fixed, identical-for-both-conditions
# implementation prompt to stdout, with the two paths interpolated.
_build_execution_prompt() {
    local plan_path="$1"
    local spec_path="$2"
    cat <<PROMPT_EOF
Implement the plan at $plan_path completely, in this repository. The approved spec is at $spec_path for reference. Regardless of what the plan or spec say about transport details, the final result must expose exactly this HTTP contract, since it will be tested automatically:

- POST /api/links with JSON body {"url": "<target>"} -> 201 with JSON body {"code": "<short code>"}
- GET /<code> -> 302 with Location set to the stored target URL
- GET /<code> for an unknown code -> 404
- The service must be startable from the project root with exactly: python3 serve.py, listening on port 8000.

Implement real, working behavior -- not stubs. When finished, confirm the server starts cleanly with that exact command.
PROMPT_EOF
}

# Usage: run_execution_step <project-dir> <plan-path> <spec-path> <log-file>
# Runs ONE unscripted claude -p call in <project-dir>, with NO
# --plugin-dir flags at all (identical for both conditions), --max-turns
# 40, wrapped in `timeout 1800`. Prints "true" to stdout if
# <project-dir>/serve.py exists after the call returns, else "false" --
# an existence check only, not proof the server works.
run_execution_step() {
    local project_dir="$1"
    local plan_path="$2"
    local spec_path="$3"
    local log_file="$4"

    local prompt
    prompt="$(_build_execution_prompt "$plan_path" "$spec_path")"

    (
        cd "$project_dir" || exit 1
        timeout 1800 claude -p "$prompt" \
            --dangerously-skip-permissions \
            --max-turns 40 \
            --output-format stream-json \
            --verbose \
            > "$log_file" 2>&1 || true
    ) || true

    if [ -f "$project_dir/serve.py" ]; then
        echo "true"
    else
        echo "false"
    fi
}
