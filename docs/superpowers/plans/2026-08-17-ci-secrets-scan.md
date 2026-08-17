# CI Secrets Scan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `secrets-scan` job to `.github/workflows/ci.yml` that runs gitleaks against every push to `main` and every pull request.

**Architecture:** One new job, parallel to the existing `fast-tests` job, sharing the workflow's existing triggers. No changes to `fast-tests` itself.

**Tech Stack:** GitHub Actions (YAML), `gitleaks/gitleaks-action@v3.0.0` (SHA-pinned).

## Global Constraints

- Pin `gitleaks/gitleaks-action` to the verified commit SHA `e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e` (tag `v3.0.0`), not a floating tag — matches this repo's existing `actions/checkout` pinning convention.
- No `GITLEAKS_LICENSE` secret — confirmed unnecessary for personal-account repos via the Action's own README.
- Do not add this as a required branch-protection status check in this PR — that's a deliberate post-merge follow-up, same sequencing as `fast-tests`' own required-check rollout.

---

### Task 1: Add the job, verify YAML, verify live on this PR

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:** none

- [ ] **Step 1: Add the `secrets-scan` job**

Append to `.github/workflows/ci.yml`, after the existing `fast-tests` job (same indentation level, as a sibling job under `jobs:`):

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

- [ ] **Step 2: Validate YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci(ci): add gitleaks secrets scan"
```

- [ ] **Step 4: Push, open PR**

```bash
git push -u origin chore/ci-secrets-scan
```

Open the PR with `gh pr create`, following this repo's established template: who's submitting, what problem (no secrets/credentials scan existed), what changed (new `secrets-scan` job, tool choice and licensing verified live against the GitHub API rather than assumed), which gate (none), alternatives considered (hand-rolled binary download vs. official Action -- Action chosen to avoid independently verifying a CLI checksum; PR-comments left on vs. disabled -- disabled for least-privilege, relying on check status alone like `fast-tests` already does), existing-PRs checkbox, rigor section citing the YAML validation and noting this PR's own `pull_request` trigger is the real live test, human-review checkbox unchecked. Note explicitly that making this a required status check is a deliberate post-merge follow-up, not part of this PR.

- [ ] **Step 5: Confirm the job actually runs and passes on the PR itself**

```bash
gh pr checks <PR-number>
```

Expected: both `fast-tests` and `secrets-scan` show as passing. This is the real verification -- if `secrets-scan` fails, read the actual log (`gh run view --log`) before assuming anything: a genuine finding needs to be handled directly (not suppressed), while an overly-broad rule match needs a targeted `.gitleaks.toml` allowlist entry, not a blanket disable of the check.

- [ ] **Step 6: Report to human partner**

Show the complete diff (`git diff main...chore/ci-secrets-scan`), the PR URL, and the live `gh pr checks` result confirming both jobs passed for real. Per standing instruction, do not merge.

## Self-Review

1. **Spec coverage:** the single task covers the job addition, YAML validation, PR, and live confirmation -- matches every part of the design spec. The required-status-check follow-up is explicitly named as out of scope for this plan, matching the spec's own deferral.
2. **Placeholder scan:** none -- exact YAML, exact SHA, exact commands.
3. **Type consistency:** the job name (`secrets-scan`) is identical between the workflow file, the plan's own verification steps, and the PR-body instructions.
