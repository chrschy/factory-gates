#!/usr/bin/env bash
# Gate-agnostic headless LLM-judge mechanics, shared across all
# tests/gate-quality/<gate>/ suites. No plugins needed -- the judge only
# reads and reasons over whatever prompt it's given, it doesn't need any
# skill loaded.

set -euo pipefail

# Run the judge against an already-built prompt, writing its raw response
# to output_file. Sandboxed to the prompt only: no filesystem, shell, or
# MCP tool access, so the judge can't see anything beyond what's in the
# prompt text (see
# docs/superpowers/specs/2026-08-14-judge-tool-sandboxing-fix-design.md
# for why this matters).
# Usage: run_judge <prompt> <output_file>
run_judge() {
    local prompt="$1"
    local output_file="$2"
    timeout 120 claude -p "$prompt" --dangerously-skip-permissions \
        --disallowedTools "Bash,Read,Write,Edit,NotebookEdit,Glob,Grep,WebFetch,WebSearch,Task,TodoWrite,ExitPlanMode" \
        --strict-mcp-config \
        > "$output_file" 2>&1 || true
}

# Parse a judge output file into "pass", "fail", or "unparseable".
# expected_header is the gate-specific "## <Gate> Doc Review" heading text
# each gate's build_judge_prompt asks the judge to reply with -- used as a
# sanity check that the response is structured as expected before looking
# for a Status line.
# Usage: parse_judge_verdict <output_file> <expected_header>
parse_judge_verdict() {
    local output_file="$1"
    local expected_header="$2"
    if ! grep -q "$expected_header" "$output_file" 2>/dev/null; then
        echo "unparseable"
        return
    fi
    local status_line
    status_line="$(grep -E '^\*\*Status:\*\*' "$output_file" 2>/dev/null | head -1)"
    if printf '%s' "$status_line" | grep -qE '^\*\*Status:\*\*[[:space:]]*Approved[[:space:]]*$'; then
        echo "pass"
    elif printf '%s' "$status_line" | grep -qE '^\*\*Status:\*\*[[:space:]]*Issues Found[[:space:]]*$'; then
        echo "fail"
    else
        echo "unparseable"
    fi
}
