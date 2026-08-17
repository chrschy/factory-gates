# Superpowers-vs-factory-gates Outcome Benchmark

Measures whether going through factory-gates' three gates changes what
actually ships, not just whether a gate produces a good-looking document
(`tests/gate-quality/`'s job) or gets invoked at all (`tests/gate-routing/`'s
job). Drives the same toy URL-shortener feature through two conditions --
**treatment** (Superpowers + factory-gates, full `brainstorming ->
architecture-gate -> program-design-gate -> writing-plans ->
vertical-slices-gate`) and **baseline** (Superpowers alone, `brainstorming
-> writing-plans` only) -- hands each condition's resulting plan to one
identical, plugin-free implementation call, and scores the resulting code
against a fixed, black-box HTTP acceptance test suite.

See `docs/superpowers/specs/2026-08-16-outcome-benchmark-design.md`,
`...-architecture.md`, and `...-program-design.md` for the full design.

## How it works

1. A real `claude -p` conversation drives each condition's turn script
   (12 turns for treatment, 6 for baseline) in an isolated project
   directory.
2. The resulting plan doc (`docs/superpowers/plans/*.md`) and product spec
   (`docs/superpowers/specs/*-design.md`) are located.
3. A second, unscripted `claude -p` call -- identical prompt for both
   conditions, no plugins loaded -- is told to implement the plan and
   expose a fixed HTTP contract via `python3 serve.py`.
4. `fixtures/acceptance_tests.py` (stdlib-only) is run against the
   resulting server, and pass/fail counts are recorded.

## Running

```bash
# Default batch (3 trials per condition, 6 total -- likely 45-90+
# minutes, real token cost -- each trial now includes a full
# implementation pass, not just planning documents)
./run-all.sh

# Cheap single-trial-per-condition spot check while iterating on the
# harness itself
./run-all.sh --trials 1
```

Requires: `claude` CLI installed and authenticated, `jq`, `python3` (3.9
or newer), and the Superpowers plugin installed locally (see
`../gate-routing/README.md` for the same prerequisites and
`SUPERPOWERS_PLUGIN_DIR` override).

Unit tests for the pure parsing/templating logic (fast, no live calls):

```bash
./test-scoring.sh
./test-execute.sh
../gate-routing/test-common.sh
```

## Reading the output

```json
{
  "treatment": { "trials": 3, "pass": 2, "fail": 1, "inconclusive": 0, "mean_pass_rate": 0.87 },
  "baseline":  { "trials": 3, "pass": 1, "fail": 1, "inconclusive": 1, "mean_pass_rate": 0.53 }
}
```

- **pass** -- the implementation passed every acceptance test
- **fail** -- the server started and was scored, but at least one
  acceptance test failed -- check that trial's `acceptance-test-output.txt`
- **inconclusive** -- no plan was ever produced, or the execution step
  never produced a server that actually accepted connections -- check
  `result.json`'s `*_triggered`/`plan_found`/`execution_completed` fields
  to see how far the trial got
- **mean_pass_rate** -- mean of `tests_passed / tests_total` across
  non-inconclusive trials only; `null` if every trial in that condition
  was inconclusive

## Known limitations

- **Non-deterministic on three axes now, not two**: the planning
  conversation, the unscripted implementation call, and (indirectly)
  whatever code that call produces are all LLM outputs. Don't trust a
  single trial's outcome in isolation.
- **Execution is deliberately identical for both conditions** (no
  plugins loaded during implementation) -- this isolates the comparison
  to planning-phase differences, but means this suite does NOT measure
  whether `subagent-driven-development`/`executing-plans` themselves
  behave differently with vs. without factory-gates. That's a different,
  unmeasured question.
- **Not run in CI** -- same reasoning as `gate-routing`/`gate-quality`:
  real tokens, real time, meant as a manual/occasional diagnostic. The
  pure-logic unit tests (`test-scoring.sh`, `test-execute.sh`,
  `../gate-routing/test-common.sh`) are the exception and do run in CI.
- **Single toy feature, fixed HTTP contract.** The execution prompt pins
  transport details (port, paths, JSON shape) identically for both
  conditions so one acceptance suite can score either -- this makes
  interface-*shape* mismatches invisible to this benchmark by design;
  what it measures is internal correctness under a fixed contract
  (collision handling, malformed input, datastore consistency), not
  whether program-design-gate prevents shape drift.
- **3 trials per condition is a first working version**, not a claim of
  statistical power -- same posture as `gate-routing`'s documented
  small-sample caveat.
