# factory-gates — Fix Release Script's Checks-Race Condition

**Status:** approved
**Date:** 2026-08-17

## Why

Triggering `release.yml` for the real v0.3.0 release got further than any prior attempt (correctly computed the version, created the release branch, pushed it, and opened PR #26 for real -- confirming both the version-calc logic and the `RELEASE_PAT` permission fix from earlier today both work). It then failed:

```
Waiting for required checks on the release PR...
no checks reported on the 'release/v0.3.0' branch
ERROR: required checks failed on the release PR (...)
```

But PR #26's checks (`fast-tests`, `secrets-scan`) both actually passed once inspected directly afterward. This is a genuine race condition, not a real check failure: `release.sh` calls `gh pr checks "$RELEASE_BRANCH" --watch --fail-fast` immediately after `gh pr create` returns, but GitHub hasn't necessarily registered the triggered `pull_request`-event workflow run as a check yet at that exact moment. `gh pr checks --watch` treats "zero checks currently visible" as an immediate failure rather than something to keep waiting on.

## Fix

Wrap the `gh pr checks --watch --fail-fast` call in a bounded retry loop that retries specifically when the failure is the "no checks reported" race condition, and fails immediately (no retry) for any other reason -- preserving fail-fast semantics for genuine check failures:

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

Up to 6 attempts, 5s apart (30s total extra budget) -- GitHub Actions typically registers a triggered check within a few seconds; this is a generous margin without being an indefinite wait. A genuine check failure (checks that exist and report failure, not "no checks reported") breaks out of the loop immediately on the first attempt, matching the original fail-fast intent.

## Verification

The real end-to-end test is triggering the release workflow again after this merges -- the exact failure mode this fixes can only be observed under real GitHub Actions timing, not locally. No dry-run change (this code is entirely after the `DRY_RUN` early-exit).

## Self-review

- **Placeholders:** none -- exact retry logic given.
- **Internal consistency:** explicitly distinguishes "no checks reported yet" (retry) from any other failure (fail immediately) -- doesn't weaken fail-fast behavior for real problems.
- **Scope:** one function's worth of retry logic in one file. No changes to `release.yml`, no changes to what counts as a required check.
- **Ambiguity:** none -- root-caused from a real, just-observed failure log and independently confirmed (PR #26's checks genuinely passed), not guessed at.
