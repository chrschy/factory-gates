# Fix architecture-gate's Open Questions Fabrication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the fabrication bug `tests/gate-quality/architecture-gate/` found in `architecture-gate`'s Open Questions section, and get before/after evidence that the fix helped, per `CLAUDE.md`'s "Skill Changes Require Evidence" rule.

**Architecture:** Two precise wording edits to `skills/architecture-gate/SKILL.md` (the document template's Open Questions placeholder, and self-review checklist item 6), then a real re-run of the existing `tests/gate-quality/architecture-gate/run-all.sh` suite as verification. No new files, no script changes.

**Tech Stack:** Markdown only; verification via the existing bash+jq+claude test suite.

## Global Constraints

- Exact old/new text for both edits is given verbatim below — this is a content change, not a design decision, so there is no room for paraphrasing.
- Scope is exactly these two edits in exactly this one file. No other section of `architecture-gate/SKILL.md`, no other gate's SKILL.md.
- Verification is a real run of `tests/gate-quality/architecture-gate/run-all.sh` (default 3 trials, real tokens, several minutes) — not a shortcut, not a smaller manual check.
- Baseline to compare against: PR #5's run, `{"trials": 3, "pass": 2, "fail": 1, "inconclusive": 0}`, where the one `fail` was specifically the fabricated Open Questions entry. A clean re-run doesn't prove the fix (the suite is non-deterministic, documented in its own README) — if a `fail` recurs, it must be checked to confirm it's a *different* issue, not the same one.

## File Structure

No new files. One file modified: `skills/architecture-gate/SKILL.md`.

---

### Task 1: Fix the wording, verify, PR

**Files:**
- Modify: `skills/architecture-gate/SKILL.md:31` (self-review checklist item 6)
- Modify: `skills/architecture-gate/SKILL.md:60` (document template's Open Questions placeholder)

**Interfaces:** none (content-only change; no other task depends on this one)

- [ ] **Step 1: Create the branch**

```bash
cd /home/christopher/PycharmProjects/factory-gates
git checkout main
git pull
git checkout -b fix/architecture-gate-open-questions
```

- [ ] **Step 2: Edit the document template's Open Questions placeholder (line 60)**

Find this exact line:
```
[Anything brainstorming's spec left ambiguous that architecture forced a decision on]
```

Replace it with:
```
[Only include an entry here if you can point to the specific spec section that was genuinely ambiguous — re-read it before writing this section to confirm. If the spec already committed to an answer, that is not an open question, even if architecture had to restate or elaborate on it. If nothing was left open, write "None — the spec fully specified this."]
```

- [ ] **Step 3: Edit self-review checklist item 6 (line 31)**

Find this exact line:
```
6. **Self-review:** any component with an undefined boundary? Any data model referenced but not specified? Any constraint implied by the product spec but missing here?
```

Replace it with:
```
6. **Self-review:** any component with an undefined boundary? Any data model referenced but not specified? Any constraint implied by the product spec but missing here? For each "Open questions" entry, re-read the spec section it cites — does the spec actually leave this open, or does it already commit to an answer? A fabricated open question is worse than an empty section.
```

- [ ] **Step 4: Verify both edits landed correctly**

```bash
grep -n "Only include an entry here if you can point to the specific spec section" skills/architecture-gate/SKILL.md
grep -n "A fabricated open question is worse than an empty section" skills/architecture-gate/SKILL.md
```

Expected: two matches, one per grep, at the lines you just edited (60 and 31 respectively — line numbers may shift slightly depending on exact edit mechanics, that's fine, just confirm both strings are present exactly once each).

- [ ] **Step 5: Commit**

```bash
git add skills/architecture-gate/SKILL.md
git commit -m "fix(architecture-gate): stop fabricating Open Questions entries not actually left open by the spec"
```

- [ ] **Step 6: Re-run the gate-quality suite as verification**

```bash
tests/gate-quality/architecture-gate/run-all.sh
```

Expected: takes several minutes (3 real trials, ~7 turns each plus judge calls), real token cost. Record the full summary JSON and, for any trial with `outcome: "fail"`, read that trial's `judge_output_file` (path is in its `result.json`) to see exactly what the judge flagged.

- [ ] **Step 7: Compare against baseline and report**

Compare this run's summary against PR #5's baseline (`{"trials": 3, "pass": 2, "fail": 1, "inconclusive": 0}`). If this run has zero fails, or a fail on a genuinely different issue than the fabricated Open Questions entry, the fix is supported. If a fail recurs on the *same* fabrication pattern (an Open Questions entry not traceable to a real spec ambiguity), the fix did not work — stop here and report BLOCKED with the new judge output, do not proceed to Step 8. Report the before/after comparison to your human partner either way, plainly, without editorializing beyond the numbers and the actual judge text.

- [ ] **Step 8: Push, open PR, human review gate, merge**

```bash
git push -u origin fix/architecture-gate-open-questions
```

Fill in the `<PASTE ...>` placeholder with Step 6/7's actual results before running this command.

```bash
gh pr create --title "fix(architecture-gate): stop fabricating Open Questions entries" --body "$(cat <<'EOF'
## Who is submitting this PR? (required)

| Field | Value |
|-------|-------|
| Your model + version | Claude Sonnet 5 |
| Harness + version | Claude Code |
| All plugins installed | superpowers |
| Human partner who reviewed this diff | [@chrschy](https://github.com/chrschy) |

## What problem are you trying to solve?

tests/gate-quality/architecture-gate/'s first run (PR #5) found that
architecture-gate can fabricate an "Open questions" entry -- claiming the
spec left something ambiguous when it had actually already committed to
an answer. Observed once in 3 trials: the skill claimed the spec left
deployment topology (one binary vs. two) as an unresolved aside, when the
spec stated it unambiguously twice.

## What does this PR change?

Two wording edits to skills/architecture-gate/SKILL.md: the Open
Questions template placeholder now requires re-reading the cited spec
section before including an entry, and self-review checklist item 6 adds
an explicit verification step for each Open Questions entry.

## Which gate does this touch?

architecture-gate. This is exactly the kind of HARD-GATE/checklist wording
change CLAUDE.md's "Skill Changes Require Evidence" rule is about.

## What alternatives did you consider?

Considered a broader rewrite of the self-review section, but scoped
narrowly to the actual observed failure (Open Questions fabrication) --
no evidence of a problem in the other self-review checks or other gates.

## Existing PRs
- [x] I have reviewed open AND closed PRs/issues for duplicates or prior art
- Related PRs/issues: none found

## Rigor
- [x] This change was tested adversarially, not just on the happy path
- [x] Ran tests/gate-quality/architecture-gate/run-all.sh before and after -- results:

Before (PR #5 baseline): {"trials": 3, "pass": 2, "fail": 1, "inconclusive": 0}
-- the 1 fail was the fabricated Open Questions entry described above.

After (this fix): <PASTE Step 6/7's actual summary JSON and fail-trial details, if any, here>

## Human review
- [ ] A human has reviewed the COMPLETE proposed diff before submission
EOF
)"
```

- [ ] **Step 9: Human review gate**

Stop here. Show the human partner the complete diff (`git diff main...fix/architecture-gate-open-questions`), the PR URL, and the before/after comparison. Do not proceed to Step 10 until they explicitly approve.

- [ ] **Step 10: Merge**

```bash
gh pr merge --squash --delete-branch --admin
```

- [ ] **Step 11: Verify**

```bash
git checkout main
git pull
grep -n "A fabricated open question is worse than an empty section" skills/architecture-gate/SKILL.md
```

Expected: one match, confirming the fix is live on `main`.

## Self-Review

1. **Spec coverage:** both wording edits from the spec are reproduced verbatim (Step 2, Step 3); verification against the real suite and the documented baseline (Step 6-7); PR/merge flow with the before/after evidence CLAUDE.md requires (Step 8-11).
2. **Placeholder scan:** one intentional, explicitly-flagged placeholder in Step 8 (`<PASTE Step 6/7's actual summary JSON...>`), same pattern as every prior plan in this repo — must be filled from real output before opening the PR. Step 7 also explicitly names the one placeholder-like branch point that isn't a literal text placeholder: what to do if the fix doesn't actually work (stop, report BLOCKED, don't merge a non-fix).
3. **Type consistency:** N/A — no code, no function signatures, a single markdown file edited twice with exact, non-conflicting text.
