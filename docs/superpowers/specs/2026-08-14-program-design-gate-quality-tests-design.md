# factory-gates — Program Design Gate Quality Tests

**Status:** approved
**Date:** 2026-08-14

## Why

`architecture-gate` now has a quality test suite (`tests/gate-quality/architecture-gate/`) judging its output document, following two real bugs found and fixed via that suite: a fabricated "Open questions" entry, and a judge that wasn't sandboxed to just the document it was scoring. `program-design-gate` — the next gate in the chain, and the one Dex Horthy calls "the step teams skip most often" — has never been exercised or judged since the original scaffold. This spec extends the same pattern to it.

Two things emerged while reading `program-design-gate`'s SKILL.md closely, both addressed here:

1. Its "Deviations from architecture" template section has wording almost identical to `architecture-gate`'s old, buggy "Open questions" placeholder — `[Anything the architecture doc left open that got resolved here]`, no instruction to verify before citing. Strong reason to expect the same fabrication risk. Fixed preemptively (Part A) rather than waiting to empirically rediscover it.
2. `run_judge`/`parse_judge_verdict` are entirely gate-agnostic; only the rubric prompt differs per gate. With a second real consumer, duplicating them (as `architecture-gate`'s suite currently does standalone) stops being "avoid premature abstraction" and starts being a real cost — the recent sandboxing fix would need reapplying per gate. Extracted into a shared library (Part C) instead.

`vertical-slices-gate` is explicitly out of scope for this round: it produces no persisted document (pure conversational sign-off), so it needs a genuinely different test design (judging conversation/reasoning quality, not a document) and a much longer trial chain (through `writing-plans` first). Deferred to its own future round.

## Part A — Preemptive wording fix in `program-design-gate`

Two edits in `skills/program-design-gate/SKILL.md`, mirroring the `architecture-gate` fix exactly:

**Document template's "Deviations from architecture" section**, from:
```
## Deviations from architecture
[Anything the architecture doc left open that got resolved here]
```
to:
```
## Deviations from architecture
[Only include an entry here if you can point to the specific architecture doc section that was genuinely underspecified — re-read it before writing this section to confirm. If the architecture doc already specified an answer, that is not a deviation, even if program design had to restate or elaborate on it. If nothing was left open, write "None — the architecture doc fully specified this."]
```

**Self-review checklist item 7**, appending one sentence, from:
```
7. **Self-review:** does every signature referenced in one part of the doc get defined somewhere else in it? Any component from the architecture doc with no corresponding signatures here?
```
to:
```
7. **Self-review:** does every signature referenced in one part of the doc get defined somewhere else in it? Any component from the architecture doc with no corresponding signatures here? For each "Deviations from architecture" entry, re-read the architecture section it cites — does it actually leave this underspecified, or does it already commit to an answer? A fabricated deviation is worse than an empty section.
```

## Part B — `program-design-gate` quality suite

**Conversation:** extends the existing `architecture-gate-quality` script one gate further, reusing the same URL-shortener toy feature. `program-design-gate` has only one combined "present as one document → approve" step before writing (unlike `architecture-gate`'s separate approaches-then-sections steps), so this adds 2 turns, not 3 — **9 turns total**:

1. Feature request (full URL-shortener spec, as in `architecture-gate-quality`)
2. "That approach looks good — please continue." (`brainstorming`)
3. "Approved. Please write the spec and commit it."
4. "I've reviewed the spec, it looks good, please proceed." (→ `architecture-gate`)
5. "That architecture approach looks good — please continue." (`architecture-gate`)
6. "Approved. Please write the architecture doc."
7. "I've reviewed the architecture doc, it looks good, please proceed." (→ `program-design-gate`)
8. "Approved. Please write the program design doc." (`program-design-gate`'s present+approve+write)
9. "I've reviewed the program design doc, it looks good." (final user-review-gate approval)

**Trial count:** 3, same default as the other suites, given the cost trend (9 turns/trial is the most expensive suite yet).

**Rubric**, mirroring `architecture-gate`'s structure, adapted to this gate's checklist/template:

| Category | What to look for |
|---|---|
| Template compliance | References the architecture doc by path; ≥1 Component/Module section with a File path and a signature block; Call Stacks section; Deviations from architecture section |
| Signature completeness | Every component from the architecture doc has corresponding signatures here — no orphans |
| Signature consistency | Every signature referenced anywhere in the doc (e.g. in a call stack) is actually defined somewhere else in it |
| No implementation bodies | Signatures only — no function bodies, no test code |
| Traceability | "Deviations from architecture" entries (if any) reflect genuine underspecification, verified against the cited architecture section — not fabricated (this is the exact thing Part A's fix targets; the suite's first run doubles as verification) |
| Scope discipline | Stays out of `writing-plans`/`vertical-slices-gate` territory (no task sequencing); doesn't re-litigate `architecture-gate`'s already-fixed component boundaries |

**Outcome classification:** same three-way split as `architecture-gate-quality` — pass (judge: Approved), fail (judge: Issues Found), inconclusive (no program-design doc produced within the turn cap, or `program-design-gate` never triggered, or judge output unparseable).

## Part C — Shared judge library

Extract the gate-agnostic pieces of `tests/gate-quality/architecture-gate/lib/judge.sh` into a new shared file:

```
tests/gate-quality/
  lib/
    judge-common.sh        — run_judge(prompt, output_file), parse_judge_verdict(output_file)
                              (generic: takes an already-built prompt, not a doc path + rubric)
  architecture-gate/
    lib/
      judge.sh                — build_judge_prompt(doc_path) [architecture-gate's rubric only],
                              sources judge-common.sh
  program-design-gate/
    lib/
      judge.sh                — build_judge_prompt(doc_path) [program-design-gate's rubric],
                              sources judge-common.sh
```

`run_judge`'s signature changes slightly: it currently takes `(doc_path, output_file)` and calls `build_judge_prompt` internally. Once shared, `run_judge` takes `(prompt, output_file)` directly — the caller (each gate's own code, which already has its own `build_judge_prompt`) builds the prompt first and passes it in. This keeps `judge-common.sh` genuinely gate-agnostic (it never needs to know about `build_judge_prompt` at all) rather than requiring every future gate's `judge.sh` to define a function with that exact name for `judge-common.sh` to call back into.

The sandboxing flags (`--disallowedTools`, `--strict-mcp-config`) live in `judge-common.sh`'s `run_judge` — fixed once, inherited by every gate's suite automatically.

`architecture-gate`'s existing `run-trial.sh` and `test-judge.sh` need their `source` lines and any direct calls to account for the moved functions and the changed `run_judge` signature. `architecture-gate`'s own unit tests (`test-judge.sh`) continue to pass — this is a refactor, not a behavior change.

## File Structure

```
tests/gate-quality/
  lib/
    judge-common.sh              — new: run_judge, parse_judge_verdict (moved from architecture-gate)
  architecture-gate/
    lib/
      judge.sh                    — modified: build_judge_prompt only, sources ../../lib/judge-common.sh
    run-trial.sh                   — modified: call run_judge(build_judge_prompt(doc), out) instead of run_judge(doc, out)
    test-judge.sh                  — modified: source judge-common.sh for parse_judge_verdict tests, keep build_judge_prompt tests local
  program-design-gate/
    README.md
    run-trial.sh
    run-all.sh
    test-judge.sh
    lib/
      judge.sh                      — build_judge_prompt only, sources ../../lib/judge-common.sh
```

## Out of scope

- `vertical-slices-gate` quality suite (deferred, different design needed).
- CI integration (same reasoning as every other suite in this repo).
- Any wording changes to `architecture-gate` or `brainstorming` beyond what's already shipped.

## Self-review

- **Placeholders:** none — both wording edits are exact final text; the rubric and turn script are concrete.
- **Internal consistency:** Part C's `run_judge` signature change is called out explicitly as a real interface change (not hand-waved), and its consequences for `architecture-gate`'s existing files are named directly rather than left implicit.
- **Scope:** three clearly separated parts (preemptive fix, new suite, refactor), each independently justified by evidence already in hand — nothing speculative.
- **Ambiguity:** none — every design fork (preemptive fix vs. wait, duplicate vs. shared library, program-design-gate-only vs. both gates) was raised and resolved explicitly before this doc was written, not decided silently.
