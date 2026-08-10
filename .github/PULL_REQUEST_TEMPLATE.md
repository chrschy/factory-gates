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
