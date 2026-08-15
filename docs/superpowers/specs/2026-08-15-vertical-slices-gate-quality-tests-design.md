# factory-gates — Vertical Slices Gate Quality Tests

**Status:** approved
**Date:** 2026-08-15

## Why

`architecture-gate` and `program-design-gate` both have quality suites that judge the document each gate produces. `vertical-slices-gate` — Gate 4, the last one — was explicitly deferred when `program-design-gate`'s suite was built, because it produces no persisted document. Its entire output is conversational: a turn where it summarizes slice order, flags coordination/intermediate-test risk, and asks for explicit confirmation before execution starts. This spec builds that suite, judging a conversation excerpt instead of a file.

## Part A — New shared helper: `extract_assistant_text`

Added to `tests/gate-routing/lib/common.sh` (already sourced by every `gate-quality` suite for `run_turn`/`skill_invoked_in`), alongside the existing helpers:

```bash
# Prints the concatenated assistant text content from a turn's log file --
# the model's own words, with tool_use/tool_result blocks excluded. Used
# by suites that judge conversational output rather than a produced file
# (currently only vertical-slices-gate-quality).
extract_assistant_text() {
    local log_file="$1"
    jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$log_file" 2>/dev/null
}
```

`jq` already processes newline-delimited JSON streams (one top-level value per line) without needing `-s`, so this works directly against the same `stream-json` log format every other helper in this file already parses. No new dependency — `jq` is already a stated prerequisite for every suite.

## Part B — `vertical-slices-gate` quality suite

**Conversation:** extends `program-design-gate-quality`'s 9-turn script three turns further, through `writing-plans` saving a plan and into `vertical-slices-gate`'s own confirmation turn — reusing the same URL-shortener toy feature (its two independently-deployable components, a redirect service and an admin API sharing one datastore, give the "flag coordination risk" checklist item something real to exercise). **12 turns total:**

1. Feature request (full URL-shortener spec)
2. "That approach looks good — please continue." (`brainstorming`)
3. "Approved. Please write the spec and commit it."
4. "I've reviewed the spec, it looks good, please proceed." (→ `architecture-gate`)
5. "That architecture approach looks good — please continue." (`architecture-gate`)
6. "Approved. Please write the architecture doc."
7. "I've reviewed the architecture doc, it looks good, please proceed." (→ `program-design-gate`)
8. "Approved. Please write the program design doc." (`program-design-gate`'s present+approve+write)
9. "I've reviewed the program design doc, it looks good, please proceed." (→ `writing-plans` — note the added "please proceed" vs. `program-design-gate-quality`'s turn 9, which stops here; this suite needs to continue)
10. "Approved. Please write the implementation plan." (`writing-plans` saves the plan)
11. "I've reviewed the plan, it looks good." (`vertical-slices-gate` should fire here, before any execution mode is offered or chosen — this is the turn the suite captures)
12. "Confirmed, that build order looks right." (closes the loop; the suite stops here — it does not choose an execution mode or trigger `subagent-driven-development`/`executing-plans`, which would start real, costly implementation work out of scope for a quality check)

**Trial count:** 2 by default (not 3, matching the other suites) — this is now the longest, most expensive suite (12 turns/trial vs. 9 for `program-design-gate-quality`), and today's session hit a real rate limit running the (shorter) `gate-routing` suites. The README states this explicitly rather than silently inheriting the old default.

**Artifact captured for judging:** unlike the doc-review suites, there's no file to locate. `run-trial.sh` tracks `VERTICAL_SLICES_GATE_TRIGGERED` and `VERTICAL_SLICES_GATE_TURN` (first turn where `skill_invoked_in` matches `vertical-slices-gate`, mirroring `gate-routing`'s `ARCHITECTURE_GATE_TURN` tracking) the same way the other suites track their gate flags — looping through all 12 turns unconditionally, no early break. If triggered, `extract_assistant_text` pulls that turn's assistant text and that's what gets judged. If not triggered within the script, the trial is `inconclusive` — no judging attempted.

**Rubric**, derived directly from `vertical-slices-gate`'s own checklist:

| Category | What to look for |
|---|---|
| Slice order stated | Lists the build-order tasks/slices, one line each, in the order they'll be built |
| Demoable/testable noted | For each slice, names what's independently testable/demoable after it lands |
| Coordination risk | If the plan spans multiple repos/services, explicit order dependencies are called out (what ships/deploys before what); if genuinely single-service, no fabricated cross-service risk is invented |
| Intermediate-test gaps | Any slice that can't be verified until a later slice lands is surfaced explicitly, not glossed over |
| Explicit confirmation requested | Ends with a clear, short confirm-or-reorder question — not a redesign prompt |
| Scope discipline | Doesn't re-litigate architecture/program-design decisions already fixed in earlier gates; doesn't duplicate `writing-plans`' own task-level implementation detail |

**Calibration**, matching the other suites' judge prompts: only flag issues that would cause a real problem for a human confirming this build order — a missing task from the plan, invented coordination risk that doesn't actually exist, no confirmation question at all, re-opening architecture/program-design decisions. Wording and formatting preferences are not issues.

**Output format** (judge's response), same shape as the other two gates':

```
## Vertical Slices Gate Review

**Status:** Approved | Issues Found

**Issues (if any):**
- [Category]: [specific issue]

**Recommendations (advisory, do not block approval):**
- [suggestions]
```

**Outcome classification:** same three-way split as the other suites — `pass` (judge: Approved), `fail` (judge: Issues Found), `inconclusive` (`vertical-slices-gate` never triggered within the 12-turn script, or judge output unparseable).

**Known limitation, stated up front:** the judge sees only the first turn `vertical-slices-gate` fires in, not any back-and-forth refinement in later turns — same category of limitation the other two suites already document for "sees only the final document, not the conversation that produced it," just the conversational-output equivalent.

## File Structure

```
tests/gate-routing/
  lib/
    common.sh                     — modified: add extract_assistant_text
tests/gate-quality/
  vertical-slices-gate/
    README.md
    run-trial.sh
    run-all.sh
    test-judge.sh
    lib/
      judge.sh                     — build_judge_prompt(transcript_text) [vertical-slices-gate's rubric], sources ../../lib/judge-common.sh
```

`judge-common.sh` (`run_judge`, `parse_judge_verdict`) is reused unchanged — no gate-specific logic lives there.

## Out of scope

- CI integration (same reasoning as every other suite in this repo).
- Choosing/exercising an actual execution mode (`subagent-driven-development`/`executing-plans`) — real implementation work is out of scope for a quality check on the confirmation turn itself.
- Any wording changes to `vertical-slices-gate`'s own `SKILL.md` — this round is measurement only, following the same "don't fix before you've measured" discipline as `architecture-gate-quality`'s first run.

## Self-review

- **Placeholders:** none — the turn script, rubric, and output format are all concrete final text.
- **Internal consistency:** turn 9's wording is called out explicitly as differing from `program-design-gate-quality`'s (adds "please proceed" since this suite must continue past it), preventing a copy-paste mismatch.
- **Scope:** two parts (one shared helper, one new suite), no changes to any gate skill's wording, no changes to the shared judge library beyond reuse.
- **Ambiguity:** the trial-count reduction (2 vs. 3) and the "stop before choosing an execution mode" boundary were both open design questions, resolved explicitly during the design conversation before this doc was written — not decided silently.
