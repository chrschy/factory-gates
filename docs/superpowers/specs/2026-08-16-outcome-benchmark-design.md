# factory-gates — Superpowers-vs-factory-gates Outcome Benchmark

**Status:** approved
**Date:** 2026-08-16

## Why

`tests/gate-routing/` measures whether the gates get *invoked*. `tests/gate-quality/*/` measures whether each gate's own output (a doc, or a confirmation turn) is good, judged against that gate's own checklist. Neither measures the thing the gates ultimately exist for: does going through them produce *better working code* than skipping them. The backlog has carried this as an open item since `gate-quality`'s third suite landed, gated on deciding what "outcome" means and what a fair no-gates baseline looks like. This spec answers both and designs the suite.

## Outcome definition

Outcome = whether the final implementation passes a fixed, black-box acceptance test suite written against the toy feature's spec — not an LLM judge's opinion of a document. This is the most direct measure of whether the gates change what ships, at the cost of being the most expensive suite in the repo (a full implementation pass, not just planning documents).

## Baseline definition

**baseline** = Superpowers installed alone, factory-gates plugin not installed for that trial (not passed via `--plugin-dir`). `brainstorming` and `writing-plans` route exactly as they do with no factory-gates skill descriptions in the mix. This isolates the single variable under test — plugin presence — rather than instructing an agent that has the plugin loaded to ignore it, which would leave an indirect-influence confound (e.g. `architecture-gate`'s skill description possibly nudging `brainstorming`'s own output even when the gate itself isn't invoked).

## Two conditions, shared toy feature

Both conditions reuse the URL-shortener feature already used by every `gate-quality` suite (`FEATURE_REQUEST` text copied verbatim from `tests/gate-quality/vertical-slices-gate/run-trial.sh`) — one toy feature across all suites, spec already exercises component boundaries and cross-boundary data.

**treatment** — reuses `vertical-slices-gate-quality`'s existing 12-turn script verbatim, both plugin dirs loaded:

1. Feature request (full URL-shortener spec)
2. "That approach looks good — please continue."
3. "Approved. Please write the spec and commit it."
4. "I've reviewed the spec, it looks good, please proceed."
5. "That architecture approach looks good — please continue."
6. "Approved. Please write the architecture doc."
7. "I've reviewed the architecture doc, it looks good, please proceed."
8. "Approved. Please write the program design doc."
9. "I've reviewed the program design doc, it looks good, please proceed."
10. "Approved. Please write the implementation plan."
11. "I've reviewed the plan, it looks good."
12. "Confirmed, that build order looks right."

**baseline** — same feature request and spec-approval turns, only Superpowers loaded, skipping straight from the approved spec to `writing-plans` (no `architecture-gate`/`program-design-gate`/`vertical-slices-gate` turns to route through):

1. Feature request (identical text)
2. "That approach looks good — please continue."
3. "Approved. Please write the spec and commit it."
4. "I've reviewed the spec, it looks good, please proceed to plan the implementation."
5. "That implementation approach looks good — please write the plan."
6. "I've reviewed the plan, it looks good."

Both scripts locate their produced plan the same way: `find "$PROJECT_DIR/docs/superpowers/plans" -name '*.md' -print -quit` (confirmed against `writing-plans`' own `SKILL.md`: `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`).

If no plan file is found in either condition, the trial is `inconclusive` — same convention as the other suites — and the execution step is skipped.

## Execution phase — fixed and identical across conditions

A single, unscripted `claude -p` call, **no `--plugin-dir` flags at all** (no skill routing — this is deliberately not a real user's execution path; it exists to hold execution constant so the comparison isolates planning-phase differences, not `subagent-driven-development`/`executing-plans` routing variance). Generous turn budget (`--max-turns 40`) since this call has to write and iterate on real code without human-in-the-loop checkpoints.

Prompt (same text both conditions):

> Implement the plan at `<plan-path>` completely, in this repository. The approved spec is at `<spec-path>` for reference. Regardless of what the plan or spec say about transport details, the final result must expose exactly this HTTP contract, since it will be tested automatically:
>
> - `POST /api/links` with JSON body `{"url": "<target>"}` → `201` with JSON body `{"code": "<short code>"}`
> - `GET /<code>` → `302` with `Location` set to the stored target URL
> - `GET /<code>` for an unknown code → `404`
> - The service must be startable from the project root with exactly: `python3 serve.py`, listening on port 8000.
>
> Implement real, working behavior — not stubs. When finished, confirm the server starts cleanly with that exact command.

Pinning the transport contract at execution time (not inferred from whatever the plan/architecture doc decided) is what makes one universal acceptance test suite possible across two conditions whose planning artifacts can legitimately differ in shape. It does not erase the gates' effect on outcome: internal correctness under the pinned contract (collision handling, malformed input, datastore consistency between the two components) is still free to vary, and that's exactly the axis `architecture-gate`/`program-design-gate` are meant to influence.

`execution_completed` in the result is `true` only if the call exits and a `serve.py` file exists in the project root afterward; otherwise the trial is `inconclusive` and scoring is skipped.

## Scoring — black-box HTTP acceptance tests

`fixtures/acceptance_tests.py`: stdlib-only (`unittest` + `urllib.request`, no third-party deps — matches the feature's own "Python stdlib only" constraint, though that constraint applies to the implementation, not a hard requirement on the test harness). `lib/score.sh`:

1. Starts `python3 serve.py` as a background subprocess in the trial's project dir, port 8000.
2. Polls briefly for the port to accept connections (short timeout; failure to start → `inconclusive`, not `fail` — a dead server is a different failure mode than wrong behavior).
3. Runs `acceptance_tests.py` against `http://localhost:8000`, capturing per-test pass/fail via `unittest`'s machine-readable output.
4. Kills the subprocess.

**Test cases** (black-box, contract-level, not implementation-shape-dependent):

| Test | Checks |
|---|---|
| Create then redirect | POST a URL, then GET the returned code → 302 to the original URL |
| Unknown code | GET a code that was never created → 404 |
| Malformed create request | POST with missing/invalid `url` field → 4xx, not a crash/500 |
| Duplicate URL | POST the same URL twice → both succeed; each returned code independently redirects correctly (does not assert whether codes are the same or different — the spec doesn't require either) |
| Code collision safety | Create enough links in one trial run to make a same-length collision plausible; assert no two created codes ever map to different stored URLs than what was returned at creation time |

## Result shape and aggregation

Per-trial `result.json`:

```json
{
  "trial_dir": "...",
  "condition": "treatment | baseline",
  "brainstorming_triggered": true,
  "architecture_gate_triggered": true,
  "program_design_gate_triggered": true,
  "vertical_slices_gate_triggered": true,
  "plan_found": true,
  "plan_path": "...",
  "execution_completed": true,
  "tests_passed": 4,
  "tests_total": 5,
  "turns_used": 12,
  "outcome": "pass | fail | inconclusive"
}
```

`outcome` is `pass` only if `tests_passed == tests_total`; `fail` if execution completed and scoring ran but at least one acceptance test failed; `inconclusive` if no plan was found or execution never produced a startable server. (Gate-triggered flags are `false`/omitted-equivalent for `baseline`, mirroring how `gate-quality` suites already report flags that don't apply to a given script.)

`run-all.sh`: runs 3 trials per condition (6 total, `--trials N` overridable — matches the existing suites' default). Aggregates and prints:

```json
{
  "treatment": { "trials": 3, "pass": 2, "fail": 1, "inconclusive": 0, "mean_pass_rate": 0.87 },
  "baseline":  { "trials": 3, "pass": 1, "fail": 1, "inconclusive": 1, "mean_pass_rate": 0.53 }
}
```

`mean_pass_rate` is the mean of each trial's `tests_passed / tests_total` (inconclusive trials excluded from the mean, counted separately) — a finer-grained signal than the pass/fail/inconclusive split alone, since "4/5 tests pass" and "0/5 tests pass" are both `fail` but very different outcomes.

## File structure

```
tests/outcome-benchmark/
  README.md
  run-all.sh                    — drives N trials x 2 conditions, aggregates
  run-trial.sh                  — usage: run-trial.sh <treatment|baseline> <trial-dir>
  lib/
    turns.sh                    — TREATMENT_TURNS / BASELINE_TURNS arrays, shared FEATURE_REQUEST
    execute.sh                  — run_execution_step(project_dir, plan_path, spec_path, log_file)
    score.sh                    — run_acceptance_tests(project_dir) -> writes tests_passed/tests_total
  fixtures/
    acceptance_tests.py
  test-scoring.sh                — unit tests for score.sh's pass/fail parsing, no live calls
```

Reuses `tests/gate-routing/lib/common.sh` unchanged (`resolve_superpowers_dir`, `resolve_factory_gates_dir`, `setup_trial_dir`, `run_turn`, `skill_invoked_in`) — `run_turn` already supports omitting a plugin dir for the baseline condition's `factory-gates`-less script.

## Out of scope

- CI integration — same reasoning as every other suite in this repo: real tokens, real time, non-deterministic, manual/occasional diagnostic.
- Any wording changes to gate skills — this is measurement only.
- Statistical significance testing — 3 trials/condition is a first working version, explicitly not a claim of statistical power (same posture as `gate-routing`'s documented small-sample caveat).
- Multiple toy features — single URL-shortener feature only, same scope limitation the `gate-quality` suites already document.

## Self-review

- **Placeholders:** none — turn scripts, execution prompt, test cases, and result shape are all concrete final text.
- **Internal consistency:** the execution prompt's pinned HTTP contract is checked against the acceptance test cases directly (same field names, same status codes) to avoid the harness contradicting itself.
- **Scope:** one new suite directory, no changes to any gate skill, reuses `gate-routing/lib/common.sh` unchanged.
- **Ambiguity:** the outcome-definition, baseline-definition, execution-fixing, and test-design questions were the backlog's explicitly named open items — each resolved as its own discrete decision during the design conversation before this doc was written, not decided silently.
