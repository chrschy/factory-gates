# Gate-Routing Detour Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `tests/gate-routing/run-trial.sh` record when a trial detours to an unrelated skill mid-conversation (after `brainstorming` fires, before `architecture-gate`/`writing-plans` fires), without changing outcome classification. Refresh the README with real detour-rate data.

**Architecture:** One new tracking variable and one new check in `run-trial.sh`'s existing per-turn loop, reusing the `first_skill_invoked_in` helper added in PR #12. One new `detour_skill` field in `result.json`. Documentation updates in both READMEs. No changes to `common.sh`, `run-all.sh`, or outcome semantics.

**Tech Stack:** bash, jq, grep/sed.

## Global Constraints

- `OUTCOME` (`pass`/`fail`/`inconclusive`) must not change as a result of this fix — this is a diagnostic-only addition. A detour that still reaches `architecture-gate` stays `pass`.
- The detour check must only fire once `BRAINSTORMING_TRIGGERED` is true, and must not overwrite `DETOUR_SKILL` after the first occurrence.
- Reuse `first_skill_invoked_in` from `common.sh` (added in PR #12) — do not duplicate its logic.
- Scope is `tests/gate-routing/` only.

---

### Task 1: Wire detour detection into `run-trial.sh`, verify against saved logs, live re-run, update docs, PR

**Files:**
- Modify: `tests/gate-routing/run-trial.sh`
- Modify: `README.md`
- Modify: `tests/gate-routing/README.md`

**Interfaces:**
- Consumes: `first_skill_invoked_in <log_file>` from `tests/gate-routing/lib/common.sh` (unchanged).
- Produces: `result.json` gains a `detour_skill` field (string, empty when not applicable).

- [ ] **Step 1: Add `DETOUR_SKILL` to the tracking variables**

Find:

```bash
BRAINSTORMING_TRIGGERED=false
ARCHITECTURE_GATE_TRIGGERED=false
ARCHITECTURE_GATE_TURN=0
WRITING_PLANS_BEFORE_ARCHITECTURE=false
BYPASS_SKILL=""
OUTCOME="inconclusive"
TURNS_USED=0
```

Replace with:

```bash
BRAINSTORMING_TRIGGERED=false
ARCHITECTURE_GATE_TRIGGERED=false
ARCHITECTURE_GATE_TURN=0
WRITING_PLANS_BEFORE_ARCHITECTURE=false
BYPASS_SKILL=""
DETOUR_SKILL=""
OUTCOME="inconclusive"
TURNS_USED=0
```

- [ ] **Step 2: Add the detour check to the turn loop**

Find the bypass check added in PR #12 (the last check inside the loop, right before the loop's closing `done`):

```bash
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

Add a new check immediately after it, still inside the loop:

```bash
    if [ "$BRAINSTORMING_TRIGGERED" = "false" ]; then
        CANDIDATE="$(first_skill_invoked_in "$LOG_FILE")"
        if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "brainstorming" ]; then
            BYPASS_SKILL="$CANDIDATE"
            OUTCOME="fail"
            break
        fi
    fi

    if [ "$BRAINSTORMING_TRIGGERED" = "true" ] && [ -z "$DETOUR_SKILL" ]; then
        CANDIDATE="$(first_skill_invoked_in "$LOG_FILE")"
        if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "brainstorming" ] && [ "$CANDIDATE" != "architecture-gate" ] && [ "$CANDIDATE" != "writing-plans" ]; then
            DETOUR_SKILL="$CANDIDATE"
        fi
    fi
done
```

The `!= "brainstorming"` exclusion matters: on the very turn `brainstorming` first triggers, `first_skill_invoked_in` returns `"brainstorming"` itself (it's the first skill call in that turn's log) — without this exclusion, the triggering turn would be misflagged as its own detour.

Note this check does not `break` — it only records; the loop continues to the next turn normally, and the existing `architecture-gate`/`writing-plans` checks (earlier in the same iteration) still control `OUTCOME` and loop termination exactly as before.

- [ ] **Step 3: Add `detour_skill` to the `result.json` heredoc**

Find:

```bash
  "bypass_skill": "$BYPASS_SKILL",
  "turns_used": $TURNS_USED,
  "outcome": "$OUTCOME"
```

Replace with:

```bash
  "bypass_skill": "$BYPASS_SKILL",
  "detour_skill": "$DETOUR_SKILL",
  "turns_used": $TURNS_USED,
  "outcome": "$OUTCOME"
```

- [ ] **Step 4: Verify syntax**

```bash
bash -n tests/gate-routing/run-trial.sh
```

Expected: no output.

- [ ] **Step 5: Verify the detour-detection logic against already-captured logs (no new API calls)**

```bash
source tests/gate-routing/lib/common.sh
first_skill_invoked_in /tmp/factory-gates-item17-investigation/trial-3/turn2.json
first_skill_invoked_in /tmp/factory-gates-item17-investigation/trial-4/turn2.json
```

Expected: both print `test-driven-development` — confirms the same helper this fix relies on correctly identifies the detour skill in both real trials that showed the pattern.

- [ ] **Step 6: Commit**

```bash
git add tests/gate-routing/run-trial.sh
git commit -m "feat(tests): record mid-conversation skill detours in gate-routing trials"
```

- [ ] **Step 7: Fresh live run to confirm end-to-end behavior**

```bash
cd tests/gate-routing
./run-all.sh --scenario bare --trials 3
cd -
```

Expected: trials complete normally; any trial whose turn 2+ log shows a non-gate skill invoked after `brainstorming` triggered has `detour_skill` populated in its `result.json`; `outcome` values are consistent with the existing pass/fail/inconclusive rules (unchanged by this fix).

- [ ] **Step 8: Update `README.md`'s bare-scenario table row**

Fold this step's live results into the cumulative bare-scenario numbers already in the table (8 prior trials: 1 pass, 3 fail, 2 inconclusive, plus whatever Step 7 adds), and add the detour rate as a parenthetical using the real combined count (3 of 8 prior trials detoured mid-conversation; adjust to include Step 7's fresh trials -- do not invent numbers, use exactly what Step 7 printed):

```
| (bare, no phrasing) | Plain feature request, no workaround | <N> trials: <pass> pass, <fail> fail (skipped `brainstorming` entirely, jumped straight to another skill instead), <inconclusive> inconclusive (`brainstorming` ran but neither `architecture-gate` nor `writing-plans` was reached within the trial's turn budget) -- <detour_count> of these trials also showed `brainstorming` firing correctly, then getting detoured mid-conversation into an unrelated skill (usually `test-driven-development`) before ultimately settling into a pass or inconclusive outcome -- this is the baseline the mechanisms below improve on |
```

- [ ] **Step 9: Update `tests/gate-routing/README.md`'s "Reading the output" section**

After the existing `bypass_skill` explanation (added in PR #12), add:

```
A separate `detour_skill` field records a different, non-fatal pattern:
`brainstorming` fires correctly, but the conversation gets sidetracked
into an unrelated skill (most commonly `test-driven-development`) before
settling into its final outcome. Unlike `bypass_skill`, this does not
change `outcome` -- a trial that detours and still reaches
`architecture-gate` is still a `pass`. It's purely diagnostic: useful for
seeing how often trials take a detour and whether they recover.
```

- [ ] **Step 10: Verify no unintended factual drift**

```bash
grep -c "detour_skill" tests/gate-routing/run-trial.sh
grep -c "detour_skill" tests/gate-routing/README.md
grep -c "detour_skill\|detoured mid-conversation" README.md
```

Expected: at least 1 for each.

- [ ] **Step 11: Commit docs**

```bash
git add README.md tests/gate-routing/README.md
git commit -m "docs(meta): document gate-routing detour detection and refresh trial numbers"
```

- [ ] **Step 12: Push, open PR**

```bash
git push -u origin fix/gate-routing-detour-detection
```

Open the PR with `gh pr create`, following this repo's established template (see PR #12 for the closest-matching structure): who's submitting, what problem (cite the 8-trial combined detour rate), what changed, which gate (none), alternatives considered (reclassify as fail vs. diagnostic-only -- diagnostic-only chosen because a self-correcting detour still satisfies what this suite measures), existing-PRs checkbox noting this builds directly on PR #12, rigor section citing both the saved-log verification and the live before/after numbers, human-review checkbox unchecked.

- [ ] **Step 13: Report to human partner**

Show the complete diff (`git diff main...fix/gate-routing-detour-detection`) and the PR URL. Per standing instruction, do not merge.

## Self-Review

1. **Spec coverage:** the single task covers the harness change, both verification steps (saved-log + live), both README updates, and PR -- matches every section of the design spec.
2. **Placeholder scan:** Step 8's table row uses `<N>`/`<pass>`/etc. placeholders deliberately, with an explicit "do not invent numbers, use exactly what Step 7 printed" instruction -- the same accepted pattern as the bypass-detection plan's equivalent step, since the live numbers are only known after Step 7 runs.
3. **Type consistency:** `detour_skill` / `DETOUR_SKILL` naming is identical across the harness code, result.json field, and both README mentions -- no drift.
