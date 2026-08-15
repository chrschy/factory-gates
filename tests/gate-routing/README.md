# Gate-Routing Tests

Empirically tests the one real skill-routing conflict in this plugin:
Superpowers' `brainstorming` skill ends with a hard, twice-repeated
instruction -- "The ONLY skill you invoke after brainstorming is
writing-plans... do NOT invoke any other skill" -- while
`architecture-gate` tries to insert itself between `brainstorming` and
`writing-plans` via a highly specific trigger description plus
Superpowers' own "if a skill applies, you MUST use it" routing rule. The
README at the repo root calls this a "soft override, not a hard one."
This test suite measures how often it actually holds.

The other two gate handoffs (`architecture-gate` -> `program-design-gate`,
`program-design-gate` -> `writing-plans`) aren't tested here because
there's no conflict to measure -- both sides are our own skills, or our
skill hands off to `writing-plans` the same way `writing-plans` itself
expects.

## How it works

Real `claude -p` sessions, with both `superpowers` and `factory-gates`
loaded via `--plugin-dir`, driven through an actual brainstorming
conversation about a small, fully-specified feature (an in-memory rate
limiter) to the point where `brainstorming` would normally hand off to
`writing-plans`. Each trial records which skill actually fires next.

- **bare** scenario: ordinary feature request, no special phrasing
- **explicit** scenario: same request, prefixed with the README's
  documented workaround, "Use the factory-gates workflow for this."

Default matrix: 3 trials per scenario (6 total). Each trial gets its own
isolated `/tmp` project directory so `--continue` (which resumes "the
most recent conversation in the current directory") can't cross-contaminate
trials.

## Running

```bash
# Full matrix (2 scenarios x 3 trials, ~20-40 minutes, real token cost)
./run-all.sh

# Cheap single-trial spot check while iterating on the harness itself
./run-all.sh --scenario bare --trials 1

# One scenario, custom trial count
./run-all.sh --scenario explicit --trials 5
```

Requires: `claude` CLI installed and authenticated, `jq`, and the
Superpowers plugin installed locally (auto-discovered from
`~/.claude/plugins/cache/claude-plugins-official/superpowers/`, override
with `SUPERPOWERS_PLUGIN_DIR` to point at a different checkout).

## Reading the output

`run-all.sh` prints a table like:

```json
[
  { "scenario": "bare", "trials": 3, "pass": 2, "fail": 1, "inconclusive": 0 },
  { "scenario": "explicit", "trials": 3, "pass": 3, "fail": 0, "inconclusive": 0 }
]
```

- **pass** — `architecture-gate` was invoked before `writing-plans`
- **fail** — either `writing-plans` was invoked directly with
  `architecture-gate` never firing first (the failure mode the README
  warns about), or `brainstorming` was bypassed entirely and some other
  skill fired instead before it ever triggered (a more severe pattern —
  the entire gate model gets skipped, not just one gate). Trials that
  fail for the second reason carry a non-empty `bypass_skill` field in
  `result.json`, naming the skill that fired instead.
- **inconclusive** — `brainstorming` triggered but neither
  `architecture-gate` nor `writing-plans` fired within 4 turns (the trial
  ran out of turn budget before reaching the routing decision), or
  literally nothing was invoked at all (a crash, timeout, or other
  environment/setup issue with the trial — not a signal about
  factory-gates' routing)

A separate `detour_skill` field records a different, non-fatal pattern:
`brainstorming` fires correctly, but the conversation gets sidetracked
into an unrelated skill (most commonly `test-driven-development`) before
settling into its final outcome. Unlike `bypass_skill`, this does not
change `outcome` — a trial that detours and still reaches
`architecture-gate` is still a `pass`. It's purely diagnostic: useful for
seeing how often trials take a detour and whether they recover.

Both `bypass_skill` and `detour_skill` exclude this plugin's own
`factory-gates` entry-point skill from counting as a bypass or detour —
its own instructions are to invoke `brainstorming` immediately next, so
seeing it fire (alone, or just before `brainstorming` in the same turn)
is expected, on-path behavior, not a routing problem.

Per-trial logs and `result.json` verdicts are kept under
`/tmp/factory-gates-tests/<timestamp>/<scenario>/trial-<n>/` for
inspection after a run.

## Known limitations

- **Non-deterministic.** This is measuring an LLM's routing decision, not
  running code -- re-running the same scenario can produce different
  outcomes. Read the pass rate as a rate, not a single yes/no verdict.
  Re-run whenever `brainstorming`'s or `architecture-gate`'s wording
  changes, per `CLAUDE.md`'s "Skill Changes Require Evidence."
- **Same-turn ordering isn't checked.** If a trial invokes both
  `writing-plans` and `architecture-gate` within the same conversation
  turn, `run-trial.sh` counts it as a pass regardless of which one the
  model actually called first inside that turn. This matches the rigor
  level of Superpowers' own equivalent tests.
- **Not run in CI.** Each trial costs real tokens and needs a locally
  authenticated `claude` CLI -- this is a manual/occasional diagnostic,
  not a required check on every push.
