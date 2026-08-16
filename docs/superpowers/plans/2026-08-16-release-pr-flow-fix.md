# Fix Release PR-Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `.github/scripts/release.sh` so it lands the version-bump commit through a real PR (waited-on check + admin-merge) instead of a raw direct push, which the `fast-tests` required status check now structurally blocks.

**Architecture:** Version calculation and release-notes generation stay exactly as-is. Only the "land the commit" tail changes: branch + PR + `gh pr checks --watch --fail-fast` + admin-merge + tag-the-merge-commit, replacing the old commit + tag + direct push.

**Tech Stack:** bash, `gh` CLI, `git`, `jq` (unchanged dependencies).

## Global Constraints

- `dry_run` behavior is unchanged — stops before any commit/branch/PR/merge/tag/release action, exactly as today.
- If the release PR's `fast-tests` check fails, the script must stop immediately: no merge, no tag, no release. The PR is left open, not closed or deleted, so a human can inspect it.
- Bypassing the required-review-count (via `--admin` merge) is only ever used *after* the real status check has already passed — never to skip a failing or still-pending check.
- No changes to `.github/workflows/release.yml`.

---

### Task 1: Rewrite the "land the commit" tail of `release.sh`

**Files:**
- Modify: `.github/scripts/release.sh`

**Interfaces:** none (single script, no other file depends on its internals)

- [ ] **Step 1: Locate the section to replace**

The current tail (everything after the `dry_run` early-exit) reads:

```bash
if [ -z "${RELEASE_PAT:-}" ]; then
    echo "ERROR: RELEASE_PAT is not set. A real release needs a repository secret" >&2
    echo "named RELEASE_PAT (a Personal Access Token from an admin account) so this" >&2
    echo "workflow can push past main's branch protection. See" >&2
    echo "docs/superpowers/specs/2026-08-11-automated-release-versioning-design.md" >&2
    echo "for setup instructions. Re-run with --dry-run to test without it." >&2
    rm -f "$NOTES_FILE"
    exit 1
fi

jq --arg v "$NEXT_VERSION" '.version = $v' "$PLUGIN_JSON" > "${PLUGIN_JSON}.tmp" && mv "${PLUGIN_JSON}.tmp" "$PLUGIN_JSON"
jq --arg v "$NEXT_VERSION" '.plugins[0].version = $v' "$MARKETPLACE_JSON" > "${MARKETPLACE_JSON}.tmp" && mv "${MARKETPLACE_JSON}.tmp" "$MARKETPLACE_JSON"

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add "$PLUGIN_JSON" "$MARKETPLACE_JSON"
git commit -m "chore(release): v${NEXT_VERSION}"
git tag "v${NEXT_VERSION}"

git remote set-url origin "https://x-access-token:${RELEASE_PAT}@github.com/chrschy/factory-gates.git"
git push origin main --follow-tags

gh release create "v${NEXT_VERSION}" --title "v${NEXT_VERSION}" --notes-file "$NOTES_FILE"

rm -f "$NOTES_FILE"

echo ""
echo "Released v${NEXT_VERSION}"
```

- [ ] **Step 2: Replace it with the PR-based flow**

```bash
if [ -z "${RELEASE_PAT:-}" ]; then
    echo "ERROR: RELEASE_PAT is not set. A real release needs a repository secret" >&2
    echo "named RELEASE_PAT (a Personal Access Token from an admin account) so this" >&2
    echo "workflow can open and admin-merge the release PR. See" >&2
    echo "docs/superpowers/specs/2026-08-16-release-pr-flow-fix-design.md" >&2
    echo "for setup instructions. Re-run with --dry-run to test without it." >&2
    rm -f "$NOTES_FILE"
    exit 1
fi

jq --arg v "$NEXT_VERSION" '.version = $v' "$PLUGIN_JSON" > "${PLUGIN_JSON}.tmp" && mv "${PLUGIN_JSON}.tmp" "$PLUGIN_JSON"
jq --arg v "$NEXT_VERSION" '.plugins[0].version = $v' "$MARKETPLACE_JSON" > "${MARKETPLACE_JSON}.tmp" && mv "${MARKETPLACE_JSON}.tmp" "$MARKETPLACE_JSON"

RELEASE_BRANCH="release/v${NEXT_VERSION}"

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git checkout -b "$RELEASE_BRANCH"
git add "$PLUGIN_JSON" "$MARKETPLACE_JSON"
git commit -m "chore(release): v${NEXT_VERSION}"

git remote set-url origin "https://x-access-token:${RELEASE_PAT}@github.com/chrschy/factory-gates.git"
git push origin "$RELEASE_BRANCH"

export GH_TOKEN="$RELEASE_PAT"

PR_URL="$(gh pr create --title "chore(release): v${NEXT_VERSION}" --base main --head "$RELEASE_BRANCH" --body "Automated release PR for v${NEXT_VERSION}. See the workflow run for the full computed release notes.")"
echo "Release PR: $PR_URL"

echo "Waiting for required checks on the release PR..."
if ! gh pr checks "$RELEASE_BRANCH" --watch --fail-fast; then
    echo "" >&2
    echo "ERROR: required checks failed on the release PR ($PR_URL)." >&2
    echo "Not merging, not tagging, not releasing. Fix the failure, then either" >&2
    echo "push a fix to $RELEASE_BRANCH or close the PR and re-run this workflow." >&2
    rm -f "$NOTES_FILE"
    exit 1
fi

gh pr merge "$RELEASE_BRANCH" --squash --admin

git fetch origin main
git checkout main
git reset --hard origin/main

git tag "v${NEXT_VERSION}"
git push origin "v${NEXT_VERSION}"

gh release create "v${NEXT_VERSION}" --title "v${NEXT_VERSION}" --notes-file "$NOTES_FILE"

rm -f "$NOTES_FILE"

echo ""
echo "Released v${NEXT_VERSION}"
```

Note: `gh pr checks`/`gh pr merge` accept a branch name in place of a PR number, so `$RELEASE_BRANCH` works directly without needing to parse `$PR_URL` for a number.

- [ ] **Step 3: Verify syntax**

```bash
bash -n .github/scripts/release.sh
```

Expected: no output.

- [ ] **Step 4: Re-verify the dry-run path is unaffected**

```bash
.github/scripts/release.sh --dry-run
```

Expected: prints `Last tag:`, `Declared version:`, `Commits since last tag:`, `Next version:`, the release notes, and `DRY RUN: stopping before commit/tag/push/release.` — identical shape to before this change, confirming the shared version-calculation/notes-generation code above the edited section is untouched.

- [ ] **Step 5: Commit**

```bash
git add .github/scripts/release.sh
git commit -m "fix(ci): land release commits through a PR instead of a direct push"
```

---

### Task 2: Push, open PR, report

**Files:** none (git/GitHub operations only)

**Interfaces:** none

- [ ] **Step 1: Push and open the PR**

```bash
git push -u origin fix/release-pr-flow
```

Open the PR with `gh pr create`, following this repo's established template: who's submitting, what problem (the real failed release run's exact error), what changed (PR-based landing instead of direct push, with the review-bypass-vs-check-bypass distinction called out explicitly), which gate (none), alternatives considered (temporarily disabling the required check -- rejected, per the design spec's reasoning), existing-PRs checkbox noting this was caused by #16/#17 and is a direct follow-up to the manual v0.2.0 release (#19), rigor section citing the dry-run re-verification, human-review checkbox unchecked. Note explicitly that the real end-to-end test (actually triggering `release.yml` for the next real release) can only happen after this PR merges, since the workflow's next invocation is what will exercise the new code path for real -- flag this as the actual verification step, not something this PR itself can complete before merge.

- [ ] **Step 2: Report to human partner**

Show the complete diff (`git diff main...fix/release-pr-flow`) and the PR URL. Per standing instruction, do not merge.

## Self-Review

1. **Spec coverage:** Task 1 covers the script rewrite and both verification steps (syntax + dry-run re-check); Task 2 covers PR + report. The spec's "real end-to-end test" verification step is explicitly deferred to after merge (the next real release trigger), matching the spec's own Verification section, which lists it as the third and final check.
2. **Placeholder scan:** none — the full replacement script section is exact, not sketched.
3. **Type consistency:** `RELEASE_BRANCH` is used consistently for push, `gh pr create --head`, `gh pr checks`, and `gh pr merge` -- no drift between the branch name used to open the PR and the one used to check/merge it.
