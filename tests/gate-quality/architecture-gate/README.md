# Architecture Gate Quality Tests

Judges the *content quality* of the document `architecture-gate` produces,
not whether the skill gets invoked (that's `tests/gate-routing/`'s job).
Drives a real `brainstorming` -> `architecture-gate` conversation on a toy
URL-shortener feature, then scores the resulting architecture document
against a rubric derived from `architecture-gate`'s own checklist and
template, using a separate headless LLM judge.

Scope is deliberately narrow: one gate (`architecture-gate`, the most
novel of the three), one toy feature, document quality only. Nested under
`tests/gate-quality/` so `program-design-gate`/`vertical-slices-gate`
quality suites can be added later as siblings.

## How it works

1. A real `claude -p` conversation (both `superpowers` and `factory-gates`
   loaded) walks through a 7-turn script: the toy feature request,
   approving `brainstorming`'s approach, approving and writing the spec,
   handing off into `architecture-gate`, approving its proposed approach,
   writing the architecture doc, and a final approval.
2. The produced `docs/superpowers/specs/*-architecture.md` file is located
   in the trial's isolated project directory.
3. A **second, separate, headless** `claude -p` call (no plugins) is given
   the document plus the rubric and asked to return `Approved` or
   `Issues Found` with itemized findings.

## Running

```bash
# Default batch (3 trials, likely 15-30+ minutes total, real token cost --
# each trial is a much longer conversation than tests/gate-routing/'s)
./run-all.sh

# Cheap single-trial spot check while iterating on the harness itself
./run-all.sh --trials 1
```

Requires: `claude` CLI installed and authenticated, `jq`, and the
Superpowers plugin installed locally (see `tests/gate-routing/README.md`
for the same prerequisites and `SUPERPOWERS_PLUGIN_DIR` override).

Unit tests for the judge's parsing logic (fast, no live calls):

```bash
./test-judge.sh
```

## Reading the output

`run-all.sh` prints a summary like:

```json
{ "trials": 3, "pass": 2, "fail": 0, "inconclusive": 1 }
```

- **pass** — the judge reviewed the doc and returned `Approved`
- **fail** — the judge reviewed the doc and returned `Issues Found` — check
  that trial's `judge_output_file` (path is in its `result.json`) for the
  itemized issues
- **inconclusive** — no architecture doc was ever produced within the
  7-turn script (`architecture-gate` may not have triggered -- cross-check
  against `tests/gate-routing/`'s findings on that handoff), or the
  judge's own response couldn't be parsed. Not a document-quality signal.

## Known limitations

- **Non-deterministic on two axes**, not one: both the conversation being
  judged and the judge's own verdict are LLM outputs. A `fail` might mean
  the architecture doc was genuinely weak, or it might mean the judge was
  overly strict on this run -- read `judge_output_file` before concluding
  either way, and don't trust a single trial's verdict in isolation.
- **Judge and subject share no state** -- the judge only sees the final
  document, not the conversation that produced it, so it can't tell
  whether a thin section reflects a genuinely simple feature or a skipped
  step.
- **Not run in CI** -- same reasoning as `tests/gate-routing/`: real
  tokens, real time, meant as a manual/occasional diagnostic.
- **Single toy feature.** A URL shortener exercises component boundaries
  and cross-boundary data, but won't surface every failure mode (e.g.
  multi-repo coordination, which the toy feature never triggers).
