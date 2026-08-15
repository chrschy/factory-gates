# Vertical Slices Gate Quality Tests

Judges the *content quality* of the conversation turn `vertical-slices-gate`
produces, not whether the skill gets invoked (that's `tests/gate-routing/`'s
job -- though this suite's much longer trial chain means routing
non-determinism compounds here more than anywhere else). Unlike
`architecture-gate` and `program-design-gate`, this skill produces no
persisted document -- its entire output is a conversation turn summarizing
build order and asking for confirmation. Drives a real `brainstorming` ->
`architecture-gate` -> `program-design-gate` -> `writing-plans` ->
`vertical-slices-gate` conversation on the same toy URL-shortener feature
used by the other two suites, extracts the assistant's text from the turn
`vertical-slices-gate` fires in, and scores it against a rubric derived
from the skill's own checklist, using the shared headless LLM judge in
`../lib/judge-common.sh`.

## How it works

1. A real `claude -p` conversation (both `superpowers` and `factory-gates`
   loaded) walks through a 12-turn script -- the full 9 turns from
   `../program-design-gate/`'s suite through program-design-doc approval,
   plus 3 more turns for `writing-plans` saving a plan and
   `vertical-slices-gate`'s own confirmation exchange.
2. The assistant's text is extracted from whichever turn
   `vertical-slices-gate` first fires in (there's no file to locate --
   see the design spec at
   `docs/superpowers/specs/2026-08-15-vertical-slices-gate-quality-tests-design.md`
   for why).
3. A **second, separate, sandboxed** `claude -p` call (see
   `../lib/judge-common.sh`) is given that excerpt plus this gate's
   rubric and asked to return `Approved` or `Issues Found` with itemized
   findings.

## Running

```bash
# Default batch (2 trials, likely 30-50+ minutes total, real token cost --
# this is the longest suite yet, 12 turns/trial)
./run-all.sh

# Cheap single-trial spot check while iterating on the harness itself
./run-all.sh --trials 1
```

Requires: `claude` CLI installed and authenticated, `jq`, and the
Superpowers plugin installed locally (see `../../gate-routing/README.md`
for the same prerequisites and `SUPERPOWERS_PLUGIN_DIR` override).

Unit tests for the judge's parsing/templating logic (fast, no live
calls):

```bash
./test-judge.sh
```

## Reading the output

Same three-way outcome split as the other suites:

- **pass** — the judge reviewed the confirmation turn and returned `Approved`
- **fail** — the judge reviewed it and returned `Issues Found` -- check
  that trial's `judge_output_file` (path is in its `result.json`)
- **inconclusive** — `vertical-slices-gate` never triggered within the
  12-turn script -- check `result.json`'s `*_triggered` fields to see how
  far the conversation actually got before concluding this is a
  quality-suite bug rather than routing non-determinism (compounded here
  across four gate handoffs, not just one)

## Known limitations

Same as `../program-design-gate/README.md`'s (non-determinism on two
axes, not run in CI, single toy feature) -- additionally:

- **Judge sees only the first turn `vertical-slices-gate` fires in**, not
  any back-and-forth refinement afterward -- the conversational
  equivalent of the doc-review suites only seeing the final document, not
  the process that produced it.
- **Longest, most expensive suite.** Four gate handoffs have to succeed
  in sequence for a trial to reach `vertical-slices-gate` at all, so
  expect the highest `inconclusive` rate of the three suites. Default
  trial count is 2, not 3, given the real cost of a 12-turn trial.
- **Does not exercise actual execution.** The script stops right after
  `vertical-slices-gate`'s confirmation turn -- it never chooses
  `subagent-driven-development` or `executing-plans`, since triggering
  real implementation work is out of scope for a quality check on the
  confirmation turn itself.
