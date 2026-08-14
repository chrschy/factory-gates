#!/usr/bin/env bash
# architecture-gate's rubric, using the shared judge mechanics in
# ../../lib/judge-common.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/judge-common.sh
source "$SCRIPT_DIR/../../lib/judge-common.sh"

# Build the judge prompt for a given architecture doc. Prints to stdout.
build_judge_prompt() {
    local doc_path="$1"
    cat <<PROMPT_EOF
You are reviewing an architecture document produced by the factory-gates
plugin's architecture-gate skill. Score it against the rubric below.

## Document to review

$(cat "$doc_path")

## Rubric

| Category | What to look for |
|---|---|
| Template compliance | Required sections present: Components, Data Models, Constraints, Multi-repo/multi-service (if relevant), Open questions |
| Component boundaries | Each component has a stated responsibility, owned data, and which other components it talks to -- no vague/undefined boundaries |
| Data models | Specified at "shape crossing a component boundary" only -- not missing, not over-specified as a full DB schema |
| Constraints | Relevant cross-cutting constraints (auth, versioning, latency, backwards-compat, external deps) stated with a reason each, where applicable |
| Traceability | References the approved spec file by path; "Open questions" section (if used) reflects real ambiguity the spec left open, not fabricated content |
| Scope discipline | Stays out of program-design-gate's territory (no function/method signatures, no call stacks) and writing-plans' territory (no file-by-file task breakdown) |

## Calibration

Only flag issues that would cause a real problem for program-design-gate
(the next gate in the chain) to build on this document: an undefined
component boundary, a data model that's clearly needed but missing, real
scope creep into the next gate's territory. Wording preferences, section
ordering, and stylistic choices are not issues.

## Output format

## Architecture Doc Review

**Status:** Approved | Issues Found

**Issues (if any):**
- [Category]: [specific issue] -- [why it would block program-design-gate]

**Recommendations (advisory, do not block approval):**
- [suggestions]
PROMPT_EOF
}
