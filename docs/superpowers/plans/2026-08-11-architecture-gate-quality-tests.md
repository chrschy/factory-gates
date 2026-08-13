# Architecture Gate Quality Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A test harness that drives `architecture-gate` through a toy URL-shortener feature end-to-end and scores the resulting architecture document with a headless LLM judge against a rubric derived from the skill's own checklist/template.

**Architecture:** Reuses `tests/gate-routing/lib/common.sh` for plugin-dir resolution, isolated project setup, and turn-running (no duplication of already-reviewed plumbing). Adds one new library, `lib/judge.sh`, split into a pure, fast-unit-testable verdict parser (`parse_judge_verdict`) and a prompt builder (`build_judge_prompt`), plus the one live-call function (`run_judge`) that can't be unit tested without a real `claude -p` invocation. `run-trial.sh` drives one 7-turn conversation and produces a `result.json` verdict; `run-all.sh` orchestrates N trials and aggregates via `jq`, including the missing-`result.json` robustness fix already learned the hard way in `tests/gate-routing/`'s own history.

**Tech Stack:** bash, jq, the `claude` CLI — no new runtime dependency, consistent with `tests/gate-routing/` and `.github/scripts/`.

## Global Constraints

- Toy feature: a URL shortener with two components (public redirect service, admin API for creating links) sharing a data store, redirect latency called out as a constraint. Full spec given in turn 1, no clarifying-question turns expected.
- 7-turn conversation script (see Task 2) drives both `brainstorming` and all of `architecture-gate`'s checklist to the final user-review-gate approval.
- Judge is a **separate, headless `claude -p` call**, no `--plugin-dir`, given the architecture doc content plus the rubric as the prompt. Output parsed for `**Status:** Approved` / `**Status:** Issues Found`.
- Outcome classification per trial: **pass** (judge says Approved), **fail** (judge says Issues Found), **inconclusive** (no architecture doc was ever produced, `architecture-gate` never triggered, or the judge's own output couldn't be parsed — a harness/environment signal, not a quality signal).
- File layout: `tests/gate-quality/architecture-gate/{README.md,run-trial.sh,run-all.sh,test-judge.sh,lib/judge.sh}` — nested under `tests/gate-quality/` so sibling gates' quality suites can be added later without restructuring.
- Default trial count: 3, overridable via `run-all.sh --trials N`, matching `tests/gate-routing/run-all.sh`'s existing flag convention.
- No CI integration (same reasoning as `tests/gate-routing/`: real tokens, real time).
- Every `run-all.sh`-style orchestrator in this repo now defensively skips trials with a missing `result.json` rather than crashing the whole aggregation (the bug found and fixed in `tests/gate-routing/run-all.sh`'s own history) — bake this in from the start here, don't wait for a reviewer to find it again.

## File Structure

```
tests/gate-quality/
  architecture-gate/
    README.md          — what's tested, why, how to run/read it, cost/limitations
    run-trial.sh         — drives one trial's conversation, locates the doc, invokes the judge
    run-all.sh            — orchestrates N trials, aggregates via jq
    test-judge.sh          — unit tests for lib/judge.sh's parse_judge_verdict and build_judge_prompt
    lib/
      judge.sh              — build_judge_prompt, run_judge, parse_judge_verdict
```

---

### Task 1: Judge library + unit tests

**Files:**
- Create: `tests/gate-quality/architecture-gate/test-judge.sh`
- Create: `tests/gate-quality/architecture-gate/lib/judge.sh`

**Interfaces:**
- Produces (consumed by Task 2's `run-trial.sh`): `build_judge_prompt(doc_path) -> prompt text on stdout`, `run_judge(doc_path, output_file)` — writes the judge's raw response to `output_file`, `parse_judge_verdict(output_file) -> "pass"|"fail"|"unparseable"`

- [ ] **Step 1: Create the branch**

```bash
cd /home/christopher/PycharmProjects/factory-gates
git checkout main
git pull
git checkout -b test/architecture-gate-quality
mkdir -p tests/gate-quality/architecture-gate/lib
```

- [ ] **Step 2: Write the failing tests — `tests/gate-quality/architecture-gate/test-judge.sh`**

```bash
#!/usr/bin/env bash
# Unit tests for lib/judge.sh's parse_judge_verdict and build_judge_prompt.
# Pure text parsing/templating, no live claude -p calls -- fast and
# deterministic. Usage: ./test-judge.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/judge.sh
source "$SCRIPT_DIR/lib/judge.sh"

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

# --- parse_judge_verdict ---

cat > "$TMPFILE" <<'EOF'
## Architecture Doc Review

**Status:** Approved

**Issues (if any):**
None.
EOF
assert_eq "Approved status -> pass" "pass" "$(parse_judge_verdict "$TMPFILE")"

cat > "$TMPFILE" <<'EOF'
## Architecture Doc Review

**Status:** Issues Found

**Issues (if any):**
- Component boundaries: the "data store" is never named as its own component -- unclear if it's owned by one of the two services or a third thing.
EOF
assert_eq "Issues Found status -> fail" "fail" "$(parse_judge_verdict "$TMPFILE")"

cat > "$TMPFILE" <<'EOF'
This is not a real review, just some rambling text with no Status line
and no recognizable structure at all.
EOF
assert_eq "malformed output, no header -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE")"

cat > "$TMPFILE" <<'EOF'
## Architecture Doc Review

I think this looks fine overall.
EOF
assert_eq "header present but no Status line -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE")"

: > "$TMPFILE"
assert_eq "empty file -> unparseable" "unparseable" "$(parse_judge_verdict "$TMPFILE")"

# --- build_judge_prompt ---

cat > "$TMPFILE" <<'EOF'
# My Feature -- Architecture

## Components
- Foo -- does foo things
EOF
PROMPT_OUTPUT="$(build_judge_prompt "$TMPFILE")"
if printf '%s' "$PROMPT_OUTPUT" | grep -q "## Rubric" && printf '%s' "$PROMPT_OUTPUT" | grep -q "Foo -- does foo things"; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: build_judge_prompt embeds both the rubric and the document content"
fi

echo ""
echo "Passed: $PASS, Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
```

- [ ] **Step 3: Run the tests, verify they fail**

```bash
chmod +x tests/gate-quality/architecture-gate/test-judge.sh
tests/gate-quality/architecture-gate/test-judge.sh
```

Expected: FAIL — `source: .../lib/judge.sh: No such file or directory` (the library doesn't exist yet).

- [ ] **Step 4: Write the minimal implementation — `tests/gate-quality/architecture-gate/lib/judge.sh`**

```bash
#!/usr/bin/env bash
# Headless LLM-judge for architecture-gate's output document quality.
# No plugins needed -- the judge only reads and reasons over the document,
# it doesn't need any skill loaded.

set -euo pipefail

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

# Run the judge against a document, writing its raw response to output_file.
# Usage: run_judge <doc_path> <output_file>
run_judge() {
    local doc_path="$1"
    local output_file="$2"
    local prompt
    prompt="$(build_judge_prompt "$doc_path")"
    timeout 120 claude -p "$prompt" --dangerously-skip-permissions > "$output_file" 2>&1 || true
}

# Parse a judge output file into "pass", "fail", or "unparseable".
# Usage: parse_judge_verdict <output_file>
parse_judge_verdict() {
    local output_file="$1"
    if ! grep -q "Architecture Doc Review" "$output_file" 2>/dev/null; then
        echo "unparseable"
        return
    fi
    if grep -qE '\*\*Status:\*\*[[:space:]]*Approved' "$output_file" 2>/dev/null; then
        echo "pass"
    elif grep -qE '\*\*Status:\*\*[[:space:]]*Issues Found' "$output_file" 2>/dev/null; then
        echo "fail"
    else
        echo "unparseable"
    fi
}
```

- [ ] **Step 5: Run the tests again, verify they pass**

```bash
chmod +x tests/gate-quality/architecture-gate/lib/judge.sh
tests/gate-quality/architecture-gate/test-judge.sh
```

Expected: `Passed: <N>, Failed: 0`, exit code 0. If any FAIL lines print, fix `judge.sh` (not the test) and re-run until clean.

- [ ] **Step 6: Commit**

```bash
git add tests/gate-quality/architecture-gate/test-judge.sh tests/gate-quality/architecture-gate/lib/judge.sh
git commit -m "test(tests): add architecture-gate quality judge library with unit tests"
```

---

### Task 2: Single-trial driver

**Files:**
- Create: `tests/gate-quality/architecture-gate/run-trial.sh`

**Interfaces:**
- Consumes: `resolve_superpowers_dir`, `resolve_factory_gates_dir`, `setup_trial_dir`, `run_turn`, `skill_invoked_in` from `tests/gate-routing/lib/common.sh`; `run_judge`, `parse_judge_verdict` from Task 1's `lib/judge.sh`
- Produces: `<trial-dir>/result.json` with fields `trial_dir`, `brainstorming_triggered`, `architecture_gate_triggered`, `doc_found`, `doc_path`, `judge_output_file`, `turns_used`, `outcome` (`pass`|`fail`|`inconclusive`) — consumed by Task 3's `run-all.sh`

- [ ] **Step 1: Write `tests/gate-quality/architecture-gate/run-trial.sh`**

```bash
#!/usr/bin/env bash
# Run a single architecture-gate quality trial.
# Usage: run-trial.sh <trial-output-dir>
#
# Drives a real brainstorming -> architecture-gate conversation on a toy
# URL-shortener feature, locates the produced architecture doc, and scores
# it with a headless LLM judge against the rubric in
# docs/superpowers/specs/2026-08-11-architecture-gate-quality-tests-design.md.

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
    "I've reviewed the architecture doc, it looks good."
)

BRAINSTORMING_TRIGGERED=false
ARCHITECTURE_GATE_TRIGGERED=false
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
done

DOC_PATH="$(find "$PROJECT_DIR/docs/superpowers/specs" -name '*-architecture.md' -print -quit 2>/dev/null || true)"

DOC_FOUND=false
if [ -n "$DOC_PATH" ]; then
    DOC_FOUND=true
fi

OUTCOME="inconclusive"
JUDGE_OUTPUT_FILE=""

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

cat > "$TRIAL_DIR/result.json" <<EOF
{
  "trial_dir": "$TRIAL_DIR",
  "brainstorming_triggered": $BRAINSTORMING_TRIGGERED,
  "architecture_gate_triggered": $ARCHITECTURE_GATE_TRIGGERED,
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
chmod +x tests/gate-quality/architecture-gate/run-trial.sh
bash -n tests/gate-quality/architecture-gate/run-trial.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Smoke-test one real trial**

```bash
tests/gate-quality/architecture-gate/run-trial.sh /tmp/factory-gates-arch-quality-smoke-test
cat /tmp/factory-gates-arch-quality-smoke-test/result.json
```

Expected: takes several minutes (7 real conversation turns plus one judge call) and real token cost. Any of the three outcomes (`pass`, `fail`, `inconclusive`) is an acceptable smoke-test result — this step verifies the harness runs end-to-end and produces a well-formed verdict, not that the verdict is `pass`. If `doc_found` is `false`, read `turn1.json` through `turn7.json` in the trial directory to see what actually happened (e.g. did `architecture-gate` trigger at all — cross-check with `tests/gate-routing/`'s own findings on how reliably that handoff fires) before concluding there's a bug in this new harness specifically. If the script errors out before producing `result.json` at all, that actual failure needs to be fixed.

- [ ] **Step 4: Commit**

```bash
git add tests/gate-quality/architecture-gate/run-trial.sh
git commit -m "test(tests): add architecture-gate quality single-trial driver"
```

---

### Task 3: Trial batch orchestrator

**Files:**
- Create: `tests/gate-quality/architecture-gate/run-all.sh`

**Interfaces:**
- Consumes: `tests/gate-quality/architecture-gate/run-trial.sh` from Task 2 (invoked as a subprocess)
- Produces: a printed pass/fail/inconclusive table, and `<run-dir>/summary.json`

- [ ] **Step 1: Write `tests/gate-quality/architecture-gate/run-all.sh`**

```bash
#!/usr/bin/env bash
# Run the full architecture-gate quality trial batch and report pass/fail/
# inconclusive rates.
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

echo "=== Architecture-Gate Quality Test Run ==="
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
    echo "NOTE: $FAIL_COUNT trial(s) had the judge find issues in the architecture doc. Check judge_output_file in each trial's result.json for details."
    exit 1
fi
```

- [ ] **Step 2: Verify syntax**

```bash
chmod +x tests/gate-quality/architecture-gate/run-all.sh
bash -n tests/gate-quality/architecture-gate/run-all.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Smoke-test with a single trial**

```bash
tests/gate-quality/architecture-gate/run-all.sh --trials 1
```

Expected: prints the run header, one `>>> Running trial 1...` line, then a `=== Summary ===` JSON object (`trials: 1`, `pass`/`fail`/`inconclusive` summing to 1).

- [ ] **Step 4: Commit**

```bash
git add tests/gate-quality/architecture-gate/run-all.sh
git commit -m "test(tests): add architecture-gate quality trial batch orchestrator"
```

---

### Task 4: Documentation

**Files:**
- Create: `tests/gate-quality/architecture-gate/README.md`

**Interfaces:** none (describes Tasks 1-3's scripts)

- [ ] **Step 1: Write `tests/gate-quality/architecture-gate/README.md`**

```markdown
# Architecture Gate Quality Tests

Judges the *content quality* of the document `architecture-gate` produces,
not whether the skill gets invoked (that's `tests/gate-routing/`'s job).
Drives a real `brainstorming` -> `architecture-gate` conversation on a toy
URL-shortener feature, then scores the resulting architecture document
against a rubric derived from `architecture-gate`'s own checklist and
template, using a separate headless LLM judge.

Scope is deliberately narrow: one gate (`architecture-gate`, the most
novel of the three), one toy feature, document quality only. Nested under
`tests/gate-quality/` so `program-design-gate`/`vertical-slices-gate`
quality suites can be added later as siblings.

## How it works

1. A real `claude -p` conversation (both `superpowers` and `factory-gates`
   loaded) walks through a 7-turn script: the toy feature request,
   approving `brainstorming`'s approach, approving and writing the spec,
   handing off into `architecture-gate`, approving its proposed approach,
   writing the architecture doc, and a final approval.
2. The produced `docs/superpowers/specs/*-architecture.md` file is located
   in the trial's isolated project directory.
3. A **second, separate, headless** `claude -p` call (no plugins) is given
   the document plus the rubric and asked to return `Approved` or
   `Issues Found` with itemized findings.

## Running

```bash
# Default batch (3 trials, likely 15-30+ minutes total, real token cost --
# each trial is a much longer conversation than tests/gate-routing/'s)
./run-all.sh

# Cheap single-trial spot check while iterating on the harness itself
./run-all.sh --trials 1
```

Requires: `claude` CLI installed and authenticated, `jq`, and the
Superpowers plugin installed locally (see `tests/gate-routing/README.md`
for the same prerequisites and `SUPERPOWERS_PLUGIN_DIR` override).

Unit tests for the judge's parsing logic (fast, no live calls):

```bash
./test-judge.sh
```

## Reading the output

`run-all.sh` prints a summary like:

```json
{ "trials": 3, "pass": 2, "fail": 0, "inconclusive": 1 }
```

- **pass** — the judge reviewed the doc and returned `Approved`
- **fail** — the judge reviewed the doc and returned `Issues Found` — check
  that trial's `judge_output_file` (path is in its `result.json`) for the
  itemized issues
- **inconclusive** — no architecture doc was ever produced within the
  7-turn script (`architecture-gate` may not have triggered -- cross-check
  against `tests/gate-routing/`'s findings on that handoff), or the
  judge's own response couldn't be parsed. Not a document-quality signal.

## Known limitations

- **Non-deterministic on two axes**, not one: both the conversation being
  judged and the judge's own verdict are LLM outputs. A `fail` might mean
  the architecture doc was genuinely weak, or it might mean the judge was
  overly strict on this run -- read `judge_output_file` before concluding
  either way, and don't trust a single trial's verdict in isolation.
- **Judge and subject share no state** -- the judge only sees the final
  document, not the conversation that produced it, so it can't tell
  whether a thin section reflects a genuinely simple feature or a skipped
  step.
- **Not run in CI** -- same reasoning as `tests/gate-routing/`: real
  tokens, real time, meant as a manual/occasional diagnostic.
- **Single toy feature.** A URL shortener exercises component boundaries
  and cross-boundary data, but won't surface every failure mode (e.g.
  multi-repo coordination, which the toy feature never triggers).
```

- [ ] **Step 2: Verify**

```bash
grep -c "^## " tests/gate-quality/architecture-gate/README.md
```

Expected: 4.

- [ ] **Step 3: Commit**

```bash
git add tests/gate-quality/architecture-gate/README.md
git commit -m "docs(tests): document architecture-gate quality test suite"
```

---

### Task 5: Run the full batch and report results

**Files:** none

**Interfaces:**
- Consumes: `run-all.sh` from Task 3

- [ ] **Step 1: Run the full default batch**

```bash
cd /home/christopher/PycharmProjects/factory-gates
tests/gate-quality/architecture-gate/run-all.sh
```

Expected: likely 15-30+ minutes given 3 trials at ~7 turns each plus judge calls. Ends with the `=== Summary ===` JSON.

- [ ] **Step 2: Report to human partner**

Paste the summary into the conversation with your human partner, along with the location of `summary.json`. For any `fail` trial, paste the relevant `judge_output_file` contents so they can see the actual issues raised, not just the count. For any `inconclusive` trial, note whether `brainstorming_triggered`/`architecture_gate_triggered` point at a routing problem (cross-reference `tests/gate-routing/`) versus the doc simply not appearing for another reason. Do not editorialize about whether the result is "good" or "bad" beyond stating the numbers and the actual issues found — let your human partner judge whether `architecture-gate`'s wording needs work.

---

### Task 6: Open PR, review, merge

**Files:** none

**Interfaces:**
- Consumes: all commits from Tasks 1-4 on `test/architecture-gate-quality`; Task 5's results to paste into the PR body

- [ ] **Step 1: Push the branch**

```bash
git push -u origin test/architecture-gate-quality
```

- [ ] **Step 2: Open the PR**

Fill in the `<PASTE ...>` placeholder with Task 5's actual summary before running this command — do not open the PR with it still literal.

```bash
gh pr create --title "test(tests): add architecture-gate quality test suite" --body "$(cat <<'EOF'
## Who is submitting this PR? (required)

| Field | Value |
|-------|-------|
| Your model + version | Claude Sonnet 5 |
| Harness + version | Claude Code |
| All plugins installed | superpowers |
| Human partner who reviewed this diff | [@chrschy](https://github.com/chrschy) |

## What problem are you trying to solve?

None of the three gate skills in this plugin had been exercised or judged
since the original scaffold. tests/gate-routing/ only tests whether
architecture-gate gets invoked, not whether the document it produces is
any good.

## What does this PR change?

Adds tests/gate-quality/architecture-gate/ -- drives architecture-gate
through a toy URL-shortener feature and scores the resulting document with
a headless LLM judge against a rubric derived from the skill's own
checklist. Reuses tests/gate-routing/lib/common.sh for shared plumbing.

## Which gate does this touch?

architecture-gate (measurement only, no wording changed in this PR).

## What alternatives did you consider?

Considered testing the full 4-gate pipeline end-to-end, but scoped down to
one gate first per discussion -- output-quality judging is a different,
pricier kind of test than routing, worth proving out narrow before
expanding to program-design-gate and vertical-slices-gate.

## Existing PRs
- [x] I have reviewed open AND closed PRs/issues for duplicates or prior art
- Related PRs/issues: none found

## Rigor
- [x] This change was tested adversarially, not just on the happy path
- [x] Unit tests: test-judge.sh, all passing
- [x] Ran tests/gate-quality/architecture-gate/run-all.sh -- results:

<PASTE Task 5's summary.json and any fail/inconclusive details here>

## Human review
- [ ] A human has reviewed the COMPLETE proposed diff before submission
EOF
)"
```

- [ ] **Step 3: Human review gate**

Stop here. Show the human partner the complete diff (`git diff main...test/architecture-gate-quality`), the PR URL, and Task 5's results. Do not proceed to Step 4 until they explicitly approve.

- [ ] **Step 4: Merge**

```bash
gh pr merge --squash --delete-branch --admin
```

- [ ] **Step 5: Verify**

```bash
git checkout main
git pull
ls tests/gate-quality/architecture-gate/
```

Expected: `README.md`, `lib/`, `run-all.sh`, `run-trial.sh`, `test-judge.sh` all present on `main`.

## Self-Review

1. **Spec coverage:** judge library + unit tests (Task 1), single-trial driver with the 7-turn script and three-way outcome classification (Task 2), batch orchestrator with the missing-`result.json` robustness fix applied proactively (Task 3), documentation (Task 4), a real batch run with results reported (Task 5), PR/merge flow (Task 6). CI integration and the other two gates' quality suites are explicitly out of scope per the spec.
2. **Placeholder scan:** one intentional, explicitly-flagged placeholder in Task 6 Step 2 (`<PASTE Task 5's summary.json and any fail/inconclusive details here>`), same pattern as every prior plan in this repo — must be filled from real output before opening the PR.
3. **Type consistency:** `judge.sh`'s three function names (`build_judge_prompt`, `run_judge`, `parse_judge_verdict`) are identical across Task 1's test file, Task 1's implementation, and Task 2's `run-trial.sh` consumption of them. `result.json`'s field names in Task 2 match what Task 3's `jq` aggregation and Task 4's README both describe (`outcome` as `pass`/`fail`/`inconclusive`, consistently).
