# Gate-Routing Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an empirical test harness that drives real `claude -p` sessions through a brainstorming conversation (both `superpowers` and `factory-gates` plugins loaded) to determine whether `architecture-gate` actually wins the routing conflict against `brainstorming`'s hard "invoke writing-plans only" instruction — bare, and with the README's documented explicit-instruction workaround.

**Architecture:** Bash + jq, no new runtime dependency. `lib/common.sh` resolves plugin directories and provides Skill-detection helpers; `run-trial.sh` drives one 4-turn conversation for one scenario and writes a `result.json` verdict; `run-all.sh` orchestrates the 2×3 trial matrix and aggregates results via `jq`. Mirrors the pattern in Superpowers' own `tests/explicit-skill-requests/`.

**Tech Stack:** bash, jq, the `claude` CLI (`--plugin-dir`, `--continue`, `--output-format stream-json`), `gh` (repo already exists, no `gh` calls needed in this plan).

## Global Constraints

- Depends on Task 1-5 of `docs/superpowers/plans/2026-08-10-repo-governance-tooling.md` having merged first (CLAUDE.md references `tests/gate-routing/run-all.sh` by path; keep the reference valid) — if that plan hasn't merged yet, this plan still works standalone, just merge order matters for a clean history.
- Branch: `test/gate-routing-handoff`, per the branch-naming convention (`test/` prefix, scope in the slug).
- All 3 shell scripts must be executable (`chmod +x`).
- No CI integration — these tests cost real tokens and require a locally-authenticated `claude` CLI; documented as a manual/occasional diagnostic, not a required check.
- Superpowers plugin is expected at `~/.claude/plugins/cache/claude-plugins-official/superpowers/<version>/` (already installed in this environment, confirmed version `6.2.0`); overridable via `SUPERPOWERS_PLUGIN_DIR`.

---

### Task 1: Branch + shared helpers (`lib/common.sh`)

**Files:**
- Create: `tests/gate-routing/lib/common.sh`

**Interfaces:**
- Produces (consumed by Tasks 2 and 3):
  - `resolve_superpowers_dir()` → prints the Superpowers plugin dir path
  - `resolve_factory_gates_dir()` → prints this repo's root path
  - `setup_trial_dir(base_dir)` → creates and prints an isolated project dir
  - `run_turn(project_dir, prompt, do_continue, superpowers_dir, factory_gates_dir, log_file)` → runs one `claude -p` turn, writes `log_file`
  - `skill_invoked_in(log_file, skill_name)` → returns success (exit 0) if that skill's `Skill` tool invocation appears in the log

- [ ] **Step 1: Create the branch**

```bash
cd /home/christopher/PycharmProjects/factory-gates
git checkout main
git pull
git checkout -b test/gate-routing-handoff
mkdir -p tests/gate-routing/lib
```

- [ ] **Step 2: Write `tests/gate-routing/lib/common.sh`**

```bash
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

    find "$cache_root" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1
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
            "${continue_flag[@]}" \
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
```

- [ ] **Step 3: Verify it's syntactically valid**

```bash
bash -n tests/gate-routing/lib/common.sh
```

Expected: no output, exit code 0.

- [ ] **Step 4: Commit**

```bash
chmod +x tests/gate-routing/lib/common.sh
git add tests/gate-routing/lib/common.sh
git commit -m "test(tests): add shared helpers for gate-routing trials"
```

---

### Task 2: Single-trial driver (`run-trial.sh`)

**Files:**
- Create: `tests/gate-routing/run-trial.sh`

**Interfaces:**
- Consumes: `resolve_superpowers_dir`, `resolve_factory_gates_dir`, `setup_trial_dir`, `run_turn`, `skill_invoked_in` from Task 1's `lib/common.sh`
- Produces: `<trial-dir>/result.json` with fields `scenario`, `trial_dir`, `brainstorming_triggered`, `architecture_gate_triggered`, `architecture_gate_turn`, `writing_plans_before_architecture`, `turns_used`, `outcome` (`pass`|`fail`|`inconclusive`) — consumed by Task 3's `run-all.sh`

- [ ] **Step 1: Write `tests/gate-routing/run-trial.sh`**

```bash
#!/usr/bin/env bash
# Run a single gate-routing trial.
# Usage: run-trial.sh <bare|explicit> <trial-output-dir>
#
# Drives a real brainstorming conversation (Superpowers + factory-gates
# both loaded) through to the brainstorming -> architecture-gate handoff
# point, and records which skill actually fires: architecture-gate
# (pass), writing-plans directly (fail), or neither (inconclusive).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SCENARIO="${1:-}"
TRIAL_DIR="${2:-}"

if [ -z "$SCENARIO" ] || [ -z "$TRIAL_DIR" ]; then
    echo "Usage: $0 <bare|explicit> <trial-output-dir>" >&2
    exit 1
fi

if [ "$SCENARIO" != "bare" ] && [ "$SCENARIO" != "explicit" ]; then
    echo "ERROR: scenario must be 'bare' or 'explicit', got '$SCENARIO'" >&2
    exit 1
fi

SUPERPOWERS_DIR="$(resolve_superpowers_dir)"
FACTORY_GATES_DIR="$(resolve_factory_gates_dir)"

mkdir -p "$TRIAL_DIR"
PROJECT_DIR="$(setup_trial_dir "$TRIAL_DIR")"

FEATURE_REQUEST="I want to build a small in-memory rate limiter for an API. Single component: a RateLimiter class with a check(key) method, fixed-window algorithm, 100 requests per 60 seconds, no persistence, no external dependencies, single file. That's the complete design -- no open questions on my end."

if [ "$SCENARIO" = "explicit" ]; then
    TURN1_PROMPT="Use the factory-gates workflow for this. $FEATURE_REQUEST"
else
    TURN1_PROMPT="$FEATURE_REQUEST"
fi

TURNS=(
    "$TURN1_PROMPT"
    "Yes, that approach looks good -- please continue."
    "Approved. Please write the spec and commit it."
    "I've reviewed the spec, it looks good, please proceed."
)

BRAINSTORMING_TRIGGERED=false
ARCHITECTURE_GATE_TRIGGERED=false
ARCHITECTURE_GATE_TURN=0
WRITING_PLANS_BEFORE_ARCHITECTURE=false
OUTCOME="inconclusive"
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

    if skill_invoked_in "$LOG_FILE" "architecture-gate"; then
        ARCHITECTURE_GATE_TRIGGERED=true
        ARCHITECTURE_GATE_TURN=$TURN_NUM
        OUTCOME="pass"
        break
    fi

    if skill_invoked_in "$LOG_FILE" "writing-plans"; then
        WRITING_PLANS_BEFORE_ARCHITECTURE=true
        OUTCOME="fail"
        break
    fi
done

if [ "$BRAINSTORMING_TRIGGERED" = "false" ]; then
    OUTCOME="inconclusive"
fi

cat > "$TRIAL_DIR/result.json" <<EOF
{
  "scenario": "$SCENARIO",
  "trial_dir": "$TRIAL_DIR",
  "brainstorming_triggered": $BRAINSTORMING_TRIGGERED,
  "architecture_gate_triggered": $ARCHITECTURE_GATE_TRIGGERED,
  "architecture_gate_turn": $ARCHITECTURE_GATE_TURN,
  "writing_plans_before_architecture": $WRITING_PLANS_BEFORE_ARCHITECTURE,
  "turns_used": $TURNS_USED,
  "outcome": "$OUTCOME"
}
EOF

echo "Trial complete: scenario=$SCENARIO outcome=$OUTCOME turns_used=$TURNS_USED"
echo "Result: $TRIAL_DIR/result.json"

if [ "$OUTCOME" = "pass" ]; then
    exit 0
else
    exit 1
fi
```

**Known limitation to document (carried into Task 4's README):** if both `writing-plans` and `architecture-gate` are invoked within the *same* turn's log, this script treats `architecture-gate` as the winner regardless of which was actually called first within that turn — cross-tool-call ordering within a single turn isn't checked, only presence per turn, matching the rigor level of Superpowers' own equivalent tests.

- [ ] **Step 2: Verify syntax**

```bash
bash -n tests/gate-routing/run-trial.sh
```

Expected: no output, exit code 0.

- [ ] **Step 3: Smoke-test one real trial**

```bash
chmod +x tests/gate-routing/run-trial.sh
tests/gate-routing/run-trial.sh bare /tmp/factory-gates-smoke-test
cat /tmp/factory-gates-smoke-test/result.json
```

Expected: the script runs to completion (up to a few minutes), and `result.json` contains valid JSON with `"scenario": "bare"` and an `outcome` of `pass`, `fail`, or `inconclusive`. Any of the three outcomes is an acceptable smoke-test result — this step verifies the harness *runs end-to-end and produces a well-formed verdict*, not that the verdict is `pass`. If the run errors out before producing `result.json` at all, that's the actual failure to fix (plugin-dir path wrong, `claude` not authenticated, etc.).

- [ ] **Step 4: Commit**

```bash
git add tests/gate-routing/run-trial.sh
git commit -m "test(tests): add single-trial gate-routing driver"
```

---

### Task 3: Matrix orchestrator (`run-all.sh`)

**Files:**
- Create: `tests/gate-routing/run-all.sh`

**Interfaces:**
- Consumes: `tests/gate-routing/run-trial.sh` from Task 2 (invoked as a subprocess, not sourced)
- Produces: a printed pass/fail/inconclusive table per scenario, and `<run-dir>/summary.json`

- [ ] **Step 1: Write `tests/gate-routing/run-all.sh`**

```bash
#!/usr/bin/env bash
# Run the full gate-routing trial matrix and report pass/fail/inconclusive
# rates per scenario.
#
# Usage: run-all.sh [--scenario bare|explicit] [--trials N]
#   --scenario   Run only this scenario (default: both bare and explicit)
#   --trials N   Trials per scenario (default: 3)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCENARIOS=(bare explicit)
TRIALS=3

while [ $# -gt 0 ]; do
    case "$1" in
        --scenario)
            SCENARIOS=("$2")
            shift 2
            ;;
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
RUN_DIR="/tmp/factory-gates-tests/${TIMESTAMP}"
mkdir -p "$RUN_DIR"

echo "=== Gate-Routing Test Run ==="
echo "Scenarios: ${SCENARIOS[*]}"
echo "Trials per scenario: $TRIALS"
echo "Output dir: $RUN_DIR"
echo ""

RESULT_FILES=()

for scenario in "${SCENARIOS[@]}"; do
    for trial_num in $(seq 1 "$TRIALS"); do
        TRIAL_DIR="$RUN_DIR/$scenario/trial-$trial_num"
        echo ">>> Running $scenario trial $trial_num..."
        "$SCRIPT_DIR/run-trial.sh" "$scenario" "$TRIAL_DIR" || true
        RESULT_FILES+=("$TRIAL_DIR/result.json")
        echo ""
    done
done

echo "=== Summary ==="
jq -s '
  group_by(.scenario) | map({
    scenario: .[0].scenario,
    trials: length,
    pass: ([.[] | select(.outcome == "pass")] | length),
    fail: ([.[] | select(.outcome == "fail")] | length),
    inconclusive: ([.[] | select(.outcome == "inconclusive")] | length)
  })
' "${RESULT_FILES[@]}" | tee "$RUN_DIR/summary.json"

echo ""
echo "Full results: $RUN_DIR"

FAIL_COUNT=$(jq -s '[.[] | select(.outcome == "fail")] | length' "${RESULT_FILES[@]}")
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "WARNING: $FAIL_COUNT trial(s) hit the failure mode (writing-plans invoked without architecture-gate)."
    exit 1
fi
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n tests/gate-routing/run-all.sh
```

Expected: no output, exit code 0.

- [ ] **Step 3: Smoke-test with the cheapest possible matrix**

```bash
chmod +x tests/gate-routing/run-all.sh
tests/gate-routing/run-all.sh --scenario bare --trials 1
```

Expected: prints the run header, one `>>> Running bare trial 1...` line, then a `=== Summary ===` JSON table with one entry (`scenario: "bare"`, `trials: 1`, and `pass`/`fail`/`inconclusive` summing to 1).

- [ ] **Step 4: Commit**

```bash
git add tests/gate-routing/run-all.sh
git commit -m "test(tests): add gate-routing trial matrix orchestrator"
```

---

### Task 4: Documentation (`tests/gate-routing/README.md`)

**Files:**
- Create: `tests/gate-routing/README.md`

**Interfaces:**
- Consumes: nothing executable — describes Tasks 1-3's scripts
- Produces: `tests/gate-routing/README.md`, referenced from the main `CLAUDE.md`'s "Testing" section

- [ ] **Step 1: Write `tests/gate-routing/README.md`**

```markdown
# Gate-Routing Tests

Empirically tests the one real skill-routing conflict in this plugin:
Superpowers' `brainstorming` skill ends with a hard, twice-repeated
instruction -- "The ONLY skill you invoke after brainstorming is
writing-plans... do NOT invoke any other skill" -- while
`architecture-gate` tries to insert itself between `brainstorming` and
`writing-plans` via a highly specific trigger description plus
Superpowers' own "if a skill applies, you MUST use it" routing rule. The
README at the repo root calls this a "soft override, not a hard one."
This test suite measures how often it actually holds.

The other two gate handoffs (`architecture-gate` -> `program-design-gate`,
`program-design-gate` -> `writing-plans`) aren't tested here because
there's no conflict to measure -- both sides are our own skills, or our
skill hands off to `writing-plans` the same way `writing-plans` itself
expects.

## How it works

Real `claude -p` sessions, with both `superpowers` and `factory-gates`
loaded via `--plugin-dir`, driven through an actual brainstorming
conversation about a small, fully-specified feature (an in-memory rate
limiter) to the point where `brainstorming` would normally hand off to
`writing-plans`. Each trial records which skill actually fires next.

- **bare** scenario: ordinary feature request, no special phrasing
- **explicit** scenario: same request, prefixed with the README's
  documented workaround, "Use the factory-gates workflow for this."

Default matrix: 3 trials per scenario (6 total). Each trial gets its own
isolated `/tmp` project directory so `--continue` (which resumes "the
most recent conversation in the current directory") can't cross-contaminate
trials.

## Running

```bash
# Full matrix (2 scenarios x 3 trials, ~20-40 minutes, real token cost)
./run-all.sh

# Cheap single-trial spot check while iterating on the harness itself
./run-all.sh --scenario bare --trials 1

# One scenario, custom trial count
./run-all.sh --scenario explicit --trials 5
```

Requires: `claude` CLI installed and authenticated, `jq`, and the
Superpowers plugin installed locally (auto-discovered from
`~/.claude/plugins/cache/claude-plugins-official/superpowers/`, override
with `SUPERPOWERS_PLUGIN_DIR` to point at a different checkout).

## Reading the output

`run-all.sh` prints a table like:

```json
[
  { "scenario": "bare", "trials": 3, "pass": 2, "fail": 1, "inconclusive": 0 },
  { "scenario": "explicit", "trials": 3, "pass": 3, "fail": 0, "inconclusive": 0 }
]
```

- **pass** — `architecture-gate` was invoked before `writing-plans`
- **fail** — `writing-plans` was invoked directly, `architecture-gate`
  never fired first (the exact failure mode the README warns about)
- **inconclusive** — neither fired within 4 turns, or `brainstorming`
  itself never triggered (an environment/setup issue with the trial, not
  a signal about factory-gates' routing)

Per-trial logs and `result.json` verdicts are kept under
`/tmp/factory-gates-tests/<timestamp>/<scenario>/trial-<n>/` for
inspection after a run.

## Known limitations

- **Non-deterministic.** This is measuring an LLM's routing decision, not
  running code -- re-running the same scenario can produce different
  outcomes. Read the pass rate as a rate, not a single yes/no verdict.
  Re-run whenever `brainstorming`'s or `architecture-gate`'s wording
  changes, per `CLAUDE.md`'s "Skill Changes Require Evidence."
- **Same-turn ordering isn't checked.** If a trial invokes both
  `writing-plans` and `architecture-gate` within the same conversation
  turn, `run-trial.sh` counts it as a pass regardless of which one the
  model actually called first inside that turn. This matches the rigor
  level of Superpowers' own equivalent tests.
- **Not run in CI.** Each trial costs real tokens and needs a locally
  authenticated `claude` CLI -- this is a manual/occasional diagnostic,
  not a required check on every push.
```

- [ ] **Step 2: Verify**

```bash
grep -c "^## " tests/gate-routing/README.md
```

Expected: 4.

- [ ] **Step 3: Commit**

```bash
git add tests/gate-routing/README.md
git commit -m "docs(tests): document gate-routing test harness"
```

---

### Task 5: Run the full matrix and report results

**Files:** none (this task produces a result, not a file change)

**Interfaces:**
- Consumes: `run-all.sh` from Task 3

- [ ] **Step 1: Run the full default matrix**

```bash
cd /home/christopher/PycharmProjects/factory-gates
tests/gate-routing/run-all.sh
```

Expected: takes roughly 20-40 minutes. Ends with the `=== Summary ===` table covering both scenarios at 3 trials each.

- [ ] **Step 2: Report to human partner**

Paste the summary table into the conversation with your human partner, along with the location of `summary.json` and any `fail`/`inconclusive` trial directories worth a closer look (e.g. `grep -o '"skill":"[^"]*"' <trial-dir>/turn*.json` to see exactly what fired). Do not editorialize about whether the result is "good" or "bad" beyond stating the numbers -- let your human partner decide whether the README's "soft override" framing needs to change based on what was actually observed.

---

### Task 6: Open PR, review, merge

**Files:** none

**Interfaces:**
- Consumes: all commits from Tasks 1-4 on `test/gate-routing-handoff`; Task 5's results to paste into the PR body

- [ ] **Step 1: Push the branch**

```bash
git push -u origin test/gate-routing-handoff
```

- [ ] **Step 2: Open the PR**

Fill in the `<PASTE ...>` placeholders below with Task 5's actual summary table before running this command -- do not open the PR with them still literal.

```bash
gh pr create --title "test(tests): add gate-routing handoff test harness" --body "$(cat <<'EOF'
## Who is submitting this PR? (required)

| Field | Value |
|-------|-------|
| Your model + version | Claude Sonnet 5 |
| Harness + version | Claude Code |
| All plugins installed | superpowers |
| Human partner who reviewed this diff | (fill in before merging) |

## What problem are you trying to solve?

The README documents a known limitation: architecture-gate's ability to
insert itself between brainstorming and writing-plans is a "soft
override, not a hard one," untested. This PR builds the harness to
actually measure it instead of leaving it as an assertion.

## What does this PR change?

Adds tests/gate-routing/ -- a bash+jq harness that drives real claude -p
sessions through a brainstorming conversation with both superpowers and
factory-gates loaded, and reports the pass rate of the
brainstorming -> architecture-gate handoff, bare and with the README's
documented explicit-instruction workaround.

## Which gate does this touch?

architecture-gate (measurement only, no wording changed in this PR).

## What alternatives did you consider?

Considered a Node/Python harness for cleaner JSON handling and reporting,
but this repo has no runtime dependency today and bash+jq matches
Superpowers' own tests/explicit-skill-requests/ convention closely enough
to be immediately recognizable.

## Existing PRs
- [x] I have reviewed open AND closed PRs/issues for duplicates or prior art
- Related PRs/issues: none found

## Rigor
- [x] This change was tested adversarially, not just on the happy path
- [x] Ran tests/gate-routing/run-all.sh -- results:

<PASTE Task 5's summary.json table here>

## Human review
- [ ] A human has reviewed the COMPLETE proposed diff before submission
EOF
)"
```

- [ ] **Step 3: Human review gate**

Stop here. Show the human partner the complete diff (`git diff main...test/gate-routing-handoff`), the PR URL, and Task 5's results. Do not proceed to Step 4 until they explicitly approve.

- [ ] **Step 4: Merge**

```bash
gh pr merge --squash --delete-branch
```

- [ ] **Step 5: Verify**

```bash
git checkout main
git pull
ls tests/gate-routing/
```

Expected: `README.md`, `lib/`, `run-all.sh`, `run-trial.sh` all present on `main`.

## Self-Review

1. **Spec coverage:** `lib/common.sh` (Task 1), `run-trial.sh` (Task 2) implementing the exact 4-turn script and pass/fail/inconclusive classification from the spec, `run-all.sh` (Task 3) implementing the `--scenario`/`--trials` flags and jq aggregation, `README.md` (Task 4) covering purpose/usage/output/limitations, an actual full-matrix run with results reported (Task 5), and the PR/merge flow (Task 6). CI integration is explicitly out of scope per the spec.
2. **Placeholder scan:** the PR body in Task 6 has one intentional, clearly-marked placeholder (`<PASTE Task 5's summary.json table here>`) that must be filled from Task 5's real output before the PR is opened — flagged explicitly in Step 2's instructions, not left implicit.
3. **Type consistency:** `run-trial.sh`'s `result.json` field names (`scenario`, `outcome`, `architecture_gate_triggered`, `architecture_gate_turn`, `writing_plans_before_architecture`, `brainstorming_triggered`, `turns_used`, `trial_dir`) match exactly what `run-all.sh`'s `jq` aggregation reads (`.scenario`, `.outcome`) and what the README's "Reading the output" section describes (`pass`/`fail`/`inconclusive` as the three `outcome` values, consistently named across all three scripts and the docs).
