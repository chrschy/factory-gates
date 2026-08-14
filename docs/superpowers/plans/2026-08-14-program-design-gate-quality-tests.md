# Program Design Gate Quality Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preemptively fix `program-design-gate`'s Open-Questions-style fabrication risk, extract the gate-agnostic judge mechanics into a shared library, and add a `program-design-gate` quality test suite mirroring `architecture-gate`'s.

**Architecture:** `tests/gate-quality/lib/judge-common.sh` (new) holds `run_judge(prompt, output_file)` and `parse_judge_verdict(output_file, expected_header)` — fully gate-agnostic, sandboxed per the fix in PR #7. Each gate's own `lib/judge.sh` holds only `build_judge_prompt(doc_path)` (its rubric) and sources the shared library. `architecture-gate`'s existing suite is refactored onto this shape first (with regression verification), then `program-design-gate`'s new suite is built the same way.

**Tech Stack:** bash, jq, the `claude` CLI — no new dependency, consistent with every other suite in this repo.

## Global Constraints

- `run_judge`'s signature changes from `(doc_path, output_file)` to `(prompt, output_file)` — it no longer knows about `build_judge_prompt` at all; callers build the prompt themselves and pass it in.
- `parse_judge_verdict`'s signature changes from `(output_file)` to `(output_file, expected_header)` — the header-presence sanity check becomes a parameter instead of a hardcoded `"Architecture Doc Review"` string, since `program-design-gate`'s judge replies with a different header (`"Program Design Doc Review"`).
- The sandboxing flags (`--disallowedTools "Bash,Read,Write,Edit,NotebookEdit,Glob,Grep,WebFetch,WebSearch,Task,TodoWrite,ExitPlanMode"`, `--strict-mcp-config`) live once in `judge-common.sh`'s `run_judge` — every gate's suite inherits them automatically.
- `program-design-gate`'s conversation script is 9 turns (vs. `architecture-gate-quality`'s 7): the existing 6 turns through architecture-doc approval, plus `"...please proceed."` (handoff into `program-design-gate`) replacing the old final turn, plus 2 new turns for `program-design-gate`'s own present+approve+write and final review-gate approval.
- `program-design-gate`'s produced doc is located via `find ... -name '*-program-design.md'` (matches the skill's own template path, distinct from `*-architecture.md` and `*-design.md`).
- Trial count: 3, same default as the other suites.
- This is a refactor of already-shipped, already-tested code (`architecture-gate`'s judge/test files) — behavior must not change, only structure. Verified via the existing unit tests passing unchanged plus one real smoke trial, not just "the diff looks right."

## File Structure

```
tests/gate-quality/
  lib/
    judge-common.sh                    — new: run_judge, parse_judge_verdict (gate-agnostic, sandboxed)
  architecture-gate/
    lib/
      judge.sh                          — modified: build_judge_prompt only, sources ../../lib/judge-common.sh
    run-trial.sh                         — modified: builds prompt itself, passes expected_header
    test-judge.sh                        — modified: parse_judge_verdict calls pass expected_header
  program-design-gate/
    README.md                             — new
    run-trial.sh                           — new, 9-turn script
    run-all.sh                              — new
    test-judge.sh                            — new
    lib/
      judge.sh                                — new: build_judge_prompt only, sources ../../lib/judge-common.sh
skills/program-design-gate/SKILL.md         — modified: two wording edits (Part A)
```

---

### Task 1: Preemptive wording fix in program-design-gate

**Files:**
- Modify: `skills/program-design-gate/SKILL.md:32` (self-review checklist item 7)
- Modify: `skills/program-design-gate/SKILL.md:59` (document template's Deviations from architecture placeholder)

**Interfaces:** none

- [ ] **Step 1: Create the branch**

```bash
cd /home/christopher/PycharmProjects/factory-gates
git checkout main
git pull
git checkout -b feature/program-design-gate-quality
```

- [ ] **Step 2: Edit self-review checklist item 7**

Find this exact line:
```
7. **Self-review:** does every signature referenced in one part of the doc get defined somewhere else in it? Any component from the architecture doc with no corresponding signatures here?
```

Replace it with:
```
7. **Self-review:** does every signature referenced in one part of the doc get defined somewhere else in it? Any component from the architecture doc with no corresponding signatures here? For each "Deviations from architecture" entry, re-read the architecture section it cites — does it actually leave this underspecified, or does it already commit to an answer? A fabricated deviation is worse than an empty section.
```

- [ ] **Step 3: Edit the document template's Deviations from architecture placeholder**

Find this exact line:
```
[Anything the architecture doc left open that got resolved here]
```

Replace it with:
```
[Only include an entry here if you can point to the specific architecture doc section that was genuinely underspecified — re-read it before writing this section to confirm. If the architecture doc already specified an answer, that is not a deviation, even if program design had to restate or elaborate on it. If nothing was left open, write "None — the architecture doc fully specified this."]
```

- [ ] **Step 4: Verify both edits landed**

```bash
grep -n "A fabricated deviation is worse than an empty section" skills/program-design-gate/SKILL.md
grep -n "Only include an entry here if you can point to the specific architecture doc section" skills/program-design-gate/SKILL.md
```

Expected: one match each.

- [ ] **Step 5: Commit**

```bash
git add skills/program-design-gate/SKILL.md
git commit -m "fix(program-design-gate): stop fabricating Deviations from architecture entries not actually left open"
```

---

### Task 2: Extract shared judge library, refactor architecture-gate onto it

**Files:**
- Create: `tests/gate-quality/lib/judge-common.sh`
- Modify: `tests/gate-quality/architecture-gate/lib/judge.sh`
- Modify: `tests/gate-quality/architecture-gate/run-trial.sh`
- Modify: `tests/gate-quality/architecture-gate/test-judge.sh`

**Interfaces:**
- Produces (consumed by Task 3's `program-design-gate/lib/judge.sh` and Task 4's `run-trial.sh`): `run_judge(prompt, output_file)`, `parse_judge_verdict(output_file, expected_header)`

- [ ] **Step 1: Write `tests/gate-quality/lib/judge-common.sh`**

```bash
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
```

- [ ] **Step 2: Rewrite `tests/gate-quality/architecture-gate/lib/judge.sh`**

Replace the entire file with:

```bash
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
```

- [ ] **Step 3: Update `tests/gate-quality/architecture-gate/run-trial.sh`'s judge call**

Find this exact block:
```
if [ "$DOC_FOUND" = "true" ] && [ "$ARCHITECTURE_GATE_TRIGGERED" = "true" ]; then
    JUDGE_OUTPUT_FILE="$TRIAL_DIR/judge-output.txt"
    run_judge "$DOC_PATH" "$JUDGE_OUTPUT_FILE"
    VERDICT="$(parse_judge_verdict "$JUDGE_OUTPUT_FILE")"
    case "$VERDICT" in
        pass) OUTCOME="pass" ;;
        fail) OUTCOME="fail" ;;
        *) OUTCOME="inconclusive" ;;
    esac
fi
```

Replace it with:
```
if [ "$DOC_FOUND" = "true" ] && [ "$ARCHITECTURE_GATE_TRIGGERED" = "true" ]; then
    JUDGE_OUTPUT_FILE="$TRIAL_DIR/judge-output.txt"
    JUDGE_PROMPT="$(build_judge_prompt "$DOC_PATH")"
    run_judge "$JUDGE_PROMPT" "$JUDGE_OUTPUT_FILE"
    VERDICT="$(parse_judge_verdict "$JUDGE_OUTPUT_FILE" "Architecture Doc Review")"
    case "$VERDICT" in
        pass) OUTCOME="pass" ;;
        fail) OUTCOME="fail" ;;
        *) OUTCOME="inconclusive" ;;
    esac
fi
```

No other line of this file changes — its `source` line (`source "$SCRIPT_DIR/lib/judge.sh"`) already transitively picks up `run_judge`/`parse_judge_verdict` since `lib/judge.sh` now sources `judge-common.sh` itself.

- [ ] **Step 4: Update `tests/gate-quality/architecture-gate/test-judge.sh`'s six `parse_judge_verdict` calls**

Each of these six lines currently ends in `parse_judge_verdict "$TMPFILE")"` — add the expected-header argument to each:

```
assert_eq "Approved status -> pass" "pass" "$(parse_judge_verdict "$TMPFILE" "Architecture Doc Review")"
```
```
assert_eq "Issues Found status -> fail" "fail" "$(parse_judge_verdict "$TMPFILE" "Architecture Doc Review")"
```
```
assert_eq "malformed output, no header -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Architecture Doc Review")"
```
```
assert_eq "header present but no Status line -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Architecture Doc Review")"
```
```
assert_eq "empty file -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Architecture Doc Review")"
```
```
assert_eq "placeholder Status line -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Architecture Doc Review")"
```

(Six lines total, in the same order as they currently appear in the file — each just gains `"Architecture Doc Review"` as a second argument to `parse_judge_verdict`. The `build_judge_prompt` test block below them is unchanged.)

- [ ] **Step 5: Verify syntax on all four touched/new files**

```bash
bash -n tests/gate-quality/lib/judge-common.sh
bash -n tests/gate-quality/architecture-gate/lib/judge.sh
bash -n tests/gate-quality/architecture-gate/run-trial.sh
bash -n tests/gate-quality/architecture-gate/test-judge.sh
```

Expected: no output, exit 0 for each.

- [ ] **Step 6: Run architecture-gate's existing unit tests — regression check**

```bash
chmod +x tests/gate-quality/lib/judge-common.sh
tests/gate-quality/architecture-gate/test-judge.sh
```

Expected: `Passed: 7, Failed: 0`, exit 0 — identical to before the refactor. If anything fails, the refactor broke something; fix before proceeding, do not adjust the tests to match broken behavior.

- [ ] **Step 7: Run one real smoke trial — confirm the refactor didn't break live execution**

```bash
tests/gate-quality/architecture-gate/run-trial.sh /tmp/factory-gates-refactor-smoke-test
cat /tmp/factory-gates-refactor-smoke-test/result.json
```

Expected: takes several minutes, real token cost. Any of pass/fail/inconclusive is an acceptable outcome (matching this suite's own established smoke-test bar) — what matters is that it runs end-to-end and produces a well-formed `result.json` with a real `judge_output_file`, proving the refactored `run_judge`/`parse_judge_verdict`/`build_judge_prompt` wiring works together correctly in a real trial, not just in unit tests.

- [ ] **Step 8: Commit**

```bash
rm -rf /tmp/factory-gates-refactor-smoke-test
git add tests/gate-quality/lib/judge-common.sh tests/gate-quality/architecture-gate/lib/judge.sh tests/gate-quality/architecture-gate/run-trial.sh tests/gate-quality/architecture-gate/test-judge.sh
git commit -m "refactor(tests): extract shared judge mechanics into tests/gate-quality/lib/judge-common.sh"
```

---

### Task 3: program-design-gate judge library + unit tests

**Files:**
- Create: `tests/gate-quality/program-design-gate/lib/judge.sh`
- Create: `tests/gate-quality/program-design-gate/test-judge.sh`

**Interfaces:**
- Consumes: `run_judge`, `parse_judge_verdict` from Task 2's `tests/gate-quality/lib/judge-common.sh`
- Produces (consumed by Task 4's `run-trial.sh`): `build_judge_prompt(doc_path)`

- [ ] **Step 1: Write `tests/gate-quality/program-design-gate/lib/judge.sh`**

```bash
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
```

- [ ] **Step 2: Write `tests/gate-quality/program-design-gate/test-judge.sh`**

```bash
#!/usr/bin/env bash
# Unit tests for lib/judge.sh's build_judge_prompt (program-design-gate's
# rubric) and the shared parse_judge_verdict it inherits. Pure text
# parsing/templating, no live claude -p calls -- fast and deterministic.
# Usage: ./test-judge.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/judge.sh
source "$SCRIPT_DIR/lib/judge.sh"
set +e

PASS=0
FAIL=0

assert_eq() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $description"
        echo "  expected: $expected"
        echo "  actual:   $actual"
    fi
}

TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

# --- parse_judge_verdict (shared function, program-design-gate's header) ---

cat > "$TMPFILE" <<'EOF'
## Program Design Doc Review

**Status:** Approved

**Issues (if any):**
None.
EOF
assert_eq "Approved status -> pass" "pass" "$(parse_judge_verdict "$TMPFILE" "Program Design Doc Review")"

cat > "$TMPFILE" <<'EOF'
## Program Design Doc Review

**Status:** Issues Found

**Issues (if any):**
- Signature consistency: getLink(code) is called in the Call Stacks section but only createLink is defined in the Components section.
EOF
assert_eq "Issues Found status -> fail" "fail" "$(parse_judge_verdict "$TMPFILE" "Program Design Doc Review")"

cat > "$TMPFILE" <<'EOF'
This is not a real review, just some rambling text with no Status line
and no recognizable structure at all.
EOF
assert_eq "malformed output, no header -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Program Design Doc Review")"

cat > "$TMPFILE" <<'EOF'
## Program Design Doc Review

I think this looks fine overall.
EOF
assert_eq "header present but no Status line -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Program Design Doc Review")"

: > "$TMPFILE"
assert_eq "empty file -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Program Design Doc Review")"

cat > "$TMPFILE" <<'EOF'
## Program Design Doc Review

**Status:** Approved | Issues Found

**Issues (if any):**
- [Category]: [specific issue] -- [why it would block writing-plans]
EOF
assert_eq "placeholder Status line -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Program Design Doc Review")"

cat > "$TMPFILE" <<'EOF'
## Architecture Doc Review

**Status:** Approved
EOF
assert_eq "wrong gate's header -> unparseable (header mismatch)" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Program Design Doc Review")"

# --- build_judge_prompt (program-design-gate's own rubric) ---

cat > "$TMPFILE" <<'EOF'
# My Feature -- Program Design

## redirect-service
**File:** `src/redirect.go`

```
func Redirect(code string) (string, error)
```
EOF
PROMPT_OUTPUT="$(build_judge_prompt "$TMPFILE")"
if printf '%s' "$PROMPT_OUTPUT" | grep -q "## Rubric" && printf '%s' "$PROMPT_OUTPUT" | grep -q "func Redirect(code string) (string, error)"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: build_judge_prompt embeds both the rubric and the document content"
fi

if printf '%s' "$PROMPT_OUTPUT" | grep -q "Program Design Doc Review"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: build_judge_prompt's output format asks for the program-design-gate-specific header"
fi

echo ""
echo "Passed: $PASS, Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n tests/gate-quality/program-design-gate/lib/judge.sh
bash -n tests/gate-quality/program-design-gate/test-judge.sh
```

Expected: no output, exit 0 each.

- [ ] **Step 4: Run the tests**

```bash
chmod +x tests/gate-quality/program-design-gate/lib/judge.sh tests/gate-quality/program-design-gate/test-judge.sh
tests/gate-quality/program-design-gate/test-judge.sh
```

Expected: `Passed: 9, Failed: 0`, exit 0. If any FAIL lines print, fix `judge.sh` (not the test) and re-run until clean.

- [ ] **Step 5: Commit**

```bash
git add tests/gate-quality/program-design-gate/lib/judge.sh tests/gate-quality/program-design-gate/test-judge.sh
git commit -m "test(tests): add program-design-gate quality judge library with unit tests"
```

---

### Task 4: program-design-gate single-trial driver

**Files:**
- Create: `tests/gate-quality/program-design-gate/run-trial.sh`

**Interfaces:**
- Consumes: `resolve_superpowers_dir`, `resolve_factory_gates_dir`, `setup_trial_dir`, `run_turn`, `skill_invoked_in` from `tests/gate-routing/lib/common.sh`; `build_judge_prompt` from Task 3's `lib/judge.sh`; `run_judge`, `parse_judge_verdict` transitively from `tests/gate-quality/lib/judge-common.sh`
- Produces: `<trial-dir>/result.json` with fields `trial_dir`, `brainstorming_triggered`, `architecture_gate_triggered`, `program_design_gate_triggered`, `doc_found`, `doc_path`, `judge_output_file`, `turns_used`, `outcome` (`pass`|`fail`|`inconclusive`)

- [ ] **Step 1: Write `tests/gate-quality/program-design-gate/run-trial.sh`**

```bash
#!/usr/bin/env bash
# Run a single program-design-gate quality trial.
# Usage: run-trial.sh <trial-output-dir>
#
# Drives a real brainstorming -> architecture-gate -> program-design-gate
# conversation on a toy URL-shortener feature, locates the produced
# program design doc, and scores it with a headless LLM judge against the
# rubric in
# docs/superpowers/specs/2026-08-14-program-design-gate-quality-tests-design.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../gate-routing/lib/common.sh
source "$SCRIPT_DIR/../../gate-routing/lib/common.sh"
# shellcheck source=lib/judge.sh
source "$SCRIPT_DIR/lib/judge.sh"

TRIAL_DIR="${1:-}"

if [ -z "$TRIAL_DIR" ]; then
    echo "Usage: $0 <trial-output-dir>" >&2
    exit 1
fi

SUPERPOWERS_DIR="$(resolve_superpowers_dir)"
FACTORY_GATES_DIR="$(resolve_factory_gates_dir)"

mkdir -p "$TRIAL_DIR"
PROJECT_DIR="$(setup_trial_dir "$TRIAL_DIR")"

FEATURE_REQUEST="I want to build a small URL shortener. Two components: a public redirect service that takes a short code and 302-redirects to the original URL, and an admin API for creating new short links (POST with a target URL, returns a short code). Both read/write the same data store (short code -> target URL mapping). Redirect latency matters -- it's on the hot path for every click. No user accounts, no analytics, no custom short codes (always generated). That's the complete design -- no open questions on my end."

TURNS=(
    "$FEATURE_REQUEST"
    "That approach looks good -- please continue."
    "Approved. Please write the spec and commit it."
    "I've reviewed the spec, it looks good, please proceed."
    "That architecture approach looks good -- please continue."
    "Approved. Please write the architecture doc."
    "I've reviewed the architecture doc, it looks good, please proceed."
    "Approved. Please write the program design doc."
    "I've reviewed the program design doc, it looks good."
)

BRAINSTORMING_TRIGGERED=false
ARCHITECTURE_GATE_TRIGGERED=false
PROGRAM_DESIGN_GATE_TRIGGERED=false
TURNS_USED=0

for i in "${!TURNS[@]}"; do
    TURN_NUM=$((i + 1))
    TURNS_USED=$TURN_NUM
    PROMPT="${TURNS[$i]}"
    LOG_FILE="$TRIAL_DIR/turn${TURN_NUM}.json"

    if [ "$TURN_NUM" = "1" ]; then
        run_turn "$PROJECT_DIR" "$PROMPT" 0 "$SUPERPOWERS_DIR" "$FACTORY_GATES_DIR" "$LOG_FILE"
    else
        run_turn "$PROJECT_DIR" "$PROMPT" 1 "$SUPERPOWERS_DIR" "$FACTORY_GATES_DIR" "$LOG_FILE"
    fi

    if [ "$BRAINSTORMING_TRIGGERED" = "false" ] && skill_invoked_in "$LOG_FILE" "brainstorming"; then
        BRAINSTORMING_TRIGGERED=true
    fi
    if [ "$ARCHITECTURE_GATE_TRIGGERED" = "false" ] && skill_invoked_in "$LOG_FILE" "architecture-gate"; then
        ARCHITECTURE_GATE_TRIGGERED=true
    fi
    if [ "$PROGRAM_DESIGN_GATE_TRIGGERED" = "false" ] && skill_invoked_in "$LOG_FILE" "program-design-gate"; then
        PROGRAM_DESIGN_GATE_TRIGGERED=true
    fi
done

DOC_PATH="$(find "$PROJECT_DIR/docs/superpowers/specs" -name '*-program-design.md' -print -quit 2>/dev/null || true)"

DOC_FOUND=false
if [ -n "$DOC_PATH" ]; then
    DOC_FOUND=true
fi

OUTCOME="inconclusive"
JUDGE_OUTPUT_FILE=""

if [ "$DOC_FOUND" = "true" ] && [ "$PROGRAM_DESIGN_GATE_TRIGGERED" = "true" ]; then
    JUDGE_OUTPUT_FILE="$TRIAL_DIR/judge-output.txt"
    JUDGE_PROMPT="$(build_judge_prompt "$DOC_PATH")"
    run_judge "$JUDGE_PROMPT" "$JUDGE_OUTPUT_FILE"
    VERDICT="$(parse_judge_verdict "$JUDGE_OUTPUT_FILE" "Program Design Doc Review")"
    case "$VERDICT" in
        pass) OUTCOME="pass" ;;
        fail) OUTCOME="fail" ;;
        *) OUTCOME="inconclusive" ;;
    esac
fi

cat > "$TRIAL_DIR/result.json" <<EOF
{
  "trial_dir": "$TRIAL_DIR",
  "brainstorming_triggered": $BRAINSTORMING_TRIGGERED,
  "architecture_gate_triggered": $ARCHITECTURE_GATE_TRIGGERED,
  "program_design_gate_triggered": $PROGRAM_DESIGN_GATE_TRIGGERED,
  "doc_found": $DOC_FOUND,
  "doc_path": "${DOC_PATH:-}",
  "judge_output_file": "${JUDGE_OUTPUT_FILE:-}",
  "turns_used": $TURNS_USED,
  "outcome": "$OUTCOME"
}
EOF

echo "Trial complete: outcome=$OUTCOME turns_used=$TURNS_USED doc_found=$DOC_FOUND"
echo "Result: $TRIAL_DIR/result.json"

if [ "$OUTCOME" = "pass" ]; then
    exit 0
else
    exit 1
fi
```

- [ ] **Step 2: Verify syntax**

```bash
chmod +x tests/gate-quality/program-design-gate/run-trial.sh
bash -n tests/gate-quality/program-design-gate/run-trial.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Smoke-test one real trial**

```bash
tests/gate-quality/program-design-gate/run-trial.sh /tmp/factory-gates-pdg-quality-smoke-test
cat /tmp/factory-gates-pdg-quality-smoke-test/result.json
```

Expected: takes longer than the architecture-gate suite's smoke test (9 turns instead of 7, plus a judge call) — likely several minutes, real token cost. Any of pass/fail/inconclusive is an acceptable outcome. If `program_design_gate_triggered` is false, check `architecture_gate_triggered` first — if architecture-gate itself didn't trigger (the known routing non-determinism from `tests/gate-routing/`), program-design-gate never got a chance to run, which is expected and not a bug in this new harness. Only treat it as a real problem if the script errors out before producing `result.json` at all.

- [ ] **Step 4: Commit**

```bash
rm -rf /tmp/factory-gates-pdg-quality-smoke-test
git add tests/gate-quality/program-design-gate/run-trial.sh
git commit -m "test(tests): add program-design-gate quality single-trial driver"
```

---

### Task 5: program-design-gate trial batch orchestrator

**Files:**
- Create: `tests/gate-quality/program-design-gate/run-all.sh`

**Interfaces:**
- Consumes: `tests/gate-quality/program-design-gate/run-trial.sh` from Task 4 (invoked as a subprocess)
- Produces: a printed pass/fail/inconclusive table, and `<run-dir>/summary.json`

- [ ] **Step 1: Write `tests/gate-quality/program-design-gate/run-all.sh`**

```bash
#!/usr/bin/env bash
# Run the full program-design-gate quality trial batch and report
# pass/fail/inconclusive rates.
#
# Usage: run-all.sh [--trials N]
#   --trials N   Number of trials (default: 3)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TRIALS=3

while [ $# -gt 0 ]; do
    case "$1" in
        --trials)
            TRIALS="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

TIMESTAMP=$(date +%s)
RUN_DIR="/tmp/factory-gates-gate-quality-tests/${TIMESTAMP}"
mkdir -p "$RUN_DIR"

echo "=== Program-Design-Gate Quality Test Run ==="
echo "Trials: $TRIALS"
echo "Output dir: $RUN_DIR"
echo ""

RESULT_FILES=()

for trial_num in $(seq 1 "$TRIALS"); do
    TRIAL_DIR="$RUN_DIR/trial-$trial_num"
    echo ">>> Running trial $trial_num..."
    "$SCRIPT_DIR/run-trial.sh" "$TRIAL_DIR" || true
    if [ -f "$TRIAL_DIR/result.json" ]; then
        RESULT_FILES+=("$TRIAL_DIR/result.json")
    else
        echo "WARNING: no result.json for trial $trial_num (script likely crashed)" >&2
    fi
    echo ""
done

if [ "${#RESULT_FILES[@]}" -eq 0 ]; then
    echo "ERROR: no trials produced results" >&2
    exit 1
fi

echo "=== Summary ==="
jq -s '
  {
    trials: length,
    pass: ([.[] | select(.outcome == "pass")] | length),
    fail: ([.[] | select(.outcome == "fail")] | length),
    inconclusive: ([.[] | select(.outcome == "inconclusive")] | length)
  }
' "${RESULT_FILES[@]}" | tee "$RUN_DIR/summary.json"

echo ""
echo "Full results: $RUN_DIR"

FAIL_COUNT=$(jq -s '[.[] | select(.outcome == "fail")] | length' "${RESULT_FILES[@]}")
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "NOTE: $FAIL_COUNT trial(s) had the judge find issues in the program design doc. Check judge_output_file in each trial's result.json for details."
    exit 1
fi
```

- [ ] **Step 2: Verify syntax**

```bash
chmod +x tests/gate-quality/program-design-gate/run-all.sh
bash -n tests/gate-quality/program-design-gate/run-all.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Smoke-test with a single trial**

```bash
tests/gate-quality/program-design-gate/run-all.sh --trials 1
```

Expected: prints the run header, one `>>> Running trial 1...` line, then a `=== Summary ===` JSON object (`trials: 1`, `pass`/`fail`/`inconclusive` summing to 1).

- [ ] **Step 4: Commit**

```bash
git add tests/gate-quality/program-design-gate/run-all.sh
git commit -m "test(tests): add program-design-gate quality trial batch orchestrator"
```

---

### Task 6: Documentation

**Files:**
- Create: `tests/gate-quality/program-design-gate/README.md`

**Interfaces:** none

- [ ] **Step 1: Write `tests/gate-quality/program-design-gate/README.md`**

```markdown
# Program Design Gate Quality Tests

Judges the *content quality* of the document `program-design-gate`
produces, not whether the skill gets invoked. Drives a real
`brainstorming` -> `architecture-gate` -> `program-design-gate`
conversation on the same toy URL-shortener feature used by
`../architecture-gate/`, then scores the resulting program design
document against a rubric derived from `program-design-gate`'s own
checklist and template, using the shared headless LLM judge in
`../lib/judge-common.sh`.

## How it works

1. A real `claude -p` conversation (both `superpowers` and `factory-gates`
   loaded) walks through a 9-turn script -- the full 7 turns from
   `../architecture-gate/`'s suite through architecture-doc approval,
   plus 2 more turns for `program-design-gate`'s own present+approve+write
   step and final review-gate approval.
2. The produced `docs/superpowers/specs/*-program-design.md` file is
   located in the trial's isolated project directory.
3. A **second, separate, sandboxed** `claude -p` call (see
   `../lib/judge-common.sh`) is given the document plus this gate's
   rubric and asked to return `Approved` or `Issues Found` with itemized
   findings.

## Running

```bash
# Default batch (3 trials, likely 20-40+ minutes total, real token cost --
# each trial is longer than tests/gate-quality/architecture-gate/'s, since
# it walks through one more gate)
./run-all.sh

# Cheap single-trial spot check while iterating on the harness itself
./run-all.sh --trials 1
```

Requires: `claude` CLI installed and authenticated, `jq`, and the
Superpowers plugin installed locally (see `../../gate-routing/README.md`
for the same prerequisites and `SUPERPOWERS_PLUGIN_DIR` override).

Unit tests for the judge's parsing/templating logic (fast, no live
calls):

```bash
./test-judge.sh
```

## Reading the output

Same three-way outcome split as `../architecture-gate/`:

- **pass** — the judge reviewed the doc and returned `Approved`
- **fail** — the judge reviewed the doc and returned `Issues Found` --
  check that trial's `judge_output_file` (path is in its `result.json`)
- **inconclusive** — no program design doc was produced within the
  9-turn script -- check `result.json`'s `architecture_gate_triggered`
  and `program_design_gate_triggered` fields to see how far the
  conversation actually got before concluding this is a quality-suite
  bug rather than the known routing non-determinism documented in
  `../../gate-routing/`

## Known limitations

Same as `../architecture-gate/README.md`'s "Known limitations" section
(non-determinism on two axes, judge sees only the final document not the
conversation, not run in CI) -- additionally:

- **Longer trials compound non-determinism.** Reaching `program-design-gate`
  requires `architecture-gate` to have triggered first, so this suite's
  `inconclusive` rate is expected to run higher than
  `../architecture-gate/`'s alone.
```

- [ ] **Step 2: Verify**

```bash
grep -c "^## " tests/gate-quality/program-design-gate/README.md
```

Expected: 4.

- [ ] **Step 3: Commit**

```bash
git add tests/gate-quality/program-design-gate/README.md
git commit -m "docs(tests): document program-design-gate quality test suite"
```

---

### Task 7: Run the full batch and report results

**Files:** none

**Interfaces:**
- Consumes: `run-all.sh` from Task 5

- [ ] **Step 1: Run the full default batch**

```bash
cd /home/christopher/PycharmProjects/factory-gates
tests/gate-quality/program-design-gate/run-all.sh
```

Expected: likely 20-40+ minutes given 3 trials at 9 turns each plus judge calls. Ends with the `=== Summary ===` JSON.

- [ ] **Step 2: Report to human partner**

Paste the summary into the conversation with your human partner. For any `fail` trial, paste the relevant `judge_output_file` contents so they can see the actual issues raised — this run doubles as verification of Task 1's preemptive fix, so specifically check whether any `fail` is a fabricated "Deviations from architecture" entry (would mean the fix didn't work) versus a different, unrelated issue. For any `inconclusive` trial, report which gate stopped triggering (`architecture_gate_triggered` / `program_design_gate_triggered` in that trial's `result.json`) so it's clear whether this is the known upstream routing non-determinism or something new. Do not editorialize about whether the result is "good" or "bad" beyond stating the numbers and the actual issues found.

---

### Task 8: Open PR, review, merge

**Files:** none

**Interfaces:**
- Consumes: all commits from Tasks 1-6 on `feature/program-design-gate-quality`; Task 7's results to paste into the PR body

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/program-design-gate-quality
```

- [ ] **Step 2: Open the PR**

Fill in the `<PASTE ...>` placeholder with Task 7's actual results before running this command.

```bash
gh pr create --title "test(tests): add program-design-gate quality suite, fix Deviations fabrication risk, share judge mechanics" --body "$(cat <<'EOF'
## Who is submitting this PR? (required)

| Field | Value |
|-------|-------|
| Your model + version | Claude Sonnet 5 |
| Harness + version | Claude Code |
| All plugins installed | superpowers |
| Human partner who reviewed this diff | [@chrschy](https://github.com/chrschy) |

## What problem are you trying to solve?

Three related things: (1) program-design-gate's "Deviations from
architecture" template wording had the same unguarded pattern that caused
architecture-gate's Open Questions fabrication bug (PR #6) -- fixed
preemptively. (2) program-design-gate had never been exercised or judged
since the original scaffold. (3) The judge mechanics (run_judge,
parse_judge_verdict) were duplicated per-suite, meaning the sandboxing fix
(PR #7) would need reapplying for every future gate's quality suite.

## What does this PR change?

Two wording edits to skills/program-design-gate/SKILL.md (same pattern as
PR #6). Extracts run_judge/parse_judge_verdict into a new shared
tests/gate-quality/lib/judge-common.sh, refactors architecture-gate's
suite onto it (verified via its existing unit tests + one real smoke
trial, no behavior change). Adds tests/gate-quality/program-design-gate/,
a 9-turn quality suite extending the existing architecture-gate-quality
conversation one gate further, using the shared judge library.

## Which gate does this touch?

program-design-gate (wording fix + new quality suite). architecture-gate
is also touched, but only its test-suite plumbing (refactor), not its
SKILL.md.

## What alternatives did you consider?

Considered keeping the judge mechanics duplicated per-suite (simpler,
zero risk to already-shipped code) but the sandboxing-fix-must-be-
reapplied-per-gate cost is real and already happened once -- extracting
now, with two real consumers, isn't premature.

## Existing PRs
- [x] I have reviewed open AND closed PRs/issues for duplicates or prior art
- Related PRs/issues: none found

## Rigor
- [x] This change was tested adversarially, not just on the happy path
- [x] architecture-gate's existing unit tests pass unchanged after the
      refactor (7/7), plus one real smoke trial confirming live execution
      still works end to end
- [x] program-design-gate's new unit tests: 9/9 passing
- [x] Ran tests/gate-quality/program-design-gate/run-all.sh -- results:

<PASTE Task 7's summary JSON and fail/inconclusive details here>

This run also serves as verification of the preemptive Deviations fix --
see the pasted details above for whether any fail was a fabricated
Deviations entry (would mean the fix didn't work) or something else.

## Human review
- [ ] A human has reviewed the COMPLETE proposed diff before submission
EOF
)"
```

- [ ] **Step 3: Human review gate**

Stop here. Show the human partner the complete diff (`git diff main...feature/program-design-gate-quality`), the PR URL, and Task 7's results. Do not proceed to Step 4 until they explicitly approve.

- [ ] **Step 4: Merge**

```bash
gh pr merge --squash --delete-branch --admin
```

- [ ] **Step 5: Verify**

```bash
git checkout main
git pull
ls tests/gate-quality/lib/judge-common.sh tests/gate-quality/program-design-gate/
grep -n "A fabricated deviation is worse than an empty section" skills/program-design-gate/SKILL.md
```

Expected: all files present, one grep match confirming the wording fix is live.

## Self-Review

1. **Spec coverage:** Part A (Task 1), Part C's refactor with explicit regression verification (Task 2), Part B's new suite (Tasks 3-6), a real batch run doubling as fix verification (Task 7), PR/merge flow (Task 8). Every piece of the spec's three parts has a corresponding task.
2. **Placeholder scan:** two intentional, explicitly-flagged placeholders in Task 8 Step 2, same pattern as every prior plan in this repo — must be filled from Task 7's real output before opening the PR.
3. **Type consistency:** `run_judge(prompt, output_file)` and `parse_judge_verdict(output_file, expected_header)`'s new signatures are used identically across Task 2's refactored `architecture-gate` files and Task 3-4's new `program-design-gate` files — no drift between the two consumers of the shared library. `result.json`'s field names in Task 4 (`program_design_gate_triggered` added alongside the two carried-over trigger fields) match what Task 5's `jq` aggregation and Task 6's README both describe.
