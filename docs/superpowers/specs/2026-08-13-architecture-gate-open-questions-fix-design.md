# factory-gates — Fix architecture-gate's Open Questions Fabrication

**Status:** approved
**Date:** 2026-08-13

## Why

`tests/gate-quality/architecture-gate/`'s first real run (PR #5) found a genuine bug in `architecture-gate` itself: on 1 of 3 trials, the judge caught the skill fabricating an "Open questions" entry — claiming the spec left the deployment topology (one binary vs. two) "as an aside without committing to one," when the spec had actually stated it unambiguously twice (in both its Architecture and Deployment sections). The rest of that trial's document was solid; this was isolated to the Open Questions section specifically.

## Root cause

The document template's Open Questions placeholder — `[Anything brainstorming's spec left ambiguous that architecture forced a decision on]` — and self-review checklist item 6 give no instruction to *verify* a claimed ambiguity against the actual spec text before writing it. The wording invites inference ("what might have been ambiguous") rather than citation ("what specifically was ambiguous, per this exact spec section"), which is exactly the gap that produces a fabricated entry.

## Fix

Two wording changes in `skills/architecture-gate/SKILL.md`, nothing else — narrow and evidence-grounded per `CLAUDE.md`'s "Skill Changes Require Evidence" rule. Not touching component-boundary/data-model/constraint checks (no evidence of a problem there — the rest of trial 3 and both other trials passed clean) and not touching any other gate (no evidence there either).

**1. Document template's "Open questions" section**, from:
```
## Open questions the product spec left open
[Anything brainstorming's spec left ambiguous that architecture forced a decision on]
```
to:
```
## Open questions the product spec left open
[Only include an entry here if you can point to the specific spec section that was genuinely ambiguous — re-read it before writing this section to confirm. If the spec already committed to an answer, that is not an open question, even if architecture had to restate or elaborate on it. If nothing was left open, write "None — the spec fully specified this."]
```

**2. Self-review checklist item 6**, appending one sentence, from:
```
6. **Self-review:** any component with an undefined boundary? Any data model referenced but not specified? Any constraint implied by the product spec but missing here?
```
to:
```
6. **Self-review:** any component with an undefined boundary? Any data model referenced but not specified? Any constraint implied by the product spec but missing here? For each "Open questions" entry, re-read the spec section it cites — does the spec actually leave this open, or does it already commit to an answer? A fabricated open question is worse than an empty section.
```

## Verification

Re-run `tests/gate-quality/architecture-gate/run-all.sh` (default 3 trials) after the fix and compare against PR #5's baseline (`{"trials": 3, "pass": 2, "fail": 1, "inconclusive": 0}`). Since this suite is inherently non-deterministic (documented in its own README), a single clean run doesn't prove the fix — but a fabricated Open Questions entry specifically should not recur, and any `fail` on the re-run should be checked to confirm it's a *different* issue, not a regression of this one.

## Self-review

- **Placeholders:** none — both wording changes are the exact final text, not a description of what to write.
- **Internal consistency:** the fix targets exactly the failure mode observed (fabricated citation of spec ambiguity), not a broader rewrite of the checklist.
- **Scope:** deliberately narrow — one skill, two sentences, grounded in one specific, reproduced finding.
- **Ambiguity:** none — this is a direct, evidence-driven fix with no design alternatives worth presenting.
