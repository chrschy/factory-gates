# Release Checks Race-Condition Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `release.sh`'s premature "no checks reported" failure by retrying specifically on that race-condition message, while still failing immediately on any genuine check failure.

**Architecture:** Replace the single `gh pr checks --watch --fail-fast` call with a bounded retry loop around it.

**Tech Stack:** bash (no new dependency).

## Global Constraints

- Retry only on the literal "no checks reported" race condition. Any other failure output breaks the loop immediately -- no weakening of fail-fast behavior for real check failures.
- No changes to `release.yml`, to `--dry-run` behavior, or to what counts as a required check.

---

### Task 1: Apply the retry loop, verify, PR

**Files:**
- Modify: `.github/scripts/release.sh`

**Interfaces:** none

- [ ] **Step 1: Replace the checks-wait block**

Find:

```bash
echo "Waiting for required checks on the release PR..."
if ! gh pr checks "$RELEASE_BRANCH" --watch --fail-fast; then
    echo "" >&2
    echo "ERROR: required checks failed on the release PR ($PR_URL)." >&2
    echo "Not merging, not tagging, not releasing. Fix the failure, then either" >&2
    echo "push a fix to $RELEASE_BRANCH or close the PR and re-run this workflow." >&2
    rm -f "$NOTES_FILE"
    exit 1
fi
```

Replace with:

```bash
echo "Waiting for required checks on the release PR..."
CHECKS_OK=0
for attempt in 1 2 3 4 5 6; do
    if CHECKS_OUTPUT="$(gh pr checks "$RELEASE_BRANCH" --watch --fail-fast 2>&1)"; then
        echo "$CHECKS_OUTPUT"
        CHECKS_OK=1
        break
    fi
    echo "$CHECKS_OUTPUT"
    if printf '%s' "$CHECKS_OUTPUT" | grep -q "no checks reported"; then
        echo "Checks not registered yet (attempt $attempt/6) -- retrying in 5s..."
        sleep 5
        continue
    fi
    break
done

if [ "$CHECKS_OK" != "1" ]; then
    echo "" >&2
    echo "ERROR: required checks failed (or never appeared) on the release PR ($PR_URL)." >&2
    echo "Not merging, not tagging, not releasing. Fix the failure, then either" >&2
    echo "push a fix to $RELEASE_BRANCH or close the PR and re-run this workflow." >&2
    rm -f "$NOTES_FILE"
    exit 1
fi
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n .github/scripts/release.sh
```

Expected: no output.

- [ ] **Step 3: Re-verify dry-run path is unaffected**

```bash
.github/scripts/release.sh --dry-run
```

Expected: same shape as before (computes version, prints notes, stops before commit/tag/push/release) -- this code path never reaches the edited block.

- [ ] **Step 4: Commit**

```bash
git add .github/scripts/release.sh
git commit -m "fix(ci): retry release PR checks-wait on registration race condition"
```

- [ ] **Step 5: Push, open PR**

```bash
git push -u origin fix/release-checks-race-condition
```

Open the PR with `gh pr create`, following this repo's established template: who's submitting, what problem (the exact race-condition failure log from the real v0.3.0 attempt, and independent confirmation that PR #26's checks genuinely passed), what changed, which gate (none), alternatives considered (flat sleep before first check vs. targeted retry -- targeted retry chosen to avoid both under- and over-waiting), existing-PRs checkbox noting this is a direct follow-up to #20's PR-based flow and today's real release attempts, rigor section citing the syntax/dry-run verification and noting the real end-to-end test is the next release trigger, human-review checkbox unchecked.

- [ ] **Step 6: Report to human partner**

Show the complete diff (`git diff main...fix/release-checks-race-condition`) and the PR URL. Per standing instruction, do not merge.

## Self-Review

1. **Spec coverage:** single task, matches the spec's single fix exactly.
2. **Placeholder scan:** none -- exact replacement code given.
3. **Type consistency:** `CHECKS_OK`/`CHECKS_OUTPUT` variable names are self-contained to this block, no collision with existing script variables (`NEXT_VERSION`, `RELEASE_BRANCH`, `PR_URL`, `NOTES_FILE` all remain referenced correctly).
