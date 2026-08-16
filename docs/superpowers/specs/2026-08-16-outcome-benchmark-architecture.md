# Superpowers-vs-factory-gates Outcome Benchmark — Architecture

**Spec:** docs/superpowers/specs/2026-08-16-outcome-benchmark-design.md

## Components

| Component | Responsibility |
|---|---|
| `tests/gate-routing/lib/common.sh` (modified) | `run_turn` gains support for an empty `factory_gates_dir` argument, omitting the second `--plugin-dir` flag when empty. Backward compatible: every existing caller (`gate-routing`, all three `gate-quality` suites) always passes a real path today, so their behavior is unchanged. `resolve_superpowers_dir`, `setup_trial_dir`, `skill_invoked_in` are reused unmodified. |
| `tests/outcome-benchmark/lib/turns.sh` | Owns the shared `FEATURE_REQUEST` text and both turn arrays, `TREATMENT_TURNS` and `BASELINE_TURNS`. Pure data — no execution logic. |
| `tests/outcome-benchmark/run-trial.sh` | Orchestrator for a single trial. Usage: `run-trial.sh <treatment\|baseline> <trial-dir>`. Selects the matching turn array and whether to pass a real or empty `factory_gates_dir`, drives the conversation via `run_turn`, locates the produced plan doc, calls `execute.sh` then `score.sh`, writes `result.json`. |
| `tests/outcome-benchmark/lib/execute.sh` | One function, `run_execution_step`: given a project dir, plan path, and spec path, runs the fixed, plugin-free `claude -p` implementation call (identical prompt for both conditions) and reports whether `serve.py` exists afterward. |
| `tests/outcome-benchmark/lib/score.sh` | One function, `run_acceptance_tests`: starts `serve.py` as a background subprocess, waits for the port, runs `fixtures/acceptance_tests.py` against it, tears the subprocess down (always, even on early failure), and reports pass/fail counts. |
| `tests/outcome-benchmark/fixtures/acceptance_tests.py` | The fixed black-box HTTP contract test suite from the spec. Stdlib-only (`unittest`, `urllib.request`); has no dependency on either condition's internal implementation shape. |
| `tests/outcome-benchmark/run-all.sh` | Runs N trials × 2 conditions sequentially, aggregates each trial's `result.json` into the per-condition summary from the spec. |
| `tests/outcome-benchmark/test-scoring.sh` | Fast unit tests for `score.sh`'s pass/fail parsing. No live `claude -p` calls — mirrors the existing `test-judge.sh` pattern used by every `gate-quality` suite. |

## Data Models

Shapes crossing component boundaries (the spec's `result.json` shape is the authoritative end-state; this section is the contract between components that produces it):

- **Turn script → `run-trial.sh`:** a bash array of prompt strings (`TREATMENT_TURNS` or `BASELINE_TURNS`) plus the condition string (`treatment`/`baseline`) that selects it and determines whether `factory_gates_dir` is passed empty.
- **`run-trial.sh` → `execute.sh`:** three plain paths — `project_dir`, `plan_path`, `spec_path`. `execute.sh` carries no other state.
- **`execute.sh` → `score.sh`:** no direct handoff. `score.sh` re-derives what it needs from `project_dir` and checks for `serve.py`'s existence itself rather than trusting `execute.sh`'s return value — the execution call's own exit status isn't a reliable signal of a working server (the call can exhaust its turn budget "successfully" while producing a broken or absent server).
- **`run-trial.sh` → `result.json`:** exactly the shape specified in the design doc — `condition`, per-gate `*_triggered` flags, `plan_found`, `plan_path`, `execution_completed`, `tests_passed`/`tests_total`, `turns_used`, `outcome`.

## Constraints

- **Sequential trial execution only.** `run-all.sh` runs trials in a plain `for` loop, no backgrounding — matches every existing suite's convention. This is load-bearing, not incidental: `score.sh` hardcodes port 8000, which is only safe because trials never run concurrently. If a future change parallelizes `run-all.sh`, port allocation must change with it.
- **`execute.sh`'s `claude -p` call passes no `--plugin-dir` flags at all, for either condition.** This is the one place treatment and baseline are deliberately identical, per the spec's execution-fixing decision.
- **`fixtures/acceptance_tests.py` is stdlib-only** (`unittest`, `urllib.request`) — no new dependency introduced for the test harness itself.
- **Not run in CI** — matches `gate-routing`/`gate-quality`'s existing stance: real tokens, real time, non-deterministic, manual/occasional diagnostic.

## Multi-repo / multi-service coordination

None — single repo, one new directory (`tests/outcome-benchmark/`), one modified shared file (`tests/gate-routing/lib/common.sh`).

## Open questions the product spec left open

None — the design spec (`2026-08-16-outcome-benchmark-design.md`) fully specified the outcome definition, baseline definition, execution-fixing approach, and acceptance test design. The two decisions resolved in this gate — `run_turn`'s empty-`factory_gates_dir` support, and one parameterized `run-trial.sh` vs. two separate scripts — were implementation-shape gaps in the spec's own File Structure section (the spec incorrectly asserted `run_turn` already supported this), not open product questions.
