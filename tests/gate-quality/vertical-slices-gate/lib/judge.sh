#!/usr/bin/env bash
# vertical-slices-gate's rubric, using the shared judge mechanics in
# ../../lib/judge-common.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/judge-common.sh
source "$SCRIPT_DIR/../../lib/judge-common.sh"

# Build the judge prompt for a given vertical-slices-gate conversation
# transcript excerpt (the assistant's text from the turn the skill fired
# in -- not a file path, since this gate produces no document). Prints to
# stdout.
build_judge_prompt() {
    local transcript="$1"
    cat <<PROMPT_EOF
You are reviewing a conversation excerpt from the factory-gates plugin's
vertical-slices-gate skill -- the assistant's own turn summarizing build
order and asking for confirmation before execution starts. Score it
against the rubric below.

## Transcript excerpt to review

$transcript

## Rubric

| Category | What to look for |
|---|---|
| Slice order stated | Lists the build-order tasks/slices, one line each, in the order they'll be built |
| Demoable/testable noted | For each slice, names what's independently testable/demoable after it lands |
| Coordination risk | If the plan spans multiple repos/services, explicit order dependencies are called out (what ships/deploys before what); if genuinely single-service, no fabricated cross-service risk is invented |
| Intermediate-test gaps | Any slice that can't be verified until a later slice lands is surfaced explicitly, not glossed over |
| Explicit confirmation requested | Ends with a clear, short confirm-or-reorder question -- not a redesign prompt |
| Scope discipline | Doesn't re-litigate architecture/program-design decisions already fixed in earlier gates; doesn't duplicate writing-plans' own task-level implementation detail |

## Calibration

Only flag issues that would cause a real problem for a human confirming
this build order: a missing task from the plan, invented coordination
risk that doesn't actually exist, no confirmation question at all,
re-opening architecture or program-design decisions. Wording and
formatting preferences are not issues.

## Output format

## Vertical Slices Gate Review

**Status:** Approved | Issues Found

**Issues (if any):**
- [Category]: [specific issue]

**Recommendations (advisory, do not block approval):**
- [suggestions]
PROMPT_EOF
}
