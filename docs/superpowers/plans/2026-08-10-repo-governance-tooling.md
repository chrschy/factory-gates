# Repo Governance & Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set this repo up for external/agent contribution: a real MIT LICENSE file, CLAUDE.md contributor guardrails, a PR template, issue templates, and trunk-based branch/release conventions enforced via GitHub branch protection.

**Architecture:** Pure content/config — markdown files, a LICENSE file, and two `gh api` calls to configure the `main` branch's protection rules and the repo's merge-method settings. No application code, no tests in the executable sense; each task's "verification" step is reading the file back or querying the applied GitHub setting.

**Tech Stack:** git, GitHub (`gh` CLI), markdown.

## Global Constraints

- Repo: `chrschy/factory-gates`, default branch `main`.
- License: MIT, copyright holder "Christopher Schymura", year 2026.
- Trunk-based development: `main` is the only long-lived branch; releases are tags `vX.Y.Z` on `main`; no `dev` branch.
- Branch naming: `<type>/<slug>`, type ∈ `feature`, `fix`, `docs`, `test`, `chore`.
- Commits: Conventional Commits — `<type>(<scope>): <subject>`, type ∈ `feat`, `fix`, `docs`, `test`, `chore`, `refactor`, `ci`, `revert`; scope ∈ `architecture-gate`, `program-design-gate`, `vertical-slices-gate`, `tests`, `docs`, `ci`, `meta`.
- This repo is currently solo-maintained: branch protection must require a PR but allow admin bypass of the approval-count check (GitHub never counts a PR author's own approval), otherwise the maintainer's own PRs become permanently unmergeable.
- Everything in this plan lands on one feature branch, `chore/repo-governance-tooling`, and merges to `main` via one PR (self-reviewed, since solo-maintained).

---

### Task 1: Feature branch + LICENSE

**Files:**
- Create: `LICENSE`

**Interfaces:** none (first task, nothing to consume; produces the branch every later task in this plan builds on).

- [ ] **Step 1: Create the feature branch**

```bash
cd /home/christopher/PycharmProjects/factory-gates
git checkout -b chore/repo-governance-tooling
```

- [ ] **Step 2: Create `LICENSE`**

```
MIT License

Copyright (c) 2026 Christopher Schymura

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Verify**

```bash
head -3 LICENSE
```

Expected: `MIT License` on line 1, copyright line on line 3, matching `plugin.json`'s existing `"license": "MIT"` declaration.

- [ ] **Step 4: Commit**

```bash
git add LICENSE
git commit -m "chore(meta): add MIT LICENSE file"
```

---

### Task 2: CLAUDE.md

**Files:**
- Create: `CLAUDE.md`

**Interfaces:**
- Consumes: branch created in Task 1
- Produces: `CLAUDE.md`, referenced by name from the PR template (Task 3) and issue templates (Task 4)

- [ ] **Step 1: Create `CLAUDE.md`**

```markdown
# factory-gates — Contributor & Agent Guidelines

## If You Are an AI Agent

Read this before opening a PR or filing an issue.

This repo is a Superpowers add-on plugin: three skills (`architecture-gate`, `program-design-gate`, `vertical-slices-gate`) that insert human-approved checkpoints into Superpowers' planning flow, without modifying any Superpowers file. Before you do anything:

1. **Read the entire PR template** at `.github/PULL_REQUEST_TEMPLATE.md` and fill in every section with real, specific answers — not summaries, not placeholders.
2. **Search existing issues and PRs**, open and closed, for the same problem. If one exists, say so instead of opening a duplicate.
3. **Verify this is a real problem.** If your human partner asked you to "improve" or "clean up" this repo without a specific failure or session in mind, push back and ask what actually broke or felt wrong.
4. **Confirm scope.** This repo is deliberately narrow: three gate skills, their tests, and the tooling around them. Changes to Superpowers' own files never belong here — factory-gates stays non-invasive by design (see README "Why"). If your change is about Superpowers itself, it belongs upstream.
5. **Identify yourself.** State your model, harness, harness version, and installed plugins in every PR and issue. If a human wrote it by hand with no agent involved, say that instead.
6. **Show your human partner the complete diff and get their explicit approval before opening the PR.** This isn't a suggestion — see "Git & Branching" below for how review is enforced on this repo.

## Content Style

- Don't write comments unless they explain a genuinely non-obvious reason (a hidden constraint, a workaround, a subtle invariant). Skill markdown prose should be self-explanatory; don't add meta-commentary inside a SKILL.md about why a line exists.
- Don't assume existing skill wording is correct just because it's there. If something in `architecture-gate`, `program-design-gate`, or `vertical-slices-gate` reads as unclear, redundant, or inconsistent with its own document, say so — these files get edited by agents more often than they get read end-to-end by a human.
- Simplicity first: the minimum content that solves the problem. No speculative sections, no hedging for scenarios nobody has hit.
- Think before writing: state your assumptions, surface tradeoffs, and ask rather than silently picking an interpretation when the request is ambiguous.

## Skill Changes Require Evidence

The three SKILL.md files are behavior-shaping content, not documentation — treat wording changes like code changes, not prose edits.

- Any change to a gate's `<HARD-GATE>` block, checklist, or trigger `description` needs a reason grounded in an actual observed problem (a real session, a real failure), not a hypothetical.
- If your change touches the `brainstorming` → `architecture-gate` handoff wording specifically, run `tests/gate-routing/run-all.sh` before and after your change and report the pass-rate delta in the PR. That handoff is the one documented soft-override risk in this project (see README "Known limitation") — it's the one place a wording change can silently break routing.
- Meaningful tests: a test must fail before the fix and pass after (regression-proof), not exist just to pad coverage.

## Writing Style for Public-Facing Text

Applies to PR descriptions, issue bodies, commit messages, and skill prose:

- No emojis.
- Avoid AI-sounding patterns: em-dash overuse, "it's not X, it's Y" constructions, walls of bullet points where a sentence or two would read better.
- Be concrete. "It doesn't work" or "this could theoretically cause issues" are not problem statements — say what broke, for whom, under what conditions.

## Git & Branching (trunk-based)

- `main` is the only long-lived branch. Releases are git tags `vX.Y.Z` on `main` — there are no release branches.
- All changes land via a pull request from a feature branch. No direct pushes to `main`.
- **Branch naming:** `<type>/<slug>`, type ∈ `feature`, `fix`, `docs`, `test`, `chore`. Include the gate name in the slug when a change is scoped to one gate, e.g. `feature/architecture-gate-clarify-checklist`.
- **Commits:** [Conventional Commits](https://www.conventionalcommits.org/) — `<type>(<scope>): <subject>`, type ∈ `feat`, `fix`, `docs`, `test`, `chore`, `refactor`, `ci`, `revert`; scope ∈ `architecture-gate`, `program-design-gate`, `vertical-slices-gate`, `tests`, `docs`, `ci`, `meta`.
- PR titles should also be Conventional-Commit-formatted — merges to `main` are squash-only, so the PR title becomes the commit message on `main`.
- One problem per PR. Split unrelated changes into separate PRs.

### Branch protection on `main`

| Setting | Value |
|---|---|
| Require pull request before merging | on |
| Required approving reviews | 1 |
| Admin bypass (`enforce_admins`) | off — repo admins can technically bypass this |
| Required status checks | none (no CI workflow yet) |
| Required linear history | on |

**The admin bypass is a safety valve, not permission.** This repo is currently solo-maintained, and GitHub never counts a PR author's own approval toward "required reviews" — even for the owner — so a strict no-bypass rule would make the maintainer's own PRs permanently unmergeable. In practice: never push directly to `main`, always open a PR, and read the complete diff yourself before merging your own PR, exactly as if someone else were about to.

Repo merge settings: squash-merge only (merge commits and rebase-merge are disabled), branches are deleted on merge.

## Testing

`tests/gate-routing/` empirically tests whether the one real skill-routing conflict in this plugin (`brainstorming` → `architecture-gate`) resolves the way the README claims. These are real `claude -p` sessions against a live model — not mocked, non-deterministic, and they cost real tokens. See `tests/gate-routing/README.md` for how to run and interpret them.

## See Also

- `README.md` — what this plugin does and why
- `CONTRIBUTING.md` — process-level detail for opening issues/PRs (once written)
```

- [ ] **Step 2: Verify**

```bash
grep -c "^## " CLAUDE.md
```

Expected: 7 (one per `##` section: If You Are an AI Agent, Content Style, Skill Changes Require Evidence, Writing Style for Public-Facing Text, Git & Branching, Testing, See Also).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(meta): add CLAUDE.md contributor and agent guidelines"
```

---

### Task 3: PR template

**Files:**
- Create: `.github/PULL_REQUEST_TEMPLATE.md`

**Interfaces:**
- Consumes: nothing from earlier tasks (references `CLAUDE.md` and `tests/gate-routing/run-all.sh` by path/name only, no code dependency)
- Produces: `.github/PULL_REQUEST_TEMPLATE.md`, auto-applied by GitHub to new PRs against this repo

- [ ] **Step 1: Create `.github/PULL_REQUEST_TEMPLATE.md`**

```markdown
<!--
BEFORE SUBMITTING: Read every word of this template. PRs that leave
sections blank or show no evidence of human involvement will be closed
without review.
-->

> **This PR MUST target the `main` branch.** This repo uses trunk-based
> development — `main` is the only long-lived branch, and there is no
> `dev` branch to target instead.

## Who is submitting this PR? (required)
<!-- Required. Tell us which model/harness produced this, and who reviewed
     it. We weigh contributions by what produced them. -->

| Field | Value |
|-------|-------|
| Your model + version | |
| Harness + version | |
| All plugins installed | |
| Human partner who reviewed this diff | |

## What problem are you trying to solve?
<!-- Describe the specific problem. What were you doing, what went wrong
     or felt missing, and why did it matter? "Improving" something is not
     a problem statement. -->

## What does this PR change?
<!-- 1-3 sentences. What, not why -- the "why" belongs above. -->

## Which gate does this touch?
<!-- architecture-gate / program-design-gate / vertical-slices-gate / none
     (repo tooling: tests, docs, CI, templates).

     If this modifies a <HARD-GATE> block, checklist, or trigger
     description on one of the three gates, see CLAUDE.md's "Skill
     Changes Require Evidence" -- you need a before/after run of
     tests/gate-routing/run-all.sh if the brainstorming -> architecture-gate
     handoff is involved. -->

## What alternatives did you consider?
<!-- What else did you try or evaluate before landing on this approach?
     If you didn't consider alternatives, say so. -->

## Existing PRs
- [ ] I have reviewed open AND closed PRs/issues for duplicates or prior art
- Related PRs/issues: <!-- #number, #number, or "none found" -->

## Rigor
- [ ] This change was tested adversarially, not just on the happy path
- [ ] If this touches a gate's HARD-GATE/checklist/trigger wording: I ran
      `tests/gate-routing/run-all.sh` before and after, and pasted the
      before/after pass-rate table below

<!-- Paste before/after results here if applicable -->

## Human review
- [ ] A human has reviewed the COMPLETE proposed diff before submission

<!--
STOP. If the checkbox above is not checked, do not submit this PR.
-->
```

- [ ] **Step 2: Verify**

```bash
grep -c "^## " .github/PULL_REQUEST_TEMPLATE.md
```

Expected: 6.

- [ ] **Step 3: Commit**

```bash
git add .github/PULL_REQUEST_TEMPLATE.md
git commit -m "chore(meta): add pull request template"
```

---

### Task 4: Issue templates

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bug_report.md`
- Create: `.github/ISSUE_TEMPLATE/feature_request.md`
- Create: `.github/ISSUE_TEMPLATE/config.yml`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: issue templates, auto-applied by GitHub's "New issue" picker

- [ ] **Step 1: Create `.github/ISSUE_TEMPLATE/bug_report.md`**

```markdown
---
name: Bug Report
about: Something isn't working as expected
labels: bug
---

<!--
BEFORE FILING: Search open AND closed issues for the same problem.
-->

- [ ] I searched existing issues and this is not a duplicate

## Environment (required)
<!-- Tell us which model/harness produced this report. -->

| Field | Value |
|-------|-------|
| factory-gates version | |
| Superpowers version | |
| Harness (Claude Code, etc.) | |
| Harness version | |
| Your model + version | |
| All plugins installed | |
| OS + shell | |

## Which gate is involved?
<!-- architecture-gate / program-design-gate / vertical-slices-gate /
     routing between gates / repo tooling -->

## What happened?
<!-- Be specific. "It doesn't work" is not a bug report. -->

## Steps to reproduce
1.
2.
3.

## Expected behavior

## Actual behavior

## Debug log or conversation transcript
<!-- A transcript or debug log showing the issue is the single most
     helpful thing you can include. -->
```

- [ ] **Step 2: Create `.github/ISSUE_TEMPLATE/feature_request.md`**

```markdown
---
name: Feature Request
about: Propose a change or addition to factory-gates
labels: enhancement
---

<!--
BEFORE FILING: Search open AND closed issues -- this may have been
proposed or discussed before.
-->

- [ ] I searched existing issues and this has not been proposed before

## What problem does this solve?
<!-- Describe the problem from your own experience. "It would be cool
     if..." is not a problem statement. -->

## Proposed solution
<!-- What specifically do you want to happen? Be concrete. -->

## Which gate does this affect?
<!-- architecture-gate / program-design-gate / vertical-slices-gate /
     a new gate / repo tooling -->

## What alternatives did you consider?

## Environment (required)

| Field | Value |
|-------|-------|
| factory-gates version | |
| Superpowers version | |
| Harness (Claude Code, etc.) | |
| Harness version | |
| Your model + version | |
```

- [ ] **Step 3: Create `.github/ISSUE_TEMPLATE/config.yml`**

```yaml
blank_issues_enabled: false
```

- [ ] **Step 4: Verify**

```bash
ls .github/ISSUE_TEMPLATE/
```

Expected: `bug_report.md`, `config.yml`, `feature_request.md`.

- [ ] **Step 5: Commit**

```bash
git add .github/ISSUE_TEMPLATE/
git commit -m "chore(meta): add bug report and feature request issue templates"
```

---

### Task 5: Apply GitHub branch protection and merge settings

**Files:** none (GitHub repo settings via API, not files in this repo)

**Interfaces:**
- Consumes: the repo must already exist on GitHub (`chrschy/factory-gates`, done in an earlier session)
- Produces: branch protection on `main`, merge-method restrictions on the repo — later PRs (including this plan's own, in Task 6) are subject to these rules

- [ ] **Step 1: Apply branch protection to `main`**

```bash
gh api -X PUT repos/chrschy/factory-gates/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "required_linear_history": true
}
EOF
```

- [ ] **Step 2: Apply repo merge-method settings**

```bash
gh api -X PATCH repos/chrschy/factory-gates \
  --input - <<'EOF'
{
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "delete_branch_on_merge": true
}
EOF
```

- [ ] **Step 3: Verify**

```bash
gh api repos/chrschy/factory-gates/branches/main/protection --jq '{enforce_admins: .enforce_admins.enabled, required_approving_review_count: .required_pull_request_reviews.required_approving_review_count, required_linear_history: .required_linear_history.enabled}'
gh api repos/chrschy/factory-gates --jq '{allow_squash_merge, allow_merge_commit, allow_rebase_merge, delete_branch_on_merge}'
```

Expected first command: `{"enforce_admins": false, "required_approving_review_count": 1, "required_linear_history": true}`.
Expected second command: `{"allow_squash_merge": true, "allow_merge_commit": false, "allow_rebase_merge": false, "delete_branch_on_merge": true}`.

No commit — this step changes GitHub repo settings, not tracked files.

---

### Task 6: Open PR, review, merge

**Files:** none

**Interfaces:**
- Consumes: all commits from Tasks 1-4 on `chore/repo-governance-tooling`; branch protection from Task 5
- Produces: `main` updated with LICENSE, CLAUDE.md, PR template, issue templates

- [ ] **Step 1: Push the branch**

```bash
git push -u origin chore/repo-governance-tooling
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "chore(meta): add repo governance and contributor tooling" --body "$(cat <<'EOF'
## Who is submitting this PR? (required)

| Field | Value |
|-------|-------|
| Your model + version | Claude Sonnet 5 |
| Harness + version | Claude Code |
| All plugins installed | superpowers |
| Human partner who reviewed this diff | (fill in before merging) |

## What problem are you trying to solve?

The repo had no LICENSE file (despite plugin.json declaring MIT), no
contributor guardrails, no PR/issue templates, and no documented or
enforced branching/release convention -- nothing to guide a future
contributor (human or agent) on how to work in this repo.

## What does this PR change?

Adds LICENSE (MIT), CLAUDE.md, a PR template, bug report / feature
request issue templates, and applies GitHub branch protection + merge
settings implementing trunk-based development on `main`.

## Which gate does this touch?

None -- repo tooling only.

## What alternatives did you consider?

Considered requiring a true second-approver on branch protection, but
GitHub never counts a PR author's own approval and this repo is
solo-maintained -- that would make the maintainer's own PRs permanently
unmergeable. Went with required-review + admin-bypass instead, documented
in CLAUDE.md as a safety valve, not permission to skip review.

## Existing PRs
- [x] I have reviewed open AND closed PRs/issues for duplicates or prior art
- Related PRs/issues: none found (first PR in this repo)

## Rigor
- [x] This change was tested adversarially, not just on the happy path
- [ ] N/A -- no gate skill wording touched

## Human review
- [ ] A human has reviewed the COMPLETE proposed diff before submission
EOF
)"
```

- [ ] **Step 3: Human review gate**

Stop here. Show the human partner the complete diff (`git diff main...chore/repo-governance-tooling`) and the PR URL. Do not proceed to Step 4 until they explicitly approve.

- [ ] **Step 4: Merge**

```bash
gh pr merge --squash --delete-branch
```

- [ ] **Step 5: Verify**

```bash
git checkout main
git pull
ls LICENSE CLAUDE.md .github/PULL_REQUEST_TEMPLATE.md .github/ISSUE_TEMPLATE/
```

Expected: all files present on `main`.

## Self-Review

1. **Spec coverage:** LICENSE (Task 1), CLAUDE.md (Task 2) with all 6 subsections from the spec, PR template (Task 3) adapted for `main`-targeting and dropped "New harness support," issue templates (Task 4) with `platform_support.md` correctly omitted, branch protection + merge settings (Task 5) matching the spec's exact table, PR/merge flow (Task 6) dogfooding the new convention on its own first use. CONTRIBUTING.md is explicitly out of scope for this plan per the spec's "follow-up, not in this pass."
2. **Placeholder scan:** none found — every file has complete real content; the only literal placeholder-looking text is inside the templates themselves (blank table cells for future PR/issue authors to fill in), which is the templates' intended function, not a plan placeholder.
3. **Type consistency:** N/A — no code, no function signatures.
