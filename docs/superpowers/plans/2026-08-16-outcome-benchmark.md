# Superpowers-vs-factory-gates Outcome Benchmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `tests/outcome-benchmark/`, a suite that drives the same toy URL-shortener feature through two conditions (factory-gates loaded vs. Superpowers alone), hands each condition's resulting plan to one identical implementation call, and scores the resulting code against a fixed black-box acceptance test suite — measuring whether the gates change what actually ships.

**Architecture:** One modified shared helper (`run_turn` gains empty-`factory_gates_dir` support) plus a new `tests/outcome-benchmark/` directory: pure turn-script data, a pure/live split for both the execution step and the scoring step (mirroring `gate-quality`'s existing `build_judge_prompt`/`run_judge` pattern), a stdlib-only Python acceptance test fixture, and orchestrator scripts that tie it together.

**Tech Stack:** Bash (existing suite conventions), Python 3.9+ stdlib only (`unittest`, `urllib.request`, `http.server` for manual verification only), `jq` for aggregation, `claude` CLI.

**Spec:** docs/superpowers/specs/2026-08-16-outcome-benchmark-design.md
**Architecture doc:** docs/superpowers/specs/2026-08-16-outcome-benchmark-architecture.md
**Program design (interface contract):** docs/superpowers/specs/2026-08-16-outcome-benchmark-program-design.md — task-level signatures below match this document exactly. Three internal pure-function helpers not named in that doc are introduced during planning (`_plugin_dir_flags`, `_build_execution_prompt`) — both are private implementation details behind already-approved public signatures (`run_turn`, `run_execution_step`), not new components, added to make those functions unit-testable without live `claude` calls, mirroring the existing `build_judge_prompt`/`run_judge` split used by every `gate-quality` suite.

## Global Constraints

- No third-party dependencies anywhere in this suite — Python code (fixture and agent-generated `serve.py`) is stdlib-only (`unittest`, `urllib.request`); no `pyproject.toml`/`requirements.txt`.
- Python version floor: 3.9+, documented in the suite's README, not CI-enforced (Python never runs in CI for this suite).
- No linting or type-checking pipeline introduced — matches the repo's existing lint-free convention.
- Sequential trial execution only — `score.sh`'s hardcoded port 8000 depends on trials never running concurrently.
- `execute.sh`'s `claude -p` call passes no `--plugin-dir` flags at all, for either condition — the one deliberately-identical step between treatment and baseline.
- The live trial suite (`run-all.sh`, `run-trial.sh`, real `claude -p` calls) is not run in CI — real tokens, real time, non-deterministic, manual/occasional diagnostic, same stance as `gate-routing`/`gate-quality`.
- Every pure/deterministic parsing or templating function (no live calls, no subprocess) gets a unit test wired into `.github/workflows/ci.yml`'s `fast-tests` job — this applies uniformly to `test-common.sh`, `test-execute.sh`, and `test-scoring.sh` alike, not just the one file the program design doc named explicitly.

---

## Task 1: `run_turn` support for an empty `factory_gates_dir`

**Files:**
- Modify: `tests/gate-routing/lib/common.sh`
- Create: `tests/gate-routing/test-common.sh`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `_plugin_dir_flags(superpowers_dir, factory_gates_dir)` — prints one flag/value per line to stdout; omits the `--plugin-dir`/value pair for `factory_gates_dir` when it's `""`.
- Produces: `run_turn(project_dir, prompt, do_continue, superpowers_dir, factory_gates_dir, log_file)` — same external signature as today; `factory_gates_dir` may now be `""`.

- [ ] **Step 1: Write the failing test**

Create `tests/gate-routing/test-common.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for common.sh's _plugin_dir_flags -- pure text/array
# construction, no live claude calls, no subprocess.
# Usage: ./test-common.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
set +e

PASS=0
FAIL=0

assert_eq() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $description"
        echo "  expected: $expected"
        echo "  actual:   $actual"
    fi
}

RESULT="$(_plugin_dir_flags "/path/to/superpowers" "/path/to/factory-gates")"
assert_eq "both dirs -> four lines, both --plugin-dir pairs" \
"--plugin-dir
/path/to/superpowers
--plugin-dir
/path/to/factory-gates" "$RESULT"

RESULT="$(_plugin_dir_flags "/path/to/superpowers" "")"
assert_eq "empty factory_gates_dir -> only the superpowers pair" \
"--plugin-dir
/path/to/superpowers" "$RESULT"

echo ""
echo "Passed: $PASS, Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/gate-routing/test-common.sh && tests/gate-routing/test-common.sh`
Expected: FAIL with "command not found: _plugin_dir_flags" (function doesn't exist yet).

- [ ] **Step 3: Implement `_plugin_dir_flags` and update `run_turn`**

In `tests/gate-routing/lib/common.sh`, add before `run_turn`:

```bash
# Prints one --plugin-dir flag (and its value) per line for the given
# superpowers/factory-gates directories, in the order claude expects them
# on argv. Pure function -- no subprocess, no side effects. If
# factory_gates_dir is "", its --plugin-dir pair is omitted entirely
# (used by the outcome-benchmark suite's baseline condition, which must
# run with no factory-gates plugin loaded at all).
# Usage: mapfile -t flags < <(_plugin_dir_flags <superpowers-dir> <factory-gates-dir|"">)
_plugin_dir_flags() {
    local superpowers_dir="$1"
    local factory_gates_dir="$2"
    printf '%s\n' "--plugin-dir" "$superpowers_dir"
    if [ -n "$factory_gates_dir" ]; then
        printf '%s\n' "--plugin-dir" "$factory_gates_dir"
    fi
}
```

Replace `run_turn`'s body with:

```bash
# Run one conversation turn.
# Usage: run_turn <project-dir> <prompt> <do_continue: 0|1> <superpowers-dir> <factory-gates-dir|""> <log-file>
# factory-gates-dir may be "" -- when empty, the --plugin-dir flag for it
# is omitted entirely (not passed as an empty path).
run_turn() {
    local project_dir="$1"
    local prompt="$2"
    local do_continue="$3"
    local superpowers_dir="$4"
    local factory_gates_dir="$5"
    local log_file="$6"

    local continue_flag=()
    if [ "$do_continue" = "1" ]; then
        continue_flag=(--continue)
    fi

    local plugin_flags=()
    mapfile -t plugin_flags < <(_plugin_dir_flags "$superpowers_dir" "$factory_gates_dir")

    (
        cd "$project_dir"
        timeout 300 claude -p "$prompt" \
            "${continue_flag[@]+"${continue_flag[@]}"}" \
            "${plugin_flags[@]}" \
            --dangerously-skip-permissions \
            --max-turns 3 \
            --output-format stream-json \
            --verbose \
            > "$log_file" 2>&1 || true
    )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `tests/gate-routing/test-common.sh`
Expected: `Passed: 2, Failed: 0`

- [ ] **Step 5: Wire into CI**

In `.github/workflows/ci.yml`, add a new step to the `fast-tests` job, before the `architecture-gate` step:

```yaml
      - name: Run gate-routing common.sh unit tests
        run: tests/gate-routing/test-common.sh
```

- [ ] **Step 6: Commit**

```bash
git add tests/gate-routing/lib/common.sh tests/gate-routing/test-common.sh .github/workflows/ci.yml
git commit -m "feat(tests): let run_turn omit the factory-gates plugin dir"
```

---

## Task 2: Shared turn scripts (`turns.sh`)

**Files:**
- Create: `tests/outcome-benchmark/lib/turns.sh`

**Interfaces:**
- Produces: `FEATURE_REQUEST` (string), `TREATMENT_TURNS` (12-element array), `BASELINE_TURNS` (6-element array) — pure data, no functions.

- [ ] **Step 1: Create the file**

`tests/outcome-benchmark/lib/turns.sh`:

```bash
# Shared feature request and turn scripts for tests/outcome-benchmark's
# two conditions. Sourced by run-trial.sh. Pure data -- no functions.

FEATURE_REQUEST="I want to build a small URL shortener, implemented in Python using only the standard library. Two components: a public redirect service that takes a short code and 302-redirects to the original URL, and an admin API for creating new short links (POST with a target URL, returns a short code). Both read/write the same data store (short code -> target URL mapping). Redirect latency matters -- it's on the hot path for every click. No user accounts, no analytics, no custom short codes (always generated). That's the complete design -- no open questions on my end."

# treatment: brainstorming -> architecture-gate -> program-design-gate ->
# writing-plans -> vertical-slices-gate (12 turns, verbatim from
# tests/gate-quality/vertical-slices-gate/run-trial.sh)
TREATMENT_TURNS=(
    "$FEATURE_REQUEST"
    "That approach looks good -- please continue."
    "Approved. Please write the spec and commit it."
    "I've reviewed the spec, it looks good, please proceed."
    "That architecture approach looks good -- please continue."
    "Approved. Please write the architecture doc."
    "I've reviewed the architecture doc, it looks good, please proceed."
    "Approved. Please write the program design doc."
    "I've reviewed the program design doc, it looks good, please proceed."
    "Approved. Please write the implementation plan."
    "I've reviewed the plan, it looks good."
    "Confirmed, that build order looks right."
)

# baseline: brainstorming -> writing-plans only, no factory-gates loaded
BASELINE_TURNS=(
    "$FEATURE_REQUEST"
    "That approach looks good -- please continue."
    "Approved. Please write the spec and commit it."
    "I've reviewed the spec, it looks good, please proceed to plan the implementation."
    "That implementation approach looks good -- please write the plan."
    "I've reviewed the plan, it looks good."
)
```

- [ ] **Step 2: Verify array contents**

Run: `bash -c 'source tests/outcome-benchmark/lib/turns.sh; echo "${#TREATMENT_TURNS[@]} ${#BASELINE_TURNS[@]}"; echo "${TREATMENT_TURNS[0]}" | head -c 40; echo; echo "${BASELINE_TURNS[0]}" | head -c 40'`
Expected: `12 6`, and both first-line previews start with "I want to build a small URL shortener".

- [ ] **Step 3: Commit**

```bash
git add tests/outcome-benchmark/lib/turns.sh
git commit -m "feat(tests): add outcome-benchmark turn scripts"
```

---

## Task 3: Acceptance test fixture (`acceptance_tests.py`)

**Files:**
- Create: `tests/outcome-benchmark/fixtures/acceptance_tests.py`

**Interfaces:**
- Consumes: nothing (standalone script; talks to whatever server is running at `BASE_URL` over HTTP).
- Produces: a `unittest`-discoverable module. Running `python3 acceptance_tests.py -v` against a compliant server exits 0 with an `OK` summary; against a non-compliant one, exits nonzero with a `FAILED (...)` summary. This is the exact output `score.sh`'s `parse_unittest_output` (Task 4) parses.

- [ ] **Step 1: Write the fixture**

`tests/outcome-benchmark/fixtures/acceptance_tests.py`:

```python
#!/usr/bin/env python3
"""Black-box HTTP acceptance tests for the outcome-benchmark's pinned URL
shortener contract. Stdlib only. Run directly against a server already
listening at BASE_URL: python3 acceptance_tests.py -v
"""

import json
import unittest
import urllib.error
import urllib.request

BASE_URL = "http://localhost:8000"


def _request(method, path, body_bytes=None):
    req = urllib.request.Request(
        BASE_URL + path,
        data=body_bytes,
        headers={"Content-Type": "application/json"} if body_bytes is not None else {},
        method=method,
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def _post_link(url):
    """POST {"url": url} to BASE_URL/api/links.
    Returns (status_code, parsed_json_body); body is {} if the response
    wasn't valid JSON."""
    status, body = _request("POST", "/api/links", json.dumps({"url": url}).encode("utf-8"))
    return status, _parse_json(body)


def _post_raw(body_bytes):
    """POST raw bytes (not necessarily valid JSON) to BASE_URL/api/links.
    Returns (status_code, parsed_json_body_or_empty)."""
    status, body = _request("POST", "/api/links", body_bytes)
    return status, _parse_json(body)


def _parse_json(body_bytes):
    try:
        return json.loads(body_bytes) if body_bytes else {}
    except json.JSONDecodeError:
        return {}


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


_NO_REDIRECT_OPENER = urllib.request.build_opener(_NoRedirect)


def _get(path):
    """GET BASE_URL + path, redirects NOT followed.
    Returns (status_code, response_headers)."""
    req = urllib.request.Request(BASE_URL + path, method="GET")
    try:
        with _NO_REDIRECT_OPENER.open(req) as resp:
            return resp.status, dict(resp.headers)
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers)


class AcceptanceTests(unittest.TestCase):
    def test_create_then_redirect(self):
        status, body = _post_link("https://example.com/target-one")
        self.assertEqual(status, 201)
        code = body.get("code")
        self.assertTrue(code, "response body must include a non-empty 'code'")

        redirect_status, headers = _get("/" + code)
        self.assertEqual(redirect_status, 302)
        self.assertEqual(headers.get("Location"), "https://example.com/target-one")

    def test_unknown_code_returns_404(self):
        status, _ = _get("/this-code-was-never-created")
        self.assertEqual(status, 404)

    def test_malformed_create_request(self):
        status, _ = _post_raw(b"not valid json")
        self.assertTrue(400 <= status < 500, "expected 4xx for invalid JSON, got %r" % status)

        status2, _ = _post_raw(json.dumps({}).encode("utf-8"))
        self.assertTrue(400 <= status2 < 500, "expected 4xx for missing url, got %r" % status2)

    def test_duplicate_url_each_code_redirects_correctly(self):
        status_a, body_a = _post_link("https://example.com/duplicate-target")
        status_b, body_b = _post_link("https://example.com/duplicate-target")
        self.assertEqual(status_a, 201)
        self.assertEqual(status_b, 201)

        for body in (body_a, body_b):
            code = body.get("code")
            self.assertTrue(code)
            redirect_status, headers = _get("/" + code)
            self.assertEqual(redirect_status, 302)
            self.assertEqual(headers.get("Location"), "https://example.com/duplicate-target")

    def test_code_collision_safety(self):
        created = {}
        for i in range(25):
            url = "https://example.com/collision-check-%d" % i
            status, body = _post_link(url)
            self.assertEqual(status, 201)
            code = body.get("code")
            self.assertTrue(code)
            if code in created:
                self.assertEqual(
                    created[code], url,
                    "code %r was returned for two different URLs" % code,
                )
            created[code] = url

        for code, url in created.items():
            redirect_status, headers = _get("/" + code)
            self.assertEqual(redirect_status, 302)
            self.assertEqual(headers.get("Location"), url)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Verify against a throwaway reference server**

Write a throwaway (not committed) reference server implementing the pinned contract correctly, to prove the acceptance tests both pass against correct behavior and fail against incorrect behavior:

```bash
cat > /tmp/reference_serve.py <<'EOF'
import json, random, string
from http.server import BaseHTTPRequestHandler, HTTPServer

STORE = {}

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/api/links":
            self.send_response(404); self.end_headers(); return
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            data = None
        url = data.get("url") if isinstance(data, dict) else None
        if not url:
            self.send_response(400); self.end_headers(); return
        code = "".join(random.choices(string.ascii_lowercase + string.digits, k=6))
        STORE[code] = url
        body = json.dumps({"code": code}).encode()
        self.send_response(201)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        code = self.path.lstrip("/")
        url = STORE.get(code)
        if url is None:
            self.send_response(404); self.end_headers(); return
        self.send_response(302)
        self.send_header("Location", url)
        self.end_headers()

if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 8000), Handler).serve_forever()
EOF
python3 /tmp/reference_serve.py &
SERVER_PID=$!
sleep 1
python3 tests/outcome-benchmark/fixtures/acceptance_tests.py -v
kill $SERVER_PID
```

Expected: `Ran 5 tests` / `OK`. Then edit `/tmp/reference_serve.py` to return the wrong `Location` header and re-run — expected: `test_create_then_redirect` now fails, proving the test suite actually detects incorrect behavior, not just "server responds at all." Delete `/tmp/reference_serve.py` when done.

- [ ] **Step 3: Commit**

```bash
git add tests/outcome-benchmark/fixtures/acceptance_tests.py
git commit -m "feat(tests): add outcome-benchmark acceptance test fixture"
```

---

## Task 4: `score.sh`'s `parse_unittest_output` + `test-scoring.sh` + CI

**Files:**
- Create: `tests/outcome-benchmark/lib/score.sh` (this task: `parse_unittest_output` only)
- Create: `tests/outcome-benchmark/test-scoring.sh`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `parse_unittest_output(output_file)` — prints `"<passed> <total>"` to stdout.

- [ ] **Step 1: Write the failing test**

`tests/outcome-benchmark/test-scoring.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for lib/score.sh's parse_unittest_output. Pure text parsing,
# no subprocess, no network, no live claude -p calls -- fast and
# deterministic. Usage: ./test-scoring.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/score.sh
source "$SCRIPT_DIR/lib/score.sh"
set +e

PASS=0
FAIL=0

assert_eq() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $description"
        echo "  expected: $expected"
        echo "  actual:   $actual"
    fi
}

TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

cat > "$TMPFILE" <<'EOF'
test_create_then_redirect (acceptance_tests.AcceptanceTests.test_create_then_redirect) ... ok
test_unknown_code_returns_404 (acceptance_tests.AcceptanceTests.test_unknown_code_returns_404) ... ok

----------------------------------------------------------------------
Ran 2 tests in 0.014s

OK
EOF
assert_eq "all pass -> passed == total" "2 2" "$(parse_unittest_output "$TMPFILE")"

cat > "$TMPFILE" <<'EOF'
test_create_then_redirect (acceptance_tests.AcceptanceTests.test_create_then_redirect) ... ok
test_unknown_code_returns_404 (acceptance_tests.AcceptanceTests.test_unknown_code_returns_404) ... FAIL

======================================================================
FAIL: test_unknown_code_returns_404 (acceptance_tests.AcceptanceTests.test_unknown_code_returns_404)
----------------------------------------------------------------------
AssertionError: 200 != 404

----------------------------------------------------------------------
Ran 2 tests in 0.014s

FAILED (failures=1)
EOF
assert_eq "one failure -> passed = total - failures" "1 2" "$(parse_unittest_output "$TMPFILE")"

cat > "$TMPFILE" <<'EOF'
test_create_then_redirect (acceptance_tests.AcceptanceTests.test_create_then_redirect) ... ERROR

----------------------------------------------------------------------
Ran 5 tests in 0.041s

FAILED (failures=1, errors=1)
EOF
assert_eq "failures and errors both subtracted" "3 5" "$(parse_unittest_output "$TMPFILE")"

cat > "$TMPFILE" <<'EOF'
Traceback (most recent call last):
  File "acceptance_tests.py", line 4, in <module>
    import nonexistent_module
ModuleNotFoundError: No module named 'nonexistent_module'
EOF
assert_eq "crashed output, no summary line -> 0 0" "0 0" "$(parse_unittest_output "$TMPFILE")"

: > "$TMPFILE"
assert_eq "empty file -> 0 0" "0 0" "$(parse_unittest_output "$TMPFILE")"

echo ""
echo "Passed: $PASS, Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/outcome-benchmark/test-scoring.sh && tests/outcome-benchmark/test-scoring.sh`
Expected: FAIL — `lib/score.sh` doesn't exist yet, so sourcing it errors out.

- [ ] **Step 3: Implement `parse_unittest_output`**

`tests/outcome-benchmark/lib/score.sh`:

```bash
#!/usr/bin/env bash
# Scoring mechanics for tests/outcome-benchmark. Sourced by run-trial.sh.

set -euo pipefail

# Usage: parse_unittest_output <output-file>
# Pure text parser -- no subprocess, no network. Reads the output of
# `python3 <script> -v` (unittest's verbose format) from <output-file>.
# Extracts the total test count from a "Ran N tests" line, and the passed
# count as: total (if a bare "OK" line follows), or total - failures -
# errors (if a "FAILED (failures=N[, errors=M])" line follows). Prints
# "<passed> <total>" to stdout. Prints "0 0" if no recognizable summary
# line is found (crashed or truncated output).
parse_unittest_output() {
    local output_file="$1"
    local total
    total="$(grep -oE '^Ran [0-9]+ tests? in' "$output_file" 2>/dev/null | grep -oE '[0-9]+' | head -1)"

    if [ -z "$total" ]; then
        echo "0 0"
        return
    fi

    if grep -qE '^OK$' "$output_file" 2>/dev/null; then
        echo "$total $total"
        return
    fi

    local failed_line
    failed_line="$(grep -E '^FAILED \(' "$output_file" 2>/dev/null | head -1)"
    if [ -n "$failed_line" ]; then
        local failures errors
        failures="$(printf '%s' "$failed_line" | grep -oE 'failures=[0-9]+' | grep -oE '[0-9]+')"
        errors="$(printf '%s' "$failed_line" | grep -oE 'errors=[0-9]+' | grep -oE '[0-9]+')"
        failures="${failures:-0}"
        errors="${errors:-0}"
        echo "$((total - failures - errors)) $total"
        return
    fi

    echo "0 0"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `tests/outcome-benchmark/test-scoring.sh`
Expected: `Passed: 5, Failed: 0`

- [ ] **Step 5: Wire into CI**

In `.github/workflows/ci.yml`, add after the `vertical-slices-gate` step:

```yaml
      - name: Run outcome-benchmark scoring unit tests
        run: tests/outcome-benchmark/test-scoring.sh
```

- [ ] **Step 6: Commit**

```bash
git add tests/outcome-benchmark/lib/score.sh tests/outcome-benchmark/test-scoring.sh .github/workflows/ci.yml
git commit -m "feat(tests): add outcome-benchmark unittest-output parser"
```

---

## Task 5: `score.sh`'s `run_acceptance_tests`

**Files:**
- Modify: `tests/outcome-benchmark/lib/score.sh`

**Interfaces:**
- Consumes: `parse_unittest_output` (Task 4, same file).
- Produces: `run_acceptance_tests(project_dir, [output_log_file])` — prints `"<passed> <total>"` to stdout.

- [ ] **Step 1: Implement `run_acceptance_tests`**

Append to `tests/outcome-benchmark/lib/score.sh`:

```bash
# Usage: run_acceptance_tests <project-dir> [output-log-file]
# Independently re-checks for <project-dir>/serve.py (does not trust
# execute.sh's own "true"/"false" signal) and prints "0 0" immediately
# if it's missing. Otherwise starts `python3 serve.py` as a background
# subprocess in <project-dir>, polls 127.0.0.1:8000 for up to 10s (20
# attempts, 0.5s apart). If the port never opens, kills the subprocess
# and prints "0 0". If it opens, runs fixtures/acceptance_tests.py -v
# against it, captures output to [output-log-file] (default /dev/null),
# always kills the subprocess afterward, and prints
# parse_unittest_output's result.
run_acceptance_tests() {
    local project_dir="$1"
    local output_log="${2:-/dev/null}"
    local fixtures_dir
    fixtures_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"

    if [ ! -f "$project_dir/serve.py" ]; then
        echo "0 0"
        return
    fi

    local server_log
    server_log="$(mktemp)"
    (cd "$project_dir" && exec python3 serve.py) > "$server_log" 2>&1 &
    local server_pid=$!

    local port_open=false
    local attempt
    for attempt in $(seq 1 20); do
        if (exec 3<>/dev/tcp/127.0.0.1/8000) 2>/dev/null; then
            port_open=true
            break
        fi
        sleep 0.5
    done

    if [ "$port_open" != "true" ]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
        rm -f "$server_log"
        echo "0 0"
        return
    fi

    local test_output
    test_output="$(mktemp)"
    python3 "$fixtures_dir/acceptance_tests.py" -v > "$test_output" 2>&1 || true

    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true

    cp "$test_output" "$output_log" 2>/dev/null || true

    local counts
    counts="$(parse_unittest_output "$test_output")"
    rm -f "$server_log" "$test_output"
    echo "$counts"
}
```

- [ ] **Step 2: Verify against the Task 3 reference server**

```bash
mkdir -p /tmp/score-sh-check
cat > /tmp/score-sh-check/serve.py <<'EOF'
import json, random, string
from http.server import BaseHTTPRequestHandler, HTTPServer

STORE = {}

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/api/links":
            self.send_response(404); self.end_headers(); return
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            data = None
        url = data.get("url") if isinstance(data, dict) else None
        if not url:
            self.send_response(400); self.end_headers(); return
        code = "".join(random.choices(string.ascii_lowercase + string.digits, k=6))
        STORE[code] = url
        body = json.dumps({"code": code}).encode()
        self.send_response(201)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        code = self.path.lstrip("/")
        url = STORE.get(code)
        if url is None:
            self.send_response(404); self.end_headers(); return
        self.send_response(302)
        self.send_header("Location", url)
        self.end_headers()

if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 8000), Handler).serve_forever()
EOF

bash -c 'source tests/outcome-benchmark/lib/score.sh; run_acceptance_tests /tmp/score-sh-check /tmp/score-sh-check/output.txt'
```

Expected: prints `5 5`. Then run again with `/tmp/score-sh-check/serve.py` deleted — expected: prints `0 0` immediately (no wait). Then restore it but make it `exit(1)` immediately on startup instead of serving — expected: prints `0 0` after the ~10s poll timeout (port never opens). Clean up: `rm -rf /tmp/score-sh-check`.

- [ ] **Step 3: Commit**

```bash
git add tests/outcome-benchmark/lib/score.sh
git commit -m "feat(tests): add outcome-benchmark run_acceptance_tests"
```

---

## Task 6: `execute.sh`

**Files:**
- Create: `tests/outcome-benchmark/lib/execute.sh`
- Create: `tests/outcome-benchmark/test-execute.sh`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `_build_execution_prompt(plan_path, spec_path)` — prints the fixed prompt text to stdout.
- Produces: `run_execution_step(project_dir, plan_path, spec_path, log_file)` — prints `"true"`/`"false"` to stdout based on whether `<project_dir>/serve.py` exists afterward.

- [ ] **Step 1: Write the failing test**

`tests/outcome-benchmark/test-execute.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for lib/execute.sh's _build_execution_prompt. Pure string
# templating, no live claude -p calls. Usage: ./test-execute.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/execute.sh
source "$SCRIPT_DIR/lib/execute.sh"
set +e

PASS=0
FAIL=0

PROMPT_OUTPUT="$(_build_execution_prompt "/tmp/project/docs/superpowers/plans/plan.md" "/tmp/project/docs/superpowers/specs/spec-design.md")"

check() {
    local description="$1"
    local needle="$2"
    if printf '%s' "$PROMPT_OUTPUT" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $description"
    fi
}

check "embeds the plan path" "/tmp/project/docs/superpowers/plans/plan.md"
check "embeds the spec path" "/tmp/project/docs/superpowers/specs/spec-design.md"
check "pins the POST contract" "POST /api/links"
check "pins the redirect contract" "GET /<code> -> 302"
check "pins the 404 contract" "unknown code -> 404"
check "pins the exact startup command" "python3 serve.py"

echo ""
echo "Passed: $PASS, Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x tests/outcome-benchmark/test-execute.sh && tests/outcome-benchmark/test-execute.sh`
Expected: FAIL — `lib/execute.sh` doesn't exist yet.

- [ ] **Step 3: Implement `execute.sh`**

`tests/outcome-benchmark/lib/execute.sh`:

```bash
#!/usr/bin/env bash
# Execution-phase mechanics for tests/outcome-benchmark. Sourced by
# run-trial.sh.

set -euo pipefail

# Usage: _build_execution_prompt <plan-path> <spec-path>
# Pure string template -- prints the fixed, identical-for-both-conditions
# implementation prompt to stdout, with the two paths interpolated.
_build_execution_prompt() {
    local plan_path="$1"
    local spec_path="$2"
    cat <<PROMPT_EOF
Implement the plan at $plan_path completely, in this repository. The approved spec is at $spec_path for reference. Regardless of what the plan or spec say about transport details, the final result must expose exactly this HTTP contract, since it will be tested automatically:

- POST /api/links with JSON body {"url": "<target>"} -> 201 with JSON body {"code": "<short code>"}
- GET /<code> -> 302 with Location set to the stored target URL
- GET /<code> for an unknown code -> 404
- The service must be startable from the project root with exactly: python3 serve.py, listening on port 8000.

Implement real, working behavior -- not stubs. When finished, confirm the server starts cleanly with that exact command.
PROMPT_EOF
}

# Usage: run_execution_step <project-dir> <plan-path> <spec-path> <log-file>
# Runs ONE unscripted claude -p call in <project-dir>, with NO
# --plugin-dir flags at all (identical for both conditions), --max-turns
# 40, wrapped in `timeout 1800`. Prints "true" to stdout if
# <project-dir>/serve.py exists after the call returns, else "false" --
# an existence check only, not proof the server works.
run_execution_step() {
    local project_dir="$1"
    local plan_path="$2"
    local spec_path="$3"
    local log_file="$4"

    local prompt
    prompt="$(_build_execution_prompt "$plan_path" "$spec_path")"

    (
        cd "$project_dir"
        timeout 1800 claude -p "$prompt" \
            --dangerously-skip-permissions \
            --max-turns 40 \
            --output-format stream-json \
            --verbose \
            > "$log_file" 2>&1 || true
    )

    if [ -f "$project_dir/serve.py" ]; then
        echo "true"
    else
        echo "false"
    fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `tests/outcome-benchmark/test-execute.sh`
Expected: `Passed: 6, Failed: 0`

- [ ] **Step 5: Wire into CI**

In `.github/workflows/ci.yml`, add after the `outcome-benchmark scoring unit tests` step:

```yaml
      - name: Run outcome-benchmark execute.sh unit tests
        run: tests/outcome-benchmark/test-execute.sh
```

- [ ] **Step 6: Commit**

```bash
git add tests/outcome-benchmark/lib/execute.sh tests/outcome-benchmark/test-execute.sh .github/workflows/ci.yml
git commit -m "feat(tests): add outcome-benchmark execution step"
```

---

## Task 7: `run-trial.sh`

**Files:**
- Create: `tests/outcome-benchmark/run-trial.sh`

**Interfaces:**
- Consumes: `resolve_superpowers_dir`, `resolve_factory_gates_dir`, `setup_trial_dir`, `run_turn`, `skill_invoked_in` (`tests/gate-routing/lib/common.sh`); `TREATMENT_TURNS`, `BASELINE_TURNS` (`lib/turns.sh`); `run_execution_step` (`lib/execute.sh`); `run_acceptance_tests` (`lib/score.sh`).
- Produces: `trial-dir/result.json` matching the design spec's schema, plus `trial-dir/turnN.json`, `trial-dir/execution.json`, `trial-dir/acceptance-test-output.txt`.

- [ ] **Step 1: Implement `run-trial.sh`**

`tests/outcome-benchmark/run-trial.sh`:

```bash
#!/usr/bin/env bash
# Run a single outcome-benchmark trial for one condition.
# Usage: run-trial.sh <treatment|baseline> <trial-output-dir>
#
# treatment: brainstorming -> architecture-gate -> program-design-gate ->
#   writing-plans -> vertical-slices-gate (factory-gates loaded)
# baseline: brainstorming -> writing-plans only (factory-gates NOT loaded)
#
# Both conditions then go through one identical, plugin-free execution
# step and are scored against the same fixed acceptance test suite. See
# docs/superpowers/specs/2026-08-16-outcome-benchmark-design.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../gate-routing/lib/common.sh
source "$SCRIPT_DIR/../gate-routing/lib/common.sh"
# shellcheck source=lib/turns.sh
source "$SCRIPT_DIR/lib/turns.sh"
# shellcheck source=lib/execute.sh
source "$SCRIPT_DIR/lib/execute.sh"
# shellcheck source=lib/score.sh
source "$SCRIPT_DIR/lib/score.sh"

CONDITION="${1:-}"
TRIAL_DIR="${2:-}"

if [ "$CONDITION" != "treatment" ] && [ "$CONDITION" != "baseline" ]; then
    echo "Usage: $0 <treatment|baseline> <trial-output-dir>" >&2
    exit 1
fi
if [ -z "$TRIAL_DIR" ]; then
    echo "Usage: $0 <treatment|baseline> <trial-output-dir>" >&2
    exit 1
fi

SUPERPOWERS_DIR="$(resolve_superpowers_dir)"
FACTORY_GATES_DIR="$(resolve_factory_gates_dir)"

if [ "$CONDITION" = "treatment" ]; then
    TURNS=("${TREATMENT_TURNS[@]}")
    RUN_FACTORY_GATES_DIR="$FACTORY_GATES_DIR"
else
    TURNS=("${BASELINE_TURNS[@]}")
    RUN_FACTORY_GATES_DIR=""
fi

mkdir -p "$TRIAL_DIR"
PROJECT_DIR="$(setup_trial_dir "$TRIAL_DIR")"

BRAINSTORMING_TRIGGERED=false
ARCHITECTURE_GATE_TRIGGERED=false
PROGRAM_DESIGN_GATE_TRIGGERED=false
VERTICAL_SLICES_GATE_TRIGGERED=false
TURNS_USED=0

for i in "${!TURNS[@]}"; do
    TURN_NUM=$((i + 1))
    TURNS_USED=$TURN_NUM
    PROMPT="${TURNS[$i]}"
    LOG_FILE="$TRIAL_DIR/turn${TURN_NUM}.json"

    if [ "$TURN_NUM" = "1" ]; then
        run_turn "$PROJECT_DIR" "$PROMPT" 0 "$SUPERPOWERS_DIR" "$RUN_FACTORY_GATES_DIR" "$LOG_FILE"
    else
        run_turn "$PROJECT_DIR" "$PROMPT" 1 "$SUPERPOWERS_DIR" "$RUN_FACTORY_GATES_DIR" "$LOG_FILE"
    fi

    if [ "$BRAINSTORMING_TRIGGERED" = "false" ] && skill_invoked_in "$LOG_FILE" "brainstorming"; then
        BRAINSTORMING_TRIGGERED=true
    fi
    if [ "$ARCHITECTURE_GATE_TRIGGERED" = "false" ] && skill_invoked_in "$LOG_FILE" "architecture-gate"; then
        ARCHITECTURE_GATE_TRIGGERED=true
    fi
    if [ "$PROGRAM_DESIGN_GATE_TRIGGERED" = "false" ] && skill_invoked_in "$LOG_FILE" "program-design-gate"; then
        PROGRAM_DESIGN_GATE_TRIGGERED=true
    fi
    if [ "$VERTICAL_SLICES_GATE_TRIGGERED" = "false" ] && skill_invoked_in "$LOG_FILE" "vertical-slices-gate"; then
        VERTICAL_SLICES_GATE_TRIGGERED=true
    fi
done

PLAN_PATH="$(find "$PROJECT_DIR/docs/superpowers/plans" -name '*.md' -print -quit 2>/dev/null || true)"
SPEC_PATH="$(find "$PROJECT_DIR/docs/superpowers/specs" -name '*-design.md' -print -quit 2>/dev/null || true)"

PLAN_FOUND=false
if [ -n "$PLAN_PATH" ]; then
    PLAN_FOUND=true
fi
SPEC_FOUND=false
if [ -n "$SPEC_PATH" ]; then
    SPEC_FOUND=true
fi

EXECUTION_COMPLETED=false
TESTS_PASSED=0
TESTS_TOTAL=0

if [ "$PLAN_FOUND" = "true" ] && [ "$SPEC_FOUND" = "true" ]; then
    EXECUTION_LOG="$TRIAL_DIR/execution.json"
    SERVE_PY_EXISTS="$(run_execution_step "$PROJECT_DIR" "$PLAN_PATH" "$SPEC_PATH" "$EXECUTION_LOG")"
    if [ "$SERVE_PY_EXISTS" = "true" ]; then
        EXECUTION_COMPLETED=true
        SCORE_LOG="$TRIAL_DIR/acceptance-test-output.txt"
        read -r TESTS_PASSED TESTS_TOTAL <<< "$(run_acceptance_tests "$PROJECT_DIR" "$SCORE_LOG")"
    fi
fi

OUTCOME="inconclusive"
if [ "$PLAN_FOUND" = "true" ] && [ "$SPEC_FOUND" = "true" ] && [ "$EXECUTION_COMPLETED" = "true" ] && [ "$TESTS_TOTAL" -gt 0 ]; then
    if [ "$TESTS_PASSED" -eq "$TESTS_TOTAL" ]; then
        OUTCOME="pass"
    else
        OUTCOME="fail"
    fi
fi

cat > "$TRIAL_DIR/result.json" <<EOF
{
  "trial_dir": "$TRIAL_DIR",
  "condition": "$CONDITION",
  "brainstorming_triggered": $BRAINSTORMING_TRIGGERED,
  "architecture_gate_triggered": $ARCHITECTURE_GATE_TRIGGERED,
  "program_design_gate_triggered": $PROGRAM_DESIGN_GATE_TRIGGERED,
  "vertical_slices_gate_triggered": $VERTICAL_SLICES_GATE_TRIGGERED,
  "plan_found": $PLAN_FOUND,
  "plan_path": "${PLAN_PATH:-}",
  "execution_completed": $EXECUTION_COMPLETED,
  "tests_passed": $TESTS_PASSED,
  "tests_total": $TESTS_TOTAL,
  "turns_used": $TURNS_USED,
  "outcome": "$OUTCOME"
}
EOF

echo "Trial complete: condition=$CONDITION outcome=$OUTCOME tests=$TESTS_PASSED/$TESTS_TOTAL turns_used=$TURNS_USED"
echo "Result: $TRIAL_DIR/result.json"

if [ "$OUTCOME" = "pass" ]; then
    exit 0
else
    exit 1
fi
```

- [ ] **Step 2: Verify argument validation (no live calls)**

Run: `chmod +x tests/outcome-benchmark/run-trial.sh && tests/outcome-benchmark/run-trial.sh`
Expected: prints usage to stderr, exits 1 (missing condition).

Run: `tests/outcome-benchmark/run-trial.sh bogus /tmp/whatever`
Expected: prints usage to stderr, exits 1 (invalid condition).

- [ ] **Step 3: Commit**

```bash
git add tests/outcome-benchmark/run-trial.sh
git commit -m "feat(tests): add outcome-benchmark run-trial.sh orchestrator"
```

---

## Task 8: `run-all.sh`

**Files:**
- Create: `tests/outcome-benchmark/run-all.sh`

**Interfaces:**
- Consumes: `run-trial.sh` (Task 7).
- Produces: `$RUN_DIR/summary.json` — `{"treatment": {...}, "baseline": {...}}`, each with `trials`, `pass`, `fail`, `inconclusive`, `mean_pass_rate`.

- [ ] **Step 1: Implement `run-all.sh`**

`tests/outcome-benchmark/run-all.sh`:

```bash
#!/usr/bin/env bash
# Run the full outcome-benchmark: N trials x 2 conditions (treatment,
# baseline), sequentially, and report a per-condition summary.
#
# Usage: run-all.sh [--trials N]
#   --trials N   Number of trials per condition (default: 3)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TRIALS=3

while [ $# -gt 0 ]; do
    case "$1" in
        --trials)
            TRIALS="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

TIMESTAMP=$(date +%s)
RUN_DIR="/tmp/factory-gates-outcome-benchmark/${TIMESTAMP}"
mkdir -p "$RUN_DIR"

echo "=== Outcome Benchmark Run ==="
echo "Trials per condition: $TRIALS"
echo "Output dir: $RUN_DIR"
echo ""

TREATMENT_RESULTS=()
for trial_num in $(seq 1 "$TRIALS"); do
    TRIAL_DIR="$RUN_DIR/treatment/trial-$trial_num"
    echo ">>> Running treatment trial $trial_num..."
    "$SCRIPT_DIR/run-trial.sh" treatment "$TRIAL_DIR" || true
    if [ -f "$TRIAL_DIR/result.json" ]; then
        TREATMENT_RESULTS+=("$TRIAL_DIR/result.json")
    else
        echo "WARNING: no result.json for treatment trial $trial_num (script likely crashed)" >&2
    fi
    echo ""
done

BASELINE_RESULTS=()
for trial_num in $(seq 1 "$TRIALS"); do
    TRIAL_DIR="$RUN_DIR/baseline/trial-$trial_num"
    echo ">>> Running baseline trial $trial_num..."
    "$SCRIPT_DIR/run-trial.sh" baseline "$TRIAL_DIR" || true
    if [ -f "$TRIAL_DIR/result.json" ]; then
        BASELINE_RESULTS+=("$TRIAL_DIR/result.json")
    else
        echo "WARNING: no result.json for baseline trial $trial_num (script likely crashed)" >&2
    fi
    echo ""
done

if [ "${#TREATMENT_RESULTS[@]}" -eq 0 ] || [ "${#BASELINE_RESULTS[@]}" -eq 0 ]; then
    echo "ERROR: at least one condition produced zero results -- the harness itself likely broke, not a measurement outcome" >&2
    exit 1
fi

summarize_condition() {
    local files=("$@")
    jq -s '
      {
        trials: length,
        pass: ([.[] | select(.outcome == "pass")] | length),
        fail: ([.[] | select(.outcome == "fail")] | length),
        inconclusive: ([.[] | select(.outcome == "inconclusive")] | length),
        mean_pass_rate: (
          [.[] | select(.outcome != "inconclusive") | (.tests_passed / .tests_total)] as $rates
          | if ($rates | length) > 0 then (($rates | add / ($rates | length)) * 100 | round) / 100 else null end
        )
      }
    ' "${files[@]}"
}

TREATMENT_SUMMARY="$(summarize_condition "${TREATMENT_RESULTS[@]}")"
BASELINE_SUMMARY="$(summarize_condition "${BASELINE_RESULTS[@]}")"

echo "=== Summary ==="
jq -n --argjson treatment "$TREATMENT_SUMMARY" --argjson baseline "$BASELINE_SUMMARY" \
    '{treatment: $treatment, baseline: $baseline}' | tee "$RUN_DIR/summary.json"

echo ""
echo "Full results: $RUN_DIR"
```

Note: unlike the older `gate-routing`/`gate-quality` suites, this script does not exit nonzero just because some trials came back `fail` — `fail` is a legitimate, expected measurement outcome here (an implementation that didn't pass every acceptance test), not a harness malfunction. It only exits nonzero if a whole condition produced zero results at all.

- [ ] **Step 2: Verify argument parsing**

Run: `chmod +x tests/outcome-benchmark/run-all.sh && tests/outcome-benchmark/run-all.sh --bogus-flag 2>&1 | head -1`
Expected: `Unknown argument: --bogus-flag`

- [ ] **Step 3: Commit**

```bash
git add tests/outcome-benchmark/run-all.sh
git commit -m "feat(tests): add outcome-benchmark run-all.sh batch runner"
```

---

## Task 9: README and end-to-end verification

**Files:**
- Create: `tests/outcome-benchmark/README.md`

- [ ] **Step 1: Write the README**

`tests/outcome-benchmark/README.md`:

```markdown
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

\`\`\`bash
# Default batch (3 trials per condition, 6 total -- likely 45-90+
# minutes, real token cost -- each trial now includes a full
# implementation pass, not just planning documents)
./run-all.sh

# Cheap single-trial-per-condition spot check while iterating on the
# harness itself
./run-all.sh --trials 1
\`\`\`

Requires: `claude` CLI installed and authenticated, `jq`, `python3` (3.9
or newer), and the Superpowers plugin installed locally (see
`../gate-routing/README.md` for the same prerequisites and
`SUPERPOWERS_PLUGIN_DIR` override).

Unit tests for the pure parsing/templating logic (fast, no live calls):

\`\`\`bash
./test-scoring.sh
./test-execute.sh
../gate-routing/test-common.sh
\`\`\`

## Reading the output

\`\`\`json
{
  "treatment": { "trials": 3, "pass": 2, "fail": 1, "inconclusive": 0, "mean_pass_rate": 0.87 },
  "baseline":  { "trials": 3, "pass": 1, "fail": 1, "inconclusive": 1, "mean_pass_rate": 0.53 }
}
\`\`\`

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
```

- [ ] **Step 2: Commit**

```bash
git add tests/outcome-benchmark/README.md
git commit -m "docs(tests): add outcome-benchmark README"
```

- [ ] **Step 3: End-to-end live smoke test (real cost -- confirm with the user before running)**

This step spends real tokens and real time (a full `treatment` and `baseline` trial, each including a live implementation pass) and should not be run silently. Confirm with the user first, then:

```bash
tests/outcome-benchmark/run-all.sh --trials 1
```

Confirm: both conditions produce a `result.json` with a non-`null` `outcome`; `summary.json` has the `{"treatment": {...}, "baseline": {...}}` shape from the design spec. A trial landing on `inconclusive` is an acceptable smoke-test result (it exercises the harness's own error paths) as long as `result.json`'s `*_triggered`/`plan_found`/`execution_completed` fields explain why. Do not treat a single trial's `pass`/`fail` outcome as a real signal — that requires the full `--trials 3` batch this task's README documents.
