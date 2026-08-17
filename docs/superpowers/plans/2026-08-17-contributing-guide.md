# CONTRIBUTING.md Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write `CONTRIBUTING.md`, closing the reference gap in `CLAUDE.md` and the README.

**Architecture:** Single new file, deliberately short, cross-referencing `CLAUDE.md`'s existing sections rather than duplicating them.

**Tech Stack:** Markdown.

## Global Constraints

- No changes to `CLAUDE.md` — its `CONTRIBUTING.md` reference already reads correctly once this file exists.
- Every cross-reference (section names, file paths) must be verified to actually exist, not assumed.

---

### Task 1: Write `CONTRIBUTING.md`, verify links, PR

**Files:**
- Create: `CONTRIBUTING.md`

**Interfaces:** none

- [ ] **Step 1: Write the file**

```markdown
# Contributing to factory-gates

## Before you start

Read `CLAUDE.md` fully — it's the authoritative process document for this
repo, for human and AI-agent contributors alike. This file is a short
entry point, not a substitute for it.

This repo is deliberately narrow in scope: three gate skills
(`architecture-gate`, `program-design-gate`, `vertical-slices-gate`),
their tests, and the tooling around them. Changes to Superpowers' own
files never belong here (see README "Why") — factory-gates stays
non-invasive by design. If your change is about Superpowers itself, it
belongs upstream.

## Reporting issues

Search existing issues and PRs, open and closed, before filing a new
one. Use the issue templates under `.github/ISSUE_TEMPLATE/` (bug report
or feature request).

## Development setup

```bash
git clone https://github.com/chrschy/factory-gates.git
cd factory-gates
```

Requires [Superpowers](https://github.com/obra/superpowers) already
installed. Install factory-gates itself from your local checkout so you
test your actual changes, not the last published release:

```
/plugin marketplace add .
/plugin install factory-gates@factory-gates
```

## Running tests

**Fast suite** (seconds, no network, run before every PR):

```bash
ruff check .
ruff format --check .
ty check
tests/release/test-version-calc.sh
tests/gate-quality/architecture-gate/test-judge.sh
tests/gate-quality/program-design-gate/test-judge.sh
tests/gate-quality/vertical-slices-gate/test-judge.sh
tests/gate-routing/test-common.sh
tests/outcome-benchmark/test-scoring.sh
tests/outcome-benchmark/test-execute.sh
```

These are exactly what `.github/workflows/ci.yml`'s `fast-tests` job
runs — same commands, same order.

**Live-LLM suites** (real tokens, real time, not run in CI): see each
suite's own README before running --
[`tests/gate-routing/`](tests/gate-routing/README.md),
[`tests/gate-quality/architecture-gate/`](tests/gate-quality/architecture-gate/README.md),
[`tests/gate-quality/program-design-gate/`](tests/gate-quality/program-design-gate/README.md),
[`tests/gate-quality/vertical-slices-gate/`](tests/gate-quality/vertical-slices-gate/README.md),
[`tests/outcome-benchmark/`](tests/outcome-benchmark/README.md).

## Making changes

See `CLAUDE.md`'s "Git & Branching" section for branch naming, commit
format, and the one-problem-per-PR rule. Fill out
`.github/PULL_REQUEST_TEMPLATE.md` completely when opening a PR --
real, specific answers, not placeholders.

Both CI checks (`fast-tests`, `secrets-scan`) must pass, and a human
maintainer must review the complete diff before merge.

## Changing a gate skill

`architecture-gate`, `program-design-gate`, and `vertical-slices-gate`
are behavior-shaping content, not documentation. See `CLAUDE.md`'s
"Skill Changes Require Evidence" section before touching any of their
`<HARD-GATE>` blocks, checklists, or trigger descriptions -- this is the
one place a casual wording change can silently break routing.

## Cutting a release

Maintainer-only. See `CLAUDE.md`'s "Cutting a release" section.
```

- [ ] **Step 2: Verify every cross-reference actually exists**

```bash
grep -n "^## Git & Branching\|^## Skill Changes Require Evidence\|^### Cutting a release" CLAUDE.md
ls .github/ISSUE_TEMPLATE/
ls .github/PULL_REQUEST_TEMPLATE.md
ls tests/gate-routing/README.md tests/gate-quality/architecture-gate/README.md tests/gate-quality/program-design-gate/README.md tests/gate-quality/vertical-slices-gate/README.md tests/outcome-benchmark/README.md
ls tests/release/test-version-calc.sh tests/gate-quality/architecture-gate/test-judge.sh tests/gate-quality/program-design-gate/test-judge.sh tests/gate-quality/vertical-slices-gate/test-judge.sh tests/gate-routing/test-common.sh tests/outcome-benchmark/test-scoring.sh tests/outcome-benchmark/test-execute.sh
```

Expected: every reference resolves to a real file/section. Fix any mismatch before committing rather than leaving a broken pointer in a contributor-facing doc.

- [ ] **Step 3: Confirm the fast-test list matches `ci.yml` exactly**

```bash
diff <(grep -A1 "run:" .github/workflows/ci.yml | grep "run:" | sed 's/.*run: //') <(grep -E "^(ruff|ty|tests/)" CONTRIBUTING.md)
```

Expected: no meaningful diff (ordering/exact formatting may differ slightly, but the same commands must all be present) -- if `ci.yml` changes in the future without this file being updated, this exact check is what would catch the drift on a future PR touching either file.

- [ ] **Step 4: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs(meta): add CONTRIBUTING.md"
```

- [ ] **Step 5: Push, open PR**

```bash
git push -u origin docs/contributing-guide
```

Open the PR with `gh pr create`, following this repo's established template: who's submitting, what problem (referenced from CLAUDE.md/README but never written), what changed, which gate (none), alternatives considered (duplicate CLAUDE.md's content vs. cross-reference it -- cross-reference chosen to avoid drift), existing-PRs checkbox, rigor section citing the link-verification step, human-review checkbox unchecked.

- [ ] **Step 6: Confirm CI passes for real**

```bash
gh pr checks <PR-number>
```

- [ ] **Step 7: Report to human partner**

Show the complete diff and the PR URL. Per standing instruction, do not merge.

## Self-Review

1. **Spec coverage:** single task covers the file, link verification, and PR -- matches the spec's single content section.
2. **Placeholder scan:** none -- full file content given verbatim.
3. **Type consistency:** N/A -- documentation only.
