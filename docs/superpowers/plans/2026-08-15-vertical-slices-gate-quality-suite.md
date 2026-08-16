# Vertical Slices Gate Quality Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a quality test suite for `vertical-slices-gate` (Gate 4) that judges the conversation turn it produces, since (unlike `architecture-gate`/`program-design-gate`) it writes no document.

**Architecture:** One new shared helper (`extract_assistant_text`) in `tests/gate-routing/lib/common.sh`. One new suite under `tests/gate-quality/vertical-slices-gate/`, following the exact file layout of `tests/gate-quality/program-design-gate/`, reusing `tests/gate-quality/lib/judge-common.sh` unchanged.

**Tech Stack:** bash, jq, claude CLI (`claude -p`).

## Global Constraints

- Reuse the same URL-shortener toy feature text already used by `tests/gate-quality/architecture-gate/` and `tests/gate-quality/program-design-gate/`.
- `run_judge`/`parse_judge_verdict` in `tests/gate-quality/lib/judge-common.sh` are not modified — this suite only adds a new `build_judge_prompt` in its own `lib/judge.sh`, exactly like the other two suites.
- Default trial count for this suite's `run-all.sh` is **2**, not 3 — stated explicitly in code and README, not silently inherited from the other suites' default.
- The turn script stops after `vertical-slices-gate`'s confirmation turn. It must never choose an execution mode or trigger `subagent-driven-development`/`executing-plans`.

---

### Task 1: Add and verify `extract_assistant_text`

**Files:**
- Modify: `tests/gate-routing/lib/common.sh`

**Interfaces:**
- Produces: `extract_assistant_text <log_file>` — prints the concatenated assistant text content from a turn's log (tool_use/tool_result blocks excluded). Used by Task 3.

- [ ] **Step 1: Add the helper function**

Append to `tests/gate-routing/lib/common.sh`, after the existing `first_skill_invoked_in` function:

```bash

# Prints the concatenated assistant text content from a turn's log file --
# the model's own words, with tool_use/tool_result blocks excluded. Used
# by suites that judge conversational output rather than a produced file
# (currently only vertical-slices-gate-quality).
extract_assistant_text() {
    local log_file="$1"
    jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$log_file" 2>/dev/null
}
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n tests/gate-routing/lib/common.sh
```

Expected: no output (syntax OK).

- [ ] **Step 3: Verify against a real saved log (no live API calls)**

Use an already-captured turn log from this session's earlier investigation work, which contains real assistant text from a `brainstorming` turn:

```bash
source tests/gate-routing/lib/common.sh
extract_assistant_text /tmp/factory-gates-item17-investigation/trial-1/turn1.json
```

Expected: prints the assistant's actual text response for that turn (readable prose, not JSON) — confirms the helper correctly extracts text content and excludes tool_use/tool_result noise.

- [ ] **Step 4: Commit**

```bash
git add tests/gate-routing/lib/common.sh
git commit -m "feat(tests): add extract_assistant_text helper for conversation-output judging"
```

---

### Task 2: Build the judge library and its unit tests

**Files:**
- Create: `tests/gate-quality/vertical-slices-gate/lib/judge.sh`
- Create: `tests/gate-quality/vertical-slices-gate/test-judge.sh`

**Interfaces:**
- Consumes: `run_judge`, `parse_judge_verdict` from `tests/gate-quality/lib/judge-common.sh` (unchanged).
- Produces: `build_judge_prompt <transcript_text>` — takes the extracted conversation text directly (not a file path, unlike the other two gates' judges), returns the full judge prompt string. Used by Task 3.

- [ ] **Step 1: Create the directory and judge library**

Create `tests/gate-quality/vertical-slices-gate/lib/judge.sh`:

```bash
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
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n tests/gate-quality/vertical-slices-gate/lib/judge.sh
```

Expected: no output.

- [ ] **Step 3: Create the unit tests**

Create `tests/gate-quality/vertical-slices-gate/test-judge.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for lib/judge.sh's build_judge_prompt (vertical-slices-gate's
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

# --- parse_judge_verdict (shared function, vertical-slices-gate's header) ---

cat > "$TMPFILE" <<'EOF'
## Vertical Slices Gate Review

**Status:** Approved

**Issues (if any):**
None.
EOF
assert_eq "Approved status -> pass" "pass" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

cat > "$TMPFILE" <<'EOF'
## Vertical Slices Gate Review

**Status:** Issues Found

**Issues (if any):**
- Coordination risk: plan spans two services but no deploy-order dependency is stated.
EOF
assert_eq "Issues Found status -> fail" "fail" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

cat > "$TMPFILE" <<'EOF'
This is not a real review, just some rambling text with no Status line
and no recognizable structure at all.
EOF
assert_eq "malformed output, no header -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

cat > "$TMPFILE" <<'EOF'
## Vertical Slices Gate Review

I think this looks fine overall.
EOF
assert_eq "header present but no Status line -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

: > "$TMPFILE"
assert_eq "empty file -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

cat > "$TMPFILE" <<'EOF'
## Vertical Slices Gate Review

**Status:** Approved | Issues Found

**Issues (if any):**
- [Category]: [specific issue]
EOF
assert_eq "placeholder Status line -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

cat > "$TMPFILE" <<'EOF'
## Program Design Doc Review

**Status:** Approved
EOF
assert_eq "wrong gate's header -> unparseable (header mismatch)" "unparseable" "$(parse_judge_verdict "$TMPFILE" "Vertical Slices Gate Review")"

# --- build_judge_prompt (vertical-slices-gate's own rubric) ---

TRANSCRIPT="Build order:
1. redirect service -- demoable via curl once deployed
2. admin API -- demoable via POST once deployed

Confirm this order, or would you like to reorder?"

PROMPT_OUTPUT="$(build_judge_prompt "$TRANSCRIPT")"
if printf '%s' "$PROMPT_OUTPUT" | grep -q "## Rubric" && printf '%s' "$PROMPT_OUTPUT" | grep -q "redirect service -- demoable via curl"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: build_judge_prompt embeds both the rubric and the transcript content"
fi

if printf '%s' "$PROMPT_OUTPUT" | grep -q "Vertical Slices Gate Review"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: build_judge_prompt's output format asks for the vertical-slices-gate-specific header"
fi

echo ""
echo "Passed: $PASS, Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
```

- [ ] **Step 4: Run the unit tests**

```bash
chmod +x tests/gate-quality/vertical-slices-gate/test-judge.sh
./tests/gate-quality/vertical-slices-gate/test-judge.sh
```

Expected: `Passed: 9, Failed: 0` (7 `parse_judge_verdict` cases + 2 `build_judge_prompt` checks).

- [ ] **Step 5: Commit**

```bash
git add tests/gate-quality/vertical-slices-gate/lib/judge.sh tests/gate-quality/vertical-slices-gate/test-judge.sh
git commit -m "test(tests): add vertical-slices-gate judge rubric and unit tests"
```

---

### Task 3: Build the trial driver, batch runner, README, and PR

**Files:**
- Create: `tests/gate-quality/vertical-slices-gate/run-trial.sh`
- Create: `tests/gate-quality/vertical-slices-gate/run-all.sh`
- Create: `tests/gate-quality/vertical-slices-gate/README.md`

**Interfaces:**
- Consumes: `resolve_superpowers_dir`, `resolve_factory_gates_dir`, `setup_trial_dir`, `run_turn`, `skill_invoked_in`, `extract_assistant_text` (from `tests/gate-routing/lib/common.sh`); `build_judge_prompt`, `run_judge`, `parse_judge_verdict` (from this suite's `lib/judge.sh`, which itself sources `../../lib/judge-common.sh`).

- [ ] **Step 1: Create `run-trial.sh`**

```bash
#!/usr/bin/env bash
# Run a single vertical-slices-gate quality trial.
# Usage: run-trial.sh <trial-output-dir>
#
# Drives a real brainstorming -> architecture-gate -> program-design-gate
# -> writing-plans -> vertical-slices-gate conversation on a toy
# URL-shortener feature, extracts the assistant's text from the turn
# vertical-slices-gate fires in, and scores it with a headless LLM judge
# against the rubric in
# docs/superpowers/specs/2026-08-15-vertical-slices-gate-quality-tests-design.md.

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

FEATURE_REQUEST="I want to build a small URL shortener, implemented in Python using only the standard library. Two components: a public redirect service that takes a short code and 302-redirects to the original URL, and an admin API for creating new short links (POST with a target URL, returns a short code). Both read/write the same data store (short code -> target URL mapping). Redirect latency matters -- it's on the hot path for every click. No user accounts, no analytics, no custom short codes (always generated). That's the complete design -- no open questions on my end."

TURNS=(
    "$FEATURE_REQUEST"
    "That approach looks good -- please continue."
    "Approved. Please write the spec and commit it."
    "I've reviewed the spec, it looks good, please proceed."
    "That architecture approach looks good -- please continue."
    "Approved. Please write the architecture doc."
    "I've reviewed the architecture doc, it looks good, please proceed."
    "Approved. Please write the program design doc."
    "I've reviewed the program design doc, it looks good, please proceed."
    "Approved. Please write the implementation plan."
    "I've reviewed the plan, it looks good."
    "Confirmed, that build order looks right."
)

BRAINSTORMING_TRIGGERED=false
ARCHITECTURE_GATE_TRIGGERED=false
PROGRAM_DESIGN_GATE_TRIGGERED=false
VERTICAL_SLICES_GATE_TRIGGERED=false
VERTICAL_SLICES_GATE_TURN=0
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
    if [ "$VERTICAL_SLICES_GATE_TRIGGERED" = "false" ] && skill_invoked_in "$LOG_FILE" "vertical-slices-gate"; then
        VERTICAL_SLICES_GATE_TRIGGERED=true
        VERTICAL_SLICES_GATE_TURN=$TURN_NUM
    fi
done

TRANSCRIPT=""
if [ "$VERTICAL_SLICES_GATE_TRIGGERED" = "true" ]; then
    TRANSCRIPT="$(extract_assistant_text "$TRIAL_DIR/turn${VERTICAL_SLICES_GATE_TURN}.json")"
fi

OUTCOME="inconclusive"
JUDGE_OUTPUT_FILE=""

if [ "$VERTICAL_SLICES_GATE_TRIGGERED" = "true" ] && [ -n "$TRANSCRIPT" ]; then
    JUDGE_OUTPUT_FILE="$TRIAL_DIR/judge-output.txt"
    JUDGE_PROMPT="$(build_judge_prompt "$TRANSCRIPT")"
    run_judge "$JUDGE_PROMPT" "$JUDGE_OUTPUT_FILE"
    VERDICT="$(parse_judge_verdict "$JUDGE_OUTPUT_FILE" "Vertical Slices Gate Review")"
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
  "vertical_slices_gate_triggered": $VERTICAL_SLICES_GATE_TRIGGERED,
  "vertical_slices_gate_turn": $VERTICAL_SLICES_GATE_TURN,
  "judge_output_file": "${JUDGE_OUTPUT_FILE:-}",
  "turns_used": $TURNS_USED,
  "outcome": "$OUTCOME"
}
EOF

echo "Trial complete: outcome=$OUTCOME turns_used=$TURNS_USED vertical_slices_gate_triggered=$VERTICAL_SLICES_GATE_TRIGGERED"
echo "Result: $TRIAL_DIR/result.json"

if [ "$OUTCOME" = "pass" ]; then
    exit 0
else
    exit 1
fi
```

- [ ] **Step 2: Verify syntax and make executable**

```bash
chmod +x tests/gate-quality/vertical-slices-gate/run-trial.sh
bash -n tests/gate-quality/vertical-slices-gate/run-trial.sh
```

Expected: no output.

- [ ] **Step 3: Create `run-all.sh`**

```bash
#!/usr/bin/env bash
# Run the full vertical-slices-gate quality trial batch and report
# pass/fail/inconclusive rates.
#
# Usage: run-all.sh [--trials N]
#   --trials N   Number of trials (default: 2 -- this is the longest,
#                most expensive suite; see README for why)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TRIALS=2

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

echo "=== Vertical-Slices-Gate Quality Test Run ==="
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
    echo "NOTE: $FAIL_COUNT trial(s) had the judge find issues in the vertical-slices-gate confirmation turn. Check judge_output_file in each trial's result.json for details."
    exit 1
fi
```

- [ ] **Step 4: Verify syntax and make executable**

```bash
chmod +x tests/gate-quality/vertical-slices-gate/run-all.sh
bash -n tests/gate-quality/vertical-slices-gate/run-all.sh
```

Expected: no output.

- [ ] **Step 5: Create `README.md`**

```markdown
# Vertical Slices Gate Quality Tests

Judges the *content quality* of the conversation turn `vertical-slices-gate`
produces, not whether the skill gets invoked (that's `tests/gate-routing/`'s
job -- though this suite's much longer trial chain means routing
non-determinism compounds here more than anywhere else). Unlike
`architecture-gate` and `program-design-gate`, this skill produces no
persisted document -- its entire output is a conversation turn summarizing
build order and asking for confirmation. Drives a real `brainstorming` ->
`architecture-gate` -> `program-design-gate` -> `writing-plans` ->
`vertical-slices-gate` conversation on the same toy URL-shortener feature
used by the other two suites, extracts the assistant's text from the turn
`vertical-slices-gate` fires in, and scores it against a rubric derived
from the skill's own checklist, using the shared headless LLM judge in
`../lib/judge-common.sh`.

## How it works

1. A real `claude -p` conversation (both `superpowers` and `factory-gates`
   loaded) walks through a 12-turn script -- the full 9 turns from
   `../program-design-gate/`'s suite through program-design-doc approval,
   plus 3 more turns for `writing-plans` saving a plan and
   `vertical-slices-gate`'s own confirmation exchange.
2. The assistant's text is extracted from whichever turn
   `vertical-slices-gate` first fires in (there's no file to locate --
   see the design spec at
   `docs/superpowers/specs/2026-08-15-vertical-slices-gate-quality-tests-design.md`
   for why).
3. A **second, separate, sandboxed** `claude -p` call (see
   `../lib/judge-common.sh`) is given that excerpt plus this gate's
   rubric and asked to return `Approved` or `Issues Found` with itemized
   findings.

## Running

\`\`\`bash
# Default batch (2 trials, likely 30-50+ minutes total, real token cost --
# this is the longest suite yet, 12 turns/trial)
./run-all.sh

# Cheap single-trial spot check while iterating on the harness itself
./run-all.sh --trials 1
\`\`\`

Requires: `claude` CLI installed and authenticated, `jq`, and the
Superpowers plugin installed locally (see `../../gate-routing/README.md`
for the same prerequisites and `SUPERPOWERS_PLUGIN_DIR` override).

Unit tests for the judge's parsing/templating logic (fast, no live
calls):

\`\`\`bash
./test-judge.sh
\`\`\`

## Reading the output

Same three-way outcome split as the other suites:

- **pass** — the judge reviewed the confirmation turn and returned `Approved`
- **fail** — the judge reviewed it and returned `Issues Found` -- check
  that trial's `judge_output_file` (path is in its `result.json`)
- **inconclusive** — `vertical-slices-gate` never triggered within the
  12-turn script -- check `result.json`'s `*_triggered` fields to see how
  far the conversation actually got before concluding this is a
  quality-suite bug rather than routing non-determinism (compounded here
  across four gate handoffs, not just one)

## Known limitations

Same as `../program-design-gate/README.md`'s (non-determinism on two
axes, not run in CI, single toy feature) -- additionally:

- **Judge sees only the first turn `vertical-slices-gate` fires in**, not
  any back-and-forth refinement afterward -- the conversational
  equivalent of the doc-review suites only seeing the final document, not
  the process that produced it.
- **Longest, most expensive suite.** Four gate handoffs have to succeed
  in sequence for a trial to reach `vertical-slices-gate` at all, so
  expect the highest `inconclusive` rate of the three suites. Default
  trial count is 2, not 3, given the real cost of a 12-turn trial.
- **Does not exercise actual execution.** The script stops right after
  `vertical-slices-gate`'s confirmation turn -- it never chooses
  `subagent-driven-development` or `executing-plans`, since triggering
  real implementation work is out of scope for a quality check on the
  confirmation turn itself.
```

- [ ] **Step 6: Verify no unintended drift**

```bash
grep -c "extract_assistant_text" tests/gate-quality/vertical-slices-gate/run-trial.sh
grep -c "Vertical Slices Gate Review" tests/gate-quality/vertical-slices-gate/lib/judge.sh
grep -c "TRIALS=2" tests/gate-quality/vertical-slices-gate/run-all.sh
```

Expected: at least 1 for each.

- [ ] **Step 7: Commit**

```bash
git add tests/gate-quality/vertical-slices-gate/run-trial.sh tests/gate-quality/vertical-slices-gate/run-all.sh tests/gate-quality/vertical-slices-gate/README.md
git commit -m "test(tests): add vertical-slices-gate quality suite driver, runner, and docs"
```

- [ ] **Step 8: Live verification run**

```bash
cd tests/gate-quality/vertical-slices-gate
./run-all.sh --trials 1
cd -
```

This is a single, cheap spot-check (not the full default 2-trial batch) to confirm the suite works end-to-end for real before opening the PR: the 12-turn conversation completes, `vertical_slices_gate_triggered` and `vertical_slices_gate_turn` populate correctly if the skill fires, `extract_assistant_text` produces real text (not empty), the judge call completes, and `result.json` has a valid `outcome`. If `vertical-slices-gate` doesn't trigger within the script, that's a legitimate `inconclusive` result (routing non-determinism, not a suite bug) — check the `*_triggered` fields in `result.json` to see how far the conversation got before concluding anything is broken.

- [ ] **Step 9: Push, open PR**

```bash
git push -u origin test/vertical-slices-gate-quality-suite
```

Open the PR with `gh pr create`, following this repo's established template (see PR #8, the `program-design-gate` suite's PR, for the closest-matching structure): who's submitting, what problem (no quality suite existed for the last gate, and it needed a genuinely different design since it produces no document), what changed, which gate (`vertical-slices-gate`), alternatives considered (judging the conversation excerpt vs. waiting for some other artifact — there is none), existing-PRs checkbox noting this completes the quality-suite trio started by architecture-gate's and program-design-gate's, rigor section citing the unit test results and the live spot-check's actual outcome, human-review checkbox unchecked.

- [ ] **Step 10: Report to human partner**

Show the complete diff (`git diff main...test/vertical-slices-gate-quality-suite`) and the PR URL. Per standing instruction, do not merge.

## Self-Review

1. **Spec coverage:** Task 1 covers the shared helper; Task 2 covers the judge rubric and its unit tests; Task 3 covers the trial driver, batch runner, README, live spot-check, and PR. Every section of the design spec has a corresponding task.
2. **Placeholder scan:** none — every file's full content is given verbatim in the relevant step, matching the "no placeholders" rule the same way every prior plan in this repo has.
3. **Type consistency:** `extract_assistant_text` is referenced identically in Task 1's definition and Task 3's `run-trial.sh` usage. `build_judge_prompt`'s signature (`transcript_text`, not `doc_path`) is consistent between Task 2's definition and Task 3's call site. `VERTICAL_SLICES_GATE_TRIGGERED`/`VERTICAL_SLICES_GATE_TURN` naming matches across the tracking variables and the `result.json` field names.
