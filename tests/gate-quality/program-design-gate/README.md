# Program Design Gate Quality Tests

Judges the *content quality* of the document `program-design-gate`
produces, not whether the skill gets invoked. Drives a real
`brainstorming` -> `architecture-gate` -> `program-design-gate`
conversation on the same toy URL-shortener feature used by
`../architecture-gate/`, then scores the resulting program design
document against a rubric derived from `program-design-gate`'s own
checklist and template, using the shared headless LLM judge in
`../lib/judge-common.sh`.

## How it works

1. A real `claude -p` conversation (both `superpowers` and `factory-gates`
   loaded) walks through a 9-turn script -- the full 7 turns from
   `../architecture-gate/`'s suite through architecture-doc approval,
   plus 2 more turns for `program-design-gate`'s own present+approve+write
   step and final review-gate approval.
2. The produced `docs/superpowers/specs/*-program-design.md` file is
   located in the trial's isolated project directory.
3. A **second, separate, sandboxed** `claude -p` call (see
   `../lib/judge-common.sh`) is given the document plus this gate's
   rubric and asked to return `Approved` or `Issues Found` with itemized
   findings.

## Running

```bash
# Default batch (3 trials, likely 20-40+ minutes total, real token cost --
# each trial is longer than tests/gate-quality/architecture-gate/'s, since
# it walks through one more gate)
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

Same three-way outcome split as `../architecture-gate/`:

- **pass** — the judge reviewed the doc and returned `Approved`
- **fail** — the judge reviewed the doc and returned `Issues Found` --
  check that trial's `judge_output_file` (path is in its `result.json`)
- **inconclusive** — no program design doc was produced within the
  9-turn script -- check `result.json`'s `architecture_gate_triggered`
  and `program_design_gate_triggered` fields to see how far the
  conversation actually got before concluding this is a quality-suite
  bug rather than the known routing non-determinism documented in
  `../../gate-routing/`

## Known limitations

Same as `../architecture-gate/README.md`'s "Known limitations" section
(non-determinism on two axes, judge sees only the final document not the
conversation, not run in CI) -- additionally:

- **Longer trials compound non-determinism.** Reaching `program-design-gate`
  requires `architecture-gate` to have triggered first, so this suite's
  `inconclusive` rate is expected to run higher than
  `../architecture-gate/`'s alone.
