# factory-gates — CI Secrets/Credentials Scan

**Status:** approved
**Date:** 2026-08-17

## Why

No automated check exists for accidentally-committed credentials or secrets. `.github/workflows/ci.yml` currently only runs the four fast unit-test suites (`fast-tests` job). This adds a dedicated scan.

## Fix

New job `secrets-scan` in `.github/workflows/ci.yml`, parallel to the existing `fast-tests` job, sharing the same workflow-level triggers (push to `main`, every pull request):

```yaml
  secrets-scan:
    runs-on: ubuntu-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0

      - name: Scan for secrets with gitleaks
        uses: gitleaks/gitleaks-action@e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e # v3.0.0
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITLEAKS_ENABLE_COMMENTS: "false"
```

**Tool choice:** gitleaks, via the official `gitleaks/gitleaks-action`, SHA-pinned exactly like this repo's existing `actions/checkout` usage — not a hand-rolled binary download, since the Action is the maintained, trusted distribution path and avoids needing to independently verify a CLI release checksum. Verified directly against the GitHub API (not assumed from memory) before writing this spec: latest release is `v3.0.0` at commit `e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e`.

**Licensing, verified not assumed:** `gitleaks-action`'s own README states `GITLEAKS_LICENSE` is "only required for Organizations, not personal accounts." `chrschy/factory-gates` is a personal-account repo, so no `GITLEAKS_LICENSE` secret is configured or referenced.

**`fetch-depth: 0`:** this job's own checkout step needs full history (gitleaks scans commit history, not just the working tree); the existing `fast-tests` job's shallow default checkout is untouched, since each job gets an independent runner/workspace.

**`GITLEAKS_ENABLE_COMMENTS: "false"`:** disables the Action's default PR-commenting behavior. Chosen for minimalism and least-privilege: PR comments would need `pull-requests: write` permission granted to the job beyond the default `contents: read`, and the check's own pass/fail status (visible the same way `fast-tests`' already is) is sufficient signal without it — consistent with how `fast-tests` itself has no separate reporting mechanism beyond its check status.

**Scope, matching what a diff-scoped run actually does:** the Action scans the diff on pull-request events and the new commit(s) on push events by default (event-aware, not a hand-rolled diff calculation) — not a full-history rescan on every run, which would be redundant and slow.

**Not a required status check in this PR.** Same sequencing constraint discovered when `fast-tests` was made required (PR #16/#17): a check can't be added to branch protection's `required_status_checks` until it has actually run and reported at least once. Making `secrets-scan` required is a deliberate follow-up after this PR merges and the job has run for real on `main`, not attempted here.

**Out of scope:** GitHub's native repo-level secret scanning feature (Settings → Code security) — complementary, zero-workflow-maintenance, but a separate one-click repo-settings decision, not something this PR changes.

## Verification

1. YAML validated as well-formed before commit (`python3 -c "import yaml; ..."`, matching how `ci.yml`'s original addition was verified).
2. This PR's own `pull_request` trigger is the real end-to-end test — the job runs for real before merge, checked via `gh pr checks`, not assumed to work from the YAML alone.
3. Confirm the job doesn't false-positive against this repo's own content before merge — a first real run against real repo history is the actual test; if it flags something, that's either a genuine finding (handle it directly) or a rule tuned too broadly (add a targeted `.gitleaks.toml` allowlist entry, not a blanket disable).

## Self-review

- **Placeholders:** none — exact YAML, exact verified SHA/version, exact licensing citation.
- **Internal consistency:** explicitly notes this job's checkout (`fetch-depth: 0`) doesn't affect `fast-tests`' separate, unmodified checkout step, since GitHub Actions jobs are independent.
- **Scope:** one new job in one existing file. No branch-protection change in this PR (explicitly deferred, matching precedent).
- **Ambiguity:** none — the two things that could have been guessed (Action version/SHA, licensing requirement) were both verified against live data before being written down, not assumed from training-time knowledge.
