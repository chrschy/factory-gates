#!/usr/bin/env bash
# program-design-gate's rubric, using the shared judge mechanics in
# ../../lib/judge-common.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/judge-common.sh
source "$SCRIPT_DIR/../../lib/judge-common.sh"

# Build the judge prompt for a given program design doc. Prints to stdout.
build_judge_prompt() {
    local doc_path="$1"
    cat <<PROMPT_EOF
You are reviewing a program design document produced by the factory-gates
plugin's program-design-gate skill. Score it against the rubric below.

## Document to review

$(cat "$doc_path")

## Rubric

| Category | What to look for |
|---|---|
| Template compliance | References the architecture doc by path; at least one Component/Module section with a File path and a signature block; Call Stacks section; Deviations from architecture section |
| Signature completeness | Every component from the architecture doc has corresponding signatures here -- no orphaned components |
| Signature consistency | Every signature referenced anywhere in the doc (e.g. in a call stack) is actually defined somewhere else in it -- no dangling references |
| No implementation bodies | Signatures only -- no function bodies, no test code |
| Traceability | "Deviations from architecture" entries (if any) reflect genuine underspecification in the architecture doc, not fabricated ambiguity -- verify against what the architecture doc actually says |
| Scope discipline | Stays out of writing-plans'/vertical-slices-gate's territory (no task sequencing, no file-by-file task breakdown) and doesn't re-litigate architecture-gate's already-fixed component boundaries |

## Calibration

Only flag issues that would cause a real problem for writing-plans to
build a task-level plan against this document: a missing signature for
something the architecture doc requires, an inconsistent signature
referenced in two places with different types, a fabricated deviation
claim, real scope creep into task-breakdown territory. Wording
preferences and formatting choices are not issues.

## Output format

## Program Design Doc Review

**Status:** Approved | Issues Found

**Issues (if any):**
- [Category]: [specific issue] -- [why it would block writing-plans]

**Recommendations (advisory, do not block approval):**
- [suggestions]
PROMPT_EOF
}
