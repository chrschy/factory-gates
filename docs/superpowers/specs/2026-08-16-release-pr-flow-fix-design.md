# factory-gates — Fix Release Automation to Use a PR Instead of a Direct Push

**Status:** approved
**Date:** 2026-08-16

## Why

Triggering `release.yml` for the real first release failed:

```
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote: - Changes must be made through a pull request.
remote: - Required status check "fast-tests" is expected.
```

`release.sh`'s original design (`docs/superpowers/specs/2026-08-11-automated-release-versioning-design.md`) pushes the version-bump commit directly to `main`, authenticated as an admin via `RELEASE_PAT`, reasoning that "pushes authenticated as an actual admin account bypass the PR requirement." That was true when it was written (2026-08-11, no required status checks existed). It stopped being true today: `fast-tests` became a required status check (#16/#17), and a required status check is structurally incompatible with a direct push — the check has to report success against a specific commit SHA before that SHA can land, but a brand-new commit created by a direct push doesn't exist until after the push completes. Admin bypass covers *merging a PR* despite missing reviews/checks (proven throughout this repo's history via `gh pr merge --admin`); it does not cover skipping the PR requirement itself for a raw push once any required status check exists.

v0.2.0 was cut manually through a normal PR (#19) as an immediate workaround. This spec fixes `release.sh` itself so future releases work through the automated workflow again.

## Fix

Replace `release.sh`'s "commit → tag → push directly" tail with "commit on a branch → PR → wait for the real check → admin-merge → tag the merge commit":

1. Compute `NEXT_VERSION` and the release notes exactly as today — **unchanged**.
2. `dry_run` still stops before any of the following — **unchanged**.
3. Bump `plugin.json`/`marketplace.json` locally — **unchanged**.
4. **New:** create branch `release/vX.Y.Z` from `main`, commit `chore(release): vX.Y.Z` there (same commit message and bot author identity as today), push the branch (via `RELEASE_PAT`).
5. **New:** `gh pr create --title "chore(release): vX.Y.Z" --base main --head release/vX.Y.Z --body <short auto-generated note>`.
6. **New:** `gh pr checks <PR> --watch --fail-fast`. If this exits non-zero (the check genuinely failed, not just "review missing"), **stop here** — do not merge, do not tag, do not release. Leave the PR open for manual inspection and print a clear error pointing at it. This is deliberate: bypassing the review-count requirement to automate releases is fine (nothing else can satisfy "1 approving review" for a bot-authored PR), but silently overriding a *failing* status check would defeat the entire reason that check exists.
7. **New:** if checks pass, `gh pr merge <PR> --squash --admin` (bypasses the review-count requirement only — the check has already genuinely passed by this point, not been overridden).
8. **New:** `git fetch origin main && git checkout main && git reset --hard origin/main` to get the actual squash-merge commit SHA (different from the branch commit's SHA).
9. Tag that merge commit `vX.Y.Z`, push the tag, `gh release create` — same as today, just sourced from the merge commit instead of the direct-push commit.

No changes to `release.yml` — `GH_TOKEN`/`RELEASE_PAT` are already wired through, and `gh pr create`/`gh pr checks`/`gh pr merge` all use `GH_TOKEN`'s own permissions regardless of the workflow's declared `permissions:` block once `GH_TOKEN` is overridden to a PAT (already the case today).

**Real side benefit:** the release commit now actually runs through CI for the first time. Previously the version-bump commit was pushed directly and never validated by `fast-tests` at all.

## Verification

1. `bash -n .github/scripts/release.sh` — syntax check.
2. `--dry-run` path is unchanged code, but re-run it anyway after editing to confirm the refactor didn't disturb the version-calculation/notes-generation logic it shares with the new PR-based tail.
3. Real end-to-end test: trigger `release.yml` for real (there are real commits since `v0.2.0` by the time this ships — this PR's own merge, at minimum, plus whatever else lands first) and confirm a release PR is opened, its `fast-tests` check is genuinely waited on and passes, it's merged, and the tag/release land on the correct (merge) commit SHA — not assumed, checked directly via `gh release view` and `git log` after the run completes.

## Self-review

- **Placeholders:** none — every step of the new flow is concrete (exact `gh` invocations, exact failure behavior).
- **Internal consistency:** explicitly distinguishes "bypass the review-count requirement" (fine, nothing else can satisfy it) from "bypass a failing check" (not fine, aborts instead) — the two are easy to conflate under "admin bypass" and this spec calls out the difference on purpose.
- **Scope:** one file (`.github/scripts/release.sh`), no changes to `release.yml`, no changes to branch protection (the whole point is working correctly *with* the protection added today, not loosening it).
- **Ambiguity:** none — this was root-caused by reading the actual failure log from the real triggered run, not guessed at.
