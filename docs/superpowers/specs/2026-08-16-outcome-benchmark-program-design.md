# Superpowers-vs-factory-gates Outcome Benchmark — Program Design

**Architecture:** docs/superpowers/specs/2026-08-16-outcome-benchmark-architecture.md

## `tests/gate-routing/lib/common.sh` (modified)
**File:** `tests/gate-routing/lib/common.sh`

```
# Usage: run_turn <project-dir> <prompt> <do_continue: 0|1> <superpowers-dir> <factory-gates-dir|""> <log-file>
# factory-gates-dir may be "" -- when empty, the --plugin-dir flag for it
# is omitted entirely (not passed as an empty path). Every other parameter
# and the stream-json log-file contract are unchanged from today.
run_turn(project_dir: str, prompt: str, do_continue: "0"|"1", superpowers_dir: str, factory_gates_dir: str, log_file: str) -> void
```

All other functions in this file (`resolve_superpowers_dir`, `resolve_factory_gates_dir`, `setup_trial_dir`, `skill_invoked_in`, `first_skill_invoked_in`, `extract_assistant_text`) are unmodified.

## `tests/outcome-benchmark/lib/turns.sh`
**File:** `tests/outcome-benchmark/lib/turns.sh`

```
# Pure data, sourced by run-trial.sh. No functions.
FEATURE_REQUEST: str
TREATMENT_TURNS: str[12]   # brainstorming -> architecture-gate -> program-design-gate -> writing-plans -> vertical-slices-gate, verbatim from tests/gate-quality/vertical-slices-gate/run-trial.sh
BASELINE_TURNS: str[6]     # brainstorming -> writing-plans only, verbatim from the design spec
```

## `tests/outcome-benchmark/lib/execute.sh`
**File:** `tests/outcome-benchmark/lib/execute.sh`

```
# Usage: run_execution_step <project-dir> <plan-path> <spec-path> <log-file>
# Runs ONE unscripted `claude -p` call in <project-dir>, with NO
# --plugin-dir flags at all (identical for both conditions -- see
# architecture doc's execution-phase constraint), --max-turns 40,
# wrapped in `timeout 1800`. Prompt: the spec's fixed
# implement-the-plan-and-expose-this-HTTP-contract text, with <plan-path>
# and <spec-path> interpolated. Logs full stream-json output to <log-file>.
# Prints "true" to stdout if <project-dir>/serve.py exists after the call
# returns, else "false". This is an existence check only -- it does not
# prove the server actually starts or behaves correctly; that's
# score.sh's job.
run_execution_step(project_dir: str, plan_path: str, spec_path: str, log_file: str) -> "true"|"false" (stdout)
```

## `tests/outcome-benchmark/lib/score.sh`
**File:** `tests/outcome-benchmark/lib/score.sh`

```
# Usage: parse_unittest_output <output-file>
# Pure text parser, no subprocess, no network. Reads the output of
# `python3 -m unittest -v` (or an equivalently-invoked test module) from
# <output-file>. Extracts the total test count from a "Ran N tests"
# line, and the passed count as: total (if a bare "OK" line follows), or
# total - failures - errors (if a "FAILED (failures=N[, errors=M])" line
# follows). Prints "<passed> <total>" to stdout. Prints "0 0" if no
# recognizable summary line is found (crashed or truncated output) --
# this is the function test-scoring.sh exercises directly against canned
# text fixtures, no live calls.
parse_unittest_output(output_file: str) -> "<passed> <total>" (stdout)

# Usage: run_acceptance_tests <project-dir> [output-log-file]
# Independently re-checks for <project-dir>/serve.py (does not trust
# execute.sh's "true"/"false" -- see architecture doc's Data Models
# section) and prints "0 0" immediately if it's missing. Otherwise starts
# `python3 serve.py` as a background subprocess in <project-dir>, polls
# 127.0.0.1:8000 for up to 10s (20 attempts, 0.5s apart). If the port
# never opens, kills the subprocess and prints "0 0". If it opens, runs
# tests/outcome-benchmark/fixtures/acceptance_tests.py -v against it,
# captures output to [output-log-file] (default /dev/null), always kills
# the subprocess afterward (even if the test run itself errors), and
# prints parse_unittest_output's result.
run_acceptance_tests(project_dir: str, output_log_file: str = "/dev/null") -> "<passed> <total>" (stdout)
```

## `tests/outcome-benchmark/fixtures/acceptance_tests.py`
**File:** `tests/outcome-benchmark/fixtures/acceptance_tests.py`

```python
import json
import unittest
import urllib.error
import urllib.request

BASE_URL = "http://localhost:8000"

def _post_link(url: str) -> tuple[int, dict]:
    """POST {"url": url} to BASE_URL/api/links. Returns (status_code, parsed_json_body); body is {} if the response wasn't valid JSON."""

def _get(path: str) -> tuple[int, dict[str, str]]:
    """GET BASE_URL + path, redirects NOT followed. Returns (status_code, response_headers)."""

class AcceptanceTests(unittest.TestCase):
    def test_create_then_redirect(self) -> None:
        """POST a URL, then GET the returned code -> 302 with Location == the original URL."""

    def test_unknown_code_returns_404(self) -> None:
        """GET a code that was never created -> 404."""

    def test_malformed_create_request(self) -> None:
        """POST with a missing/invalid "url" field -> 4xx, not a 500 or connection error."""

    def test_duplicate_url_each_code_redirects_correctly(self) -> None:
        """POST the same URL twice -> both requests succeed (2xx); each returned code independently GETs a 302 to the original URL. Does not assert whether the two codes are equal or different."""

    def test_code_collision_safety(self) -> None:
        """Create enough links in one run to make a same-length code collision plausible; assert no two created codes ever redirect to a URL other than the one returned at creation time for that code."""

if __name__ == "__main__":
    unittest.main()
```

## `tests/outcome-benchmark/run-trial.sh`
**File:** `tests/outcome-benchmark/run-trial.sh`

CLI: `run-trial.sh <treatment|baseline> <trial-dir>`. Not sourced by anything; sources `common.sh`, `turns.sh`, `execute.sh`, `score.sh`.

## `tests/outcome-benchmark/run-all.sh`
**File:** `tests/outcome-benchmark/run-all.sh`

CLI: `run-all.sh [--trials N]` (default `N=3`). Not sourced by anything.

## `tests/outcome-benchmark/test-scoring.sh`
**File:** `tests/outcome-benchmark/test-scoring.sh`

CLI: `test-scoring.sh` (no args). Sources `lib/score.sh`, calls `parse_unittest_output` against canned text fixtures written inline (mirrors `test-judge.sh`'s structure of heredoc fixtures + `assert_eq`).

## `.github/workflows/ci.yml` (modified)
**File:** `.github/workflows/ci.yml`

One new step added to the `fast-tests` job, after the three existing `test-judge.sh` steps:

```yaml
      - name: Run outcome-benchmark scoring unit tests
        run: tests/outcome-benchmark/test-scoring.sh
```

## Call Stacks

**Per-trial flow**, `run-trial.sh <condition> <trial-dir>`:

```
run-trial.sh <condition> <trial-dir>
  resolve_superpowers_dir(), resolve_factory_gates_dir()   [common.sh, unmodified]
  setup_trial_dir(trial-dir) -> project_dir                [common.sh, unmodified]
  select TURNS = TREATMENT_TURNS|BASELINE_TURNS and
         run_factory_gates_dir = factory_gates_dir|""      by <condition>
  for each turn in TURNS:
    run_turn(project_dir, turn, do_continue, superpowers_dir, run_factory_gates_dir, log_file)
    skill_invoked_in(log_file, "<gate>") -> update *_triggered flags
  plan_path  = find project_dir/docs/superpowers/plans -name '*.md' -print -quit
  spec_path  = find project_dir/docs/superpowers/specs -name '*-design.md' -print -quit
  if plan_path and spec_path both non-empty:
    serve_py_exists = run_execution_step(project_dir, plan_path, spec_path, execution_log)
    if serve_py_exists == "true":
      "tests_passed tests_total" = run_acceptance_tests(project_dir, score_log)
  outcome =
    "inconclusive"  if plan_path empty, or spec_path empty,
                        or serve_py_exists != "true", or tests_total == 0
    "pass"          if tests_passed == tests_total
    "fail"          otherwise
  write trial-dir/result.json   [shape fixed by the design spec -- condition,
                                  *_triggered flags, plan_found, plan_path,
                                  execution_completed (= serve_py_exists == "true"),
                                  tests_passed, tests_total, turns_used, outcome]
```

`tests_total == 0` doubles as "the server file existed but never actually accepted a connection" — reusing the design spec's existing `result.json` fields (no schema addition) to represent exactly what the spec already calls "execution never produced a startable server."

**Batch flow**, `run-all.sh [--trials N]`:

```
run-all.sh [--trials N]
  for condition in treatment, baseline:
    for trial_num in 1..N:
      run-trial.sh condition trial-dir
      collect trial-dir/result.json
  for each condition, aggregate via jq:
    { trials, pass, fail, inconclusive,
      mean_pass_rate: mean(tests_passed/tests_total) over non-inconclusive trials, or null if none }
  print combined { "treatment": {...}, "baseline": {...} } summary
```

## Deviations from architecture

None — the architecture doc's Components table (`execute.sh` reports `serve.py` existence; `score.sh` independently re-verifies rather than trusting that signal) and Data Models section already specified this contract's shape. Everything above makes that contract concrete with exact signatures and parameters; it does not resolve anything the architecture doc left open.
