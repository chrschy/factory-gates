#!/usr/bin/env bash
# Shared helpers for tests/gate-routing/*.sh. Not meant to be executed
# directly -- source it from run-trial.sh / run-all.sh.

set -euo pipefail

# Resolve the installed Superpowers plugin directory.
# Override with SUPERPOWERS_PLUGIN_DIR to test against a specific
# checkout instead of the locally cached marketplace install.
resolve_superpowers_dir() {
    if [ -n "${SUPERPOWERS_PLUGIN_DIR:-}" ]; then
        echo "$SUPERPOWERS_PLUGIN_DIR"
        return
    fi

    local cache_root="$HOME/.claude/plugins/cache/claude-plugins-official/superpowers"
    if [ ! -d "$cache_root" ]; then
        echo "ERROR: Superpowers plugin not found at $cache_root" >&2
        echo "Install it first, or set SUPERPOWERS_PLUGIN_DIR to a checkout." >&2
        exit 1
    fi

    local version_dir
    version_dir="$(find "$cache_root" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
    if [ -z "$version_dir" ]; then
        echo "ERROR: No version directories found in $cache_root" >&2
        exit 1
    fi
    echo "$version_dir"
}

# Resolve the factory-gates plugin directory (this repo's root).
resolve_factory_gates_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    (cd "$script_dir/../../.." && pwd)
}

# Create an isolated project directory for one trial.
# Usage: setup_trial_dir <base-dir>  (prints the project dir path)
setup_trial_dir() {
    local base_dir="$1"
    local project_dir="$base_dir/project"
    mkdir -p "$project_dir/docs/superpowers/specs" "$project_dir/docs/superpowers/plans"
    echo "$project_dir"
}

# Run one conversation turn.
# Usage: run_turn <project-dir> <prompt> <do_continue: 0|1> <superpowers-dir> <factory-gates-dir> <log-file>
run_turn() {
    local project_dir="$1"
    local prompt="$2"
    local do_continue="$3"
    local superpowers_dir="$4"
    local factory_gates_dir="$5"
    local log_file="$6"

    local continue_flag=()
    if [ "$do_continue" = "1" ]; then
        continue_flag=(--continue)
    fi

    (
        cd "$project_dir"
        timeout 300 claude -p "$prompt" \
            "${continue_flag[@]+"${continue_flag[@]}"}" \
            --plugin-dir "$superpowers_dir" \
            --plugin-dir "$factory_gates_dir" \
            --dangerously-skip-permissions \
            --max-turns 3 \
            --output-format stream-json \
            > "$log_file" 2>&1 || true
    )
}

# Check whether a Skill invocation for the given skill name appears in a
# log file (matches with or without a plugin namespace prefix, e.g.
# "architecture-gate" or "factory-gates:architecture-gate").
skill_invoked_in() {
    local log_file="$1"
    local skill_name="$2"
    grep -q '"name":"Skill"' "$log_file" 2>/dev/null && \
        grep -qE '"skill":"([^"]*:)?'"$skill_name"'"' "$log_file" 2>/dev/null
}
