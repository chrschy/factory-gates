# Gate-Routing Bypass Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `tests/gate-routing/run-trial.sh` correctly classify trials where `brainstorming` never fires but another skill is invoked instead (a routing bypass), instead of silently folding that signal into `inconclusive`. Refresh the README's determinism numbers with real post-fix data.

**Architecture:** One new helper in `tests/gate-routing/lib/common.sh`, one new check in `run-trial.sh`'s per-turn classification loop, one new `bypass_skill` field in `result.json`, plus documentation updates in the root `README.md` and `tests/gate-routing/README.md`. No changes to `run-all.sh`'s aggregation logic.

**Tech Stack:** bash, jq, grep/sed.

## Global Constraints

- `outcome` in `result.json` stays a three-value enum (`pass`/`fail`/`inconclusive`) — do not add a fourth value. A routing bypass is classified as `fail`.
- `run-all.sh` is not modified — its `jq` summary logic must keep working unchanged against the (still three-valued) `outcome` field.
- The bypass check must only fire while `brainstorming` genuinely has not triggered yet in the trial so far — never flag a turn where `brainstorming` and another skill both appear.
- Scope is `tests/gate-routing/` only — do not touch `tests/gate-quality/`.

---

### Task 1: Add and verify the `first_skill_invoked_in` helper

**Files:**
- Modify: `tests/gate-routing/lib/common.sh`

**Interfaces:**
- Produces: `first_skill_invoked_in <log_file>` — prints the name of the first `Skill` tool invocation in the log (namespace prefix stripped), or nothing if none found. Used by Task 2.

- [ ] **Step 1: Add the helper function**

Append to `tests/gate-routing/lib/common.sh`, right after the existing `skill_invoked_in` function:

```bash

# Returns the name of the first Skill tool invocation in a log file
# (namespace prefix stripped, e.g. "superpowers:test-driven-development"
# -> "test-driven-development"), or nothing if no Skill call appears.
first_skill_invoked_in() {
    local log_file="$1"
    grep -o '"skill":"[^"]*"' "$log_file" 2>/dev/null | head -1 | \
        sed -E 's/"skill":"([^:"]*:)?([^"]*)"/\2/'
}
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n tests/gate-routing/lib/common.sh
```

Expected: no output (syntax OK).

- [ ] **Step 3: Verify against real saved logs (no live API calls)**

These logs already exist on disk from a prior real trial run that surfaced this bug — use them directly rather than spending new API calls:

```bash
source tests/gate-routing/lib/common.sh
first_skill_invoked_in /tmp/factory-gates-tests/1786783482/bare/trial-1/turn1.json
first_skill_invoked_in /tmp/factory-gates-tests/1786783482/bare/trial-2/turn1.json
first_skill_invoked_in /tmp/factory-gates-tests/1786783482/bare/trial-3/turn1.json
first_skill_invoked_in /tmp/factory-gates-tests/1786783482/explicit/trial-1/turn4.json
```

Expected: first three print `test-driven-development` (the bypass case this fix targets); the fourth prints `architecture-gate` (confirms the helper also correctly identifies a normal, non-bypass skill call).

- [ ] **Step 4: Commit**

```bash
git add tests/gate-routing/lib/common.sh
git commit -m "feat(tests): add first_skill_invoked_in helper for bypass detection"
```

---

### Task 2: Wire bypass detection into `run-trial.sh`, update `result.json`

**Files:**
- Modify: `tests/gate-routing/run-trial.sh`

**Interfaces:**
- Consumes: `first_skill_invoked_in <log_file>` from Task 1.
- Produces: `result.json` gains a `bypass_skill` field (string, empty when not applicable).

- [ ] **Step 1: Initialize the tracking variable**

In `run-trial.sh`, find this block (the existing outcome-tracking variables before the turn loop):

```bash
BRAINSTORMING_TRIGGERED=false
ARCHITECTURE_GATE_TRIGGERED=false
ARCHITECTURE_GATE_TURN=0
WRITING_PLANS_BEFORE_ARCHITECTURE=false
OUTCOME="inconclusive"
TURNS_USED=0
```

Add `BYPASS_SKILL=""` to it:

```bash
BRAINSTORMING_TRIGGERED=false
ARCHITECTURE_GATE_TRIGGERED=false
ARCHITECTURE_GATE_TURN=0
WRITING_PLANS_BEFORE_ARCHITECTURE=false
BYPASS_SKILL=""
OUTCOME="inconclusive"
TURNS_USED=0
```

- [ ] **Step 2: Add the bypass check to the turn loop**

Find this block inside the `for i in "${!TURNS[@]}"; do ... done` loop (after the existing `writing-plans` check):

```bash
    if skill_invoked_in "$LOG_FILE" "writing-plans"; then
        WRITING_PLANS_BEFORE_ARCHITECTURE=true
        OUTCOME="fail"
        break
    fi
done
```

Insert a new check between the `writing-plans` block and the loop's closing `done`:

```bash
    if skill_invoked_in "$LOG_FILE" "writing-plans"; then
        WRITING_PLANS_BEFORE_ARCHITECTURE=true
        OUTCOME="fail"
        break
    fi

    if [ "$BRAINSTORMING_TRIGGERED" = "false" ]; then
        CANDIDATE="$(first_skill_invoked_in "$LOG_FILE")"
        if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "brainstorming" ]; then
            BYPASS_SKILL="$CANDIDATE"
            OUTCOME="fail"
            break
        fi
    fi
done
```

- [ ] **Step 3: Add `bypass_skill` to the `result.json` heredoc**

Find:

```bash
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
```

Replace with:

```bash
cat > "$TRIAL_DIR/result.json" <<EOF
{
  "scenario": "$SCENARIO",
  "trial_dir": "$TRIAL_DIR",
  "brainstorming_triggered": $BRAINSTORMING_TRIGGERED,
  "architecture_gate_triggered": $ARCHITECTURE_GATE_TRIGGERED,
  "architecture_gate_turn": $ARCHITECTURE_GATE_TURN,
  "writing_plans_before_architecture": $WRITING_PLANS_BEFORE_ARCHITECTURE,
  "bypass_skill": "$BYPASS_SKILL",
  "turns_used": $TURNS_USED,
  "outcome": "$OUTCOME"
}
EOF
```

- [ ] **Step 4: Verify syntax**

```bash
bash -n tests/gate-routing/run-trial.sh
```

Expected: no output (syntax OK).

- [ ] **Step 5: Commit**

```bash
git add tests/gate-routing/run-trial.sh
git commit -m "fix(tests): classify skill-bypass as fail instead of inconclusive"
```

---

### Task 3: Live verification run, README updates, PR

**Files:**
- Modify: `README.md`
- Modify: `tests/gate-routing/README.md`

**Interfaces:** none

- [ ] **Step 1: Run the full default matrix live (3 bare + 3 explicit trials)**

```bash
cd tests/gate-routing
./run-all.sh
cd -
```

Record the printed summary JSON — this is the "after" data for the PR body. Expected: `bare` trials show `outcome: "fail"` with `bypass_skill` populated (most likely `test-driven-development`, matching the pattern already observed); `explicit` trials show `outcome: "pass"`, consistent with prior runs.

- [ ] **Step 2: Update the root `README.md`'s "Known limitation" section**

In the `[!WARNING]` callout, after the existing sentence ending "...this is a soft override, not a hard one, and this repo measures it empirically (`tests/gate-routing/`) rather than just asserting it works.", add a new sentence describing the more severe pattern this fix surfaced:

```
A bare request can skip `brainstorming` entirely and jump straight into an unrelated skill (e.g. `test-driven-development`) instead -- a more severe pattern than losing only the `architecture-gate` handoff, and one the test harness now detects and classifies as a failure rather than an inconclusive result.
```

- [ ] **Step 3: Update the determinism table with real numbers**

Replace the "Say so explicitly" row's measured result with the folded total (16 prior formal trials + 3 fresh trials from Step 1 = 19; adjust the fail count only if Step 1's explicit trials showed any failures). Add a new row above it for the bare baseline, using Step 1's actual bare results (adjust pass/fail/bypass counts to match what Step 1 actually printed -- do not invent numbers):

```
| (bare, no phrasing) | Plain feature request, no workaround | 3 trials: 0 pass, 3 fail (all 3 skipped `brainstorming` entirely and jumped straight to another skill instead) -- this is the baseline the mechanisms below improve on |
| Say so explicitly | Start the feature with *"Use the factory-gates workflow for this."* | 19 formal trials, 0 fails |
```

- [ ] **Step 4: Update `tests/gate-routing/README.md`'s "Reading the output" section**

After the existing bullet list (`pass`/`fail`/`inconclusive` definitions), add:

```
Trials whose `outcome` is `fail` because `brainstorming` was bypassed
entirely (rather than `writing-plans` firing without `architecture-gate`)
carry a non-empty `bypass_skill` field in `result.json`, naming the skill
that fired instead.
```

- [ ] **Step 5: Verify no unintended factual drift**

```bash
grep -c "bypass_skill" tests/gate-routing/run-trial.sh
grep -c "bypass_skill" tests/gate-routing/README.md
grep -c "skip \`brainstorming\` entirely\|skip brainstorming entirely" README.md
```

Expected: at least 1 for each.

- [ ] **Step 6: Commit**

```bash
git add README.md tests/gate-routing/README.md
git commit -m "docs(meta): document gate-routing bypass detection and refresh trial numbers"
```

- [ ] **Step 7: Push, open PR**

```bash
git push -u origin fix/gate-routing-bypass-detection
```

Open the PR with `gh pr create`, following this repo's established PR template pattern (see prior PRs #7-#11 for exact structure): who's submitting, what problem, what changed, which gate (none -- test harness only), alternatives considered (the three classification approaches from the design spec, noting B was chosen), existing-PRs checkbox, rigor section citing the Task 1 saved-log verification plus the Step 1 live before/after numbers, human-review checkbox unchecked.

- [ ] **Step 8: Report to human partner**

Show the complete diff (`git diff main...fix/gate-routing-bypass-detection`) and the PR URL. Per standing instruction, do not merge -- the human partner reviews manually.

## Self-Review

1. **Spec coverage:** Task 1 covers the helper + free verification; Task 2 covers the classification wiring + result.json field; Task 3 covers live verification, both README updates, and PR. All spec sections have a corresponding task.
2. **Placeholder scan:** Step 3 of Task 3 explicitly instructs "adjust to match what Step 1 actually printed -- do not invent numbers" rather than hardcoding a guessed count, since the live run hasn't happened yet at plan-writing time. This is a deliberate exception to "no placeholders" -- the exact bare/explicit counts are empirical and only known after Task 3 Step 1 runs; the plan gives the exact table structure and states the fallback values as good defaults if the live results match the already-observed pattern.
3. **Type consistency:** `bypass_skill` is referenced identically in Task 1 (helper name), Task 2 (variable name and JSON field), and Task 3 (README field name) -- no naming drift.
