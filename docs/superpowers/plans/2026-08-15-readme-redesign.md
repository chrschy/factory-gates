# README Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `README.md` with the exact new content from the design spec — presentation only, no factual changes.

**Architecture:** Single file, full-content replacement (the spec's version is the final text, not a description to reproduce from memory).

**Tech Stack:** markdown, Mermaid (rendered natively by GitHub), shields.io static badges.

## Global Constraints

- The new content is the exact text in `docs/superpowers/specs/2026-08-15-readme-redesign-design.md`'s "Full new `README.md` content" section — copy it verbatim, do not paraphrase or "improve" it further.
- Every factual claim in the current `README.md` (gate table rows, install commands, the 3-mechanism determinism table's exact measured numbers, the `CLAUDE.md` snippet text, credits) must still be present afterward, unchanged in substance.

## File Structure

No new files. One file replaced: `README.md`.

---

### Task 1: Replace README.md, verify, PR

**Files:**
- Modify: `README.md`

**Interfaces:** none

- [ ] **Step 1: Create the branch**

```bash
cd /home/christopher/PycharmProjects/factory-gates
git checkout main
git pull
git checkout -b docs/readme-redesign
```

- [ ] **Step 2: Replace `README.md`'s full content**

Copy the exact content from the "Full new `README.md` content" fenced block in `docs/superpowers/specs/2026-08-15-readme-redesign-design.md` verbatim into `README.md`, replacing the entire file.

- [ ] **Step 3: Verify the new presentational elements are present**

```bash
grep -c "img.shields.io" README.md
grep -c '```mermaid' README.md
grep -c "^## 🧩 Why" README.md
grep -c "^## 📦 Install" README.md
grep -c "^## ⚠️ Known limitation" README.md
grep -c "^## 🙏 Credits" README.md
grep -c "\[!WARNING\]" README.md
grep -c "\[!TIP\]" README.md
```

Expected: at least 1 for each (the badges line has 2 `img.shields.io` occurrences, everything else exactly 1).

- [ ] **Step 4: Verify no factual content was lost**

```bash
grep -c "architecture-gate.*Gate 2" README.md
grep -c "program-design-gate.*Gate 3" README.md
grep -c "vertical-slices-gate.*Gate 4" README.md
grep -c "/plugin install factory-gates@factory-gates-dev" README.md
grep -c "16 formal trials, 0 fails" README.md
grep -c "Software Factory Workflow" README.md
grep -c "Dex Horthy, HumanLayer" README.md
```

Expected: at least 1 for each (the install command appears twice).

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs(meta): redesign README presentation with badges, Mermaid diagram, and alert callouts"
```

- [ ] **Step 6: Push, open PR**

```bash
git push -u origin docs/readme-redesign
```

```bash
gh pr create --title "docs(meta): redesign README presentation" --body "$(cat <<'EOF'
## Who is submitting this PR? (required)

| Field | Value |
|-------|-------|
| Your model + version | Claude Sonnet 5 |
| Harness + version | Claude Code |
| All plugins installed | superpowers |
| Human partner who reviewed this diff | [@chrschy](https://github.com/chrschy) |

## What problem are you trying to solve?

The README's content was accurate but plainly formatted -- no visual
orientation for a first-time reader.

## What does this PR change?

Presentation only: a badges row (MIT license, requires-Superpowers -- both
real facts, no build-status or version badge since neither is backed by
real CI/a cut release yet), a Mermaid flowchart of the gate pipeline
distinguishing Superpowers' own skills from this plugin's additions,
sparing emoji markers on top-level section headers, and GitHub
[!WARNING]/[!TIP] alert callouts for the Known limitation section. No
factual content changed -- verified by direct diff against the prior
version.

## Which gate does this touch?

None -- documentation only.

## What alternatives did you consider?

Considered directly copying elements from the two reference READMEs
(charmbracelet/vhs, rbtsbg/emp-exp) named as style references, but neither
maps directly to a skills-plugin README (VHS leans on GIF demos, emp-exp
on academic directory-tree docs) -- adapted the transferable ideas
instead (see spec for the full reasoning).

## Existing PRs
- [x] I have reviewed open AND closed PRs/issues for duplicates or prior art
- Related PRs/issues: none found

## Rigor
- [x] N/A -- presentation-only documentation change, no behavior to test
      adversarially. Verified no factual content was lost via direct
      grep checks against every table row, command, and measured number
      in the prior version.

## Human review
- [ ] A human has reviewed the COMPLETE proposed diff before submission
EOF
)"
```

- [ ] **Step 7: Report to human partner**

Show the human partner the complete diff (`git diff main...docs/readme-redesign`) and the PR URL. Per standing instruction, do not merge — the human partner reviews manually.

## Self-Review

1. **Spec coverage:** the single task replaces the file, verifies both the new presentational elements and that no factual content was lost (two separate, explicit verification steps rather than one combined check), then PR.
2. **Placeholder scan:** none — the PR body has no `<PASTE ...>` placeholders this time, since there's no empirical data to report for a documentation-only change.
3. **Type consistency:** N/A — no code.
