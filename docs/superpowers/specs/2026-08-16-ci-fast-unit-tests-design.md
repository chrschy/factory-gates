# factory-gates — CI for Fast Unit Tests

**Status:** approved
**Date:** 2026-08-16

## Why

No CI workflow exists in this repo — `.github/workflows/release.yml` is manual-only (`workflow_dispatch`). CLAUDE.md's branch protection table documents "Required status checks: none (no CI workflow yet)" as a known gap. Four test suites in this repo are fast, deterministic, and make no network or live-LLM calls, so they're safe to run automatically on every push/PR: `tests/release/test-version-calc.sh` and the three `tests/gate-quality/*/test-judge.sh` files. The backlog item that prompted this named only `test-version-calc.sh`, but since a CI workflow has to be created from scratch either way, wiring in all four now avoids redoing this work shortly after for the `test-judge.sh` suites — confirmed as the right scope during design discussion.

`tests/gate-routing/` and the live-LLM `run-trial.sh`/`run-all.sh` scripts under `tests/gate-quality/*/` stay manual-only, unchanged — real token cost and non-determinism, exactly as their own READMEs already state. Nothing about this spec touches them.

## Fix

**New file** `.github/workflows/ci.yml`:

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

Matches `release.yml`'s existing conventions: SHA-pinned `actions/checkout` with a version comment, `ubuntu-latest`. Triggers on push to `main` and on every pull request (any target branch, matching the "PRs only ever target `main`" reality of this repo without hardcoding it). All four scripts are already executable (`chmod +x`, verified) and run directly with no interpreter prefix needed, exactly as they're invoked in their own READMEs.

## Branch protection change

Per explicit decision during design: this becomes a **required** status check on `main`, not merely informational. This can't be set in the same PR that creates the workflow — GitHub requires a check to have actually reported at least once before its exact context name can be added to branch protection reliably. Sequencing:

1. Open the PR with `ci.yml`. The workflow runs on the PR itself (`pull_request` trigger) — confirms it passes for real before merge.
2. After merge, query the actual check name from a real commit on `main` (`gh api repos/chrschy/factory-gates/commits/<sha>/check-runs`) rather than assuming a name.
3. `PATCH` branch protection's `required_status_checks` to add that exact context, preserving every other existing protection setting (`required_pull_request_reviews`, `enforce_admins: false`, `required_linear_history: true`, etc. — verified via `gh api repos/chrschy/factory-gates/branches/main/protection` before editing, so nothing already in place gets silently dropped).

**Documentation:** CLAUDE.md's branch protection table row changes from "Required status checks: none (no CI workflow yet)" to naming the actual required check.

## Verification

1. All four scripts already verified passing locally before writing this spec (`test-version-calc.sh`: 29/29; the three `test-judge.sh`: 7/9/9 respectively, matching each suite's own documented count).
2. `actionlint` or `yamllint` if available locally, else manual YAML review — no GitHub Actions runner available locally, so the real test is the PR itself: opening it triggers the workflow for real, and its actual pass/fail status is checked before merge, not assumed.
3. Post-merge: confirm the required-status-check update via `gh api repos/chrschy/factory-gates/branches/main/protection` showing the new context present, and every pre-existing setting unchanged.

## Self-review

- **Placeholders:** none — exact workflow YAML given in full.
- **Internal consistency:** explicitly scopes out `tests/gate-routing/` and the live-LLM suites, naming the exact reason (cost/non-determinism) already documented elsewhere, so this doesn't contradict those suites' own "not run in CI" claims.
- **Scope:** one new workflow file, one branch-protection change (sequenced correctly, not assumed atomic), one CLAUDE.md doc line — nothing else touched.
- **Ambiguity:** the "which tests, informational-or-required" questions were both open design forks, resolved explicitly during the design conversation before this doc was written, not decided silently.
