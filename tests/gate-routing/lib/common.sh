#!/usr/bin/env bash
# Shared helpers for tests/gate-routing/*.sh. Not meant to be executed
# directly -- source it from run-trial.sh / run-all.sh.

set -euo pipefail

# The Superpowers version range this repo's routing strategy has been
# empirically verified against (see README's "Superpowers compatibility"
# section for what that coupling actually depends on).
TESTED_SUPERPOWERS_MIN="6.2.0"
TESTED_SUPERPOWERS_MAX="6.3.0"

# Compares two dotted version strings. Prints "lt", "eq", or "gt" for how
# the first compares to the second.
_compare_versions() {
    local v1="$1" v2="$2"
    if [ "$v1" = "$v2" ]; then
        echo "eq"
        return
    fi
    local lower
    lower="$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -1)"
    if [ "$lower" = "$v1" ]; then
        echo "lt"
    else
        echo "gt"
    fi
}

# Warns (stderr only -- callers capture resolve_superpowers_dir's return
# value via command substitution, so stdout must stay clean) if the given
# Superpowers version falls outside the range this repo's tests have
# actually been run against.
_warn_if_superpowers_version_untested() {
    local version="$1"
    if [ "$(_compare_versions "$version" "$TESTED_SUPERPOWERS_MIN")" = "lt" ]; then
        echo "WARNING: installed Superpowers version ($version) is older than the minimum this repo's tests have been verified against ($TESTED_SUPERPOWERS_MIN). Routing/quality results may not reflect current expected behavior." >&2
    elif [ "$(_compare_versions "$version" "$TESTED_SUPERPOWERS_MAX")" = "gt" ]; then
        echo "NOTE: installed Superpowers version ($version) is newer than the last version this repo's tests have been verified against ($TESTED_SUPERPOWERS_MAX). If routing/quality results look unexpected, this is the first thing to check -- see the README's \"Superpowers compatibility\" section." >&2
    fi
}

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
    _warn_if_superpowers_version_untested "$(basename "$version_dir")"
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
    git -C "$project_dir" init -q -b main
    git -C "$project_dir" config user.name "test"
    git -C "$project_dir" config user.email "test@test.com"
    echo "$project_dir"
}

# Prints one --plugin-dir flag (and its value) per line for the given
# superpowers/factory-gates directories, in the order claude expects them
# on argv. Pure function -- no subprocess, no side effects. If
# factory_gates_dir is "", its --plugin-dir pair is omitted entirely
# (used by the outcome-benchmark suite's baseline condition, which must
# run with no factory-gates plugin loaded at all).
# Usage: mapfile -t flags < <(_plugin_dir_flags <superpowers-dir> <factory-gates-dir|"">)
_plugin_dir_flags() {
    local superpowers_dir="$1"
    local factory_gates_dir="$2"
    printf '%s\n' "--plugin-dir" "$superpowers_dir"
    if [ -n "$factory_gates_dir" ]; then
        printf '%s\n' "--plugin-dir" "$factory_gates_dir"
    fi
}

# Run one conversation turn.
# Usage: run_turn <project-dir> <prompt> <do_continue: 0|1> <superpowers-dir> <factory-gates-dir|""> <log-file>
# factory-gates-dir may be "" -- when empty, the --plugin-dir flag for it
# is omitted entirely (not passed as an empty path).
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

    local plugin_flags=()
    mapfile -t plugin_flags < <(_plugin_dir_flags "$superpowers_dir" "$factory_gates_dir")

    (
        cd "$project_dir"
        timeout 300 claude -p "$prompt" \
            "${continue_flag[@]+"${continue_flag[@]}"}" \
            "${plugin_flags[@]}" \
            --dangerously-skip-permissions \
            --max-turns 3 \
            --output-format stream-json \
            --verbose \
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

# Returns the name of the first Skill tool invocation in a log file
# (namespace prefix stripped, e.g. "superpowers:test-driven-development"
# -> "test-driven-development"), or nothing if no Skill call appears.
first_skill_invoked_in() {
    local log_file="$1"
    grep -o '"skill":"[^"]*"' "$log_file" 2>/dev/null | head -1 | \
        sed -E 's/"skill":"([^:"]*:)?([^"]*)"/\2/' || true
}

# Prints the concatenated assistant text content from a turn's log file --
# the model's own words, with tool_use/tool_result blocks excluded. Used
# by suites that judge conversational output rather than a produced file
# (currently only vertical-slices-gate-quality).
extract_assistant_text() {
    local log_file="$1"
    jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$log_file" 2>/dev/null
}
