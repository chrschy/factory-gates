# CI for Fast Unit Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a CI workflow that runs the four fast, deterministic unit-test suites in this repo on every push to `main` and every pull request, then make it a required status check on `main`'s branch protection.

**Architecture:** One new GitHub Actions workflow file, `.github/workflows/ci.yml`, matching `release.yml`'s existing conventions (SHA-pinned actions, `ubuntu-latest`). One branch-protection update via `gh api`, sequenced after the workflow has run for real at least once. One CLAUDE.md doc update.

**Tech Stack:** GitHub Actions (YAML), bash.

## Global Constraints

- Only the four fast/deterministic suites run in CI: `tests/release/test-version-calc.sh`, `tests/gate-quality/architecture-gate/test-judge.sh`, `tests/gate-quality/program-design-gate/test-judge.sh`, `tests/gate-quality/vertical-slices-gate/test-judge.sh`. `tests/gate-routing/` and every `run-trial.sh`/`run-all.sh` live-LLM script stay manual-only — do not add them to this workflow.
- Pin `actions/checkout` to the same SHA + version comment already used in `release.yml` (`3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`), not a floating tag.
- The branch-protection update must preserve every existing setting (`required_pull_request_reviews`, `enforce_admins: false`, `required_linear_history: true`, `allow_force_pushes: false`, `allow_deletions: false`) — read the current protection config before writing, never blind-overwrite.

---

### Task 1: Create the CI workflow and verify locally

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:** none

- [ ] **Step 1: Create the workflow file**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  fast-tests:
    runs-on: ubuntu-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Run release version-calc tests
        run: tests/release/test-version-calc.sh

      - name: Run architecture-gate judge unit tests
        run: tests/gate-quality/architecture-gate/test-judge.sh

      - name: Run program-design-gate judge unit tests
        run: tests/gate-quality/program-design-gate/test-judge.sh

      - name: Run vertical-slices-gate judge unit tests
        run: tests/gate-quality/vertical-slices-gate/test-judge.sh
```

- [ ] **Step 2: Verify the four scripts are executable and pass locally, exactly as CI will run them**

```bash
tests/release/test-version-calc.sh
tests/gate-quality/architecture-gate/test-judge.sh
tests/gate-quality/program-design-gate/test-judge.sh
tests/gate-quality/vertical-slices-gate/test-judge.sh
```

Expected: each prints `Passed: <N>, Failed: 0` and exits 0 (29/0, 7/0, 9/0, 9/0 respectively). If any script isn't directly executable (missing `+x` or shebang), `chmod +x` it and re-verify — CI runs these the same way, with no interpreter prefix.

- [ ] **Step 3: Validate the YAML is well-formed**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`. (No GitHub Actions runner available locally — the real end-to-end test happens when this PR opens and the workflow actually runs, checked in Task 3.)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci(ci): add fast unit test workflow"
```

---

### Task 2: Update CLAUDE.md's branch protection table

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:** none

- [ ] **Step 1: Update the branch protection table row**

Find, in the "Branch protection on `main`" table:

```
| Required status checks | none (no CI workflow yet) |
```

Replace with:

```
| Required status checks | `CI / fast-tests` (added once `.github/workflows/ci.yml` first runs on `main` — see below) |
```

- [ ] **Step 2: Add a short note after the table** (the exact required-check context name is only known after the workflow's first real run, so this note points at how to find/update it rather than asserting a name that hasn't been confirmed yet):

```markdown

The exact required check name is set via branch protection once
`.github/workflows/ci.yml` has run at least once for real (GitHub
requires a check to have reported before its context can be added
reliably) — see `docs/superpowers/specs/2026-08-16-ci-fast-unit-tests-design.md`
for the sequencing.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(ci): note CI workflow in branch protection table"
```

---

### Task 3: Push, open PR, verify the workflow runs for real, report

**Files:** none (git/GitHub operations only)

**Interfaces:** none

- [ ] **Step 1: Push and open the PR**

```bash
git push -u origin chore/ci-fast-unit-tests
```

Open the PR with `gh pr create`, following this repo's established template: who's submitting, what problem (no CI workflow existed at all), what changed (new `ci.yml` running the four fast suites, plus the CLAUDE.md doc update), which gate (none — infra only), alternatives considered (scope: only `test-version-calc.sh` as literally named in the backlog vs. all four fast suites — broader scope chosen since the workflow has to be created either way), existing-PRs checkbox, rigor section citing local verification, human-review checkbox unchecked. Note explicitly in the PR body that the required-status-check branch-protection update happens as a separate step after merge (Task 3, Step 3 below), not in this PR.

- [ ] **Step 2: Confirm the workflow actually runs and passes on the PR itself**

```bash
gh pr checks <PR-number>
```

Expected: the `CI / fast-tests` check (or whatever its actual reported name is) shows as passing. This is the real end-to-end verification this plan has been building toward — if it fails, read the actual GitHub Actions log (`gh run view --log`) and fix before proceeding; do not merge on a red check.

- [ ] **Step 3: Report to human partner**

Show the complete diff (`git diff main...chore/ci-fast-unit-tests`), the PR URL, and the live `gh pr checks` result confirming the workflow passed for real. Per standing instruction, do not merge — the human partner reviews manually.

## Post-merge follow-up (not part of this PR — do only after merge, and only if the human partner asks to proceed)

Once merged and the workflow has run at least once on `main` (the `push` trigger fires on merge automatically):

1. Get the real check name: `gh api repos/chrschy/factory-gates/commits/$(git rev-parse main)/check-runs --jq '.check_runs[].name'`
2. Read current protection: `gh api repos/chrschy/factory-gates/branches/main/protection` — note every existing field.
3. `PATCH` branch protection to add `required_status_checks: {strict: false, contexts: ["<real name from step 1>"]}` (or the modern `checks` array form, whichever the API expects), preserving every other field read in step 2 unchanged.
4. Re-read protection and confirm the new check is present and nothing else changed.
5. Update CLAUDE.md's note from Task 2 with the confirmed real check name, in a small follow-up commit.

This is listed here so it isn't lost, but is explicitly sequenced after this PR merges — it cannot happen inside this PR's own branch/commits.

## Self-Review

1. **Spec coverage:** Task 1 covers the workflow file and local verification; Task 2 covers the doc update; Task 3 covers PR + live confirmation. The branch-protection change itself is explicitly called out as a post-merge follow-up, matching the spec's own sequencing constraint (can't be set before the check has reported for real) rather than being silently dropped.
2. **Placeholder scan:** none in the PR-scoped tasks — the workflow YAML, doc wording, and commands are all exact. The post-merge section's `<real name from step 1>` is a deliberate placeholder for a value that is only knowable after the workflow's first real run on `main`, not a plan-writing gap.
3. **Type consistency:** the workflow file name (`ci.yml`), job id (`fast-tests`), and every doc reference to "CI / fast-tests" are consistent throughout.
