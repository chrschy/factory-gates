# Python Code Standards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt BäckerAI-modeled Python code standards (numpydoc docstrings, readability conventions, ruff+ty tooling) for this repo, rewrite the one existing Python file to comply, wire enforcement into CI, and document the standards in CLAUDE.md.

**Architecture:** New `pyproject.toml` (tool config only). Rewritten `acceptance_tests.py`. Three new CI steps in the existing `fast-tests` job. New CLAUDE.md section.

**Tech Stack:** `ruff` 0.16.3, `ty` 0.0.72 (both exact-pinned).

## Global Constraints

- `ruff`/`ty` versions are exact-pinned everywhere (`pyproject.toml` doesn't pin runtime versions itself, but CI's `pip install` step and local verification both use `ruff==0.16.3 ty==0.0.72`) — never a floating/unpinned install.
- `target-version`/`python-version` is `py39`/`3.9` — matches the existing "Python 3.9+ floor" decision, not revisited.
- No behavior change to `acceptance_tests.py`'s test logic — only types, docstrings, and formatting.
- No `[project]`/`[build-system]` table in `pyproject.toml` — config-only, does not turn this repo into an installable package.

---

### Task 1: Add `pyproject.toml`

**Files:**
- Create: `pyproject.toml`

**Interfaces:** none

- [ ] **Step 1: Create the file**

```toml
[tool.ruff]
target-version = "py39"
line-length = 88

[tool.ruff.lint]
select = ["E", "F", "I", "W", "C901"]
extend-select = ["D"]

[tool.ruff.lint.pydocstyle]
convention = "numpy"

[tool.ruff.lint.mccabe]
max-complexity = 15

[tool.ty.environment]
python-version = "3.9"
```

- [ ] **Step 2: Commit**

```bash
git add pyproject.toml
git commit -m "chore(meta): add ruff/ty configuration"
```

---

### Task 2: Rewrite `acceptance_tests.py` to comply

**Files:**
- Modify: `tests/outcome-benchmark/fixtures/acceptance_tests.py`

**Interfaces:** none (internal test file, no other file imports from it)

- [ ] **Step 1: Add type hints and numpydoc docstrings to every function**

Apply throughout the file:
- `_request(method: str, path: str, body_bytes: bytes | None = None) -> tuple[int, bytes]` — one-line docstring.
- `_post_link(url: str) -> tuple[int, dict]` — one-line docstring.
- `_post_raw(body_bytes: bytes) -> tuple[int, dict]` — one-line docstring.
- `_parse_json(body_bytes: bytes) -> dict` — one-line docstring.
- `_NoRedirect.redirect_request(self, *args: object, **kwargs: object) -> None` — one-line docstring (magic-adjacent override, but not itself a dunder, so not exempt — give it one line).
- `_get(path: str) -> tuple[int, "email.message.Message"]` — one-line docstring (use `http.client.HTTPMessage` if more precise than the generic `email.message.Message` base — check which stdlib type `resp.headers`/`e.headers` actually is before annotating, don't guess).
- Every `test_*` method on `AcceptanceTests` gets `(self) -> None` and a one-line numpydoc summary of the property it verifies, e.g. `"""Verify a created link's code redirects to the original target URL."""`.

- [ ] **Step 2: Modernize `%`-style formatting to f-strings**

Two call sites currently use `%`-style formatting (`"expected 4xx for invalid JSON, got %r" % status`, `"code %r was returned for two different URLs" % code`, `"https://example.com/collision-check-%d" % i`) — convert each to an f-string with equivalent output, preserving the exact assertion messages' meaning.

- [ ] **Step 3: Run ruff and ty locally, fix anything they flag**

```bash
ruff check tests/outcome-benchmark/fixtures/acceptance_tests.py
ruff format --check tests/outcome-benchmark/fixtures/acceptance_tests.py
ty check tests/outcome-benchmark/fixtures/acceptance_tests.py
```

Expected: all three clean (no output / exit 0) after the rewrite. Fix anything flagged — don't add `# noqa`/`# type: ignore` suppressions without a concrete reason written as a comment.

- [ ] **Step 4: Confirm no behavior change**

```bash
python3 -m py_compile tests/outcome-benchmark/fixtures/acceptance_tests.py
```

Expected: no output (valid syntax). A full live run (actually exercising the HTTP assertions against a running server) isn't needed here — this task changes only types/docstrings/formatting, not assertion logic, and the file's real exercise happens later when the outcome-benchmark suite itself runs a live trial, unrelated to this change.

- [ ] **Step 5: Commit**

```bash
git add tests/outcome-benchmark/fixtures/acceptance_tests.py
git commit -m "refactor(tests): add type hints and numpydoc docstrings to acceptance_tests.py"
```

---

### Task 3: Wire ruff/ty into CI

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:** none

- [ ] **Step 1: Add the three steps to `fast-tests`, right after checkout**

Find:

```yaml
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Run release version-calc tests
```

Replace with:

```yaml
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Install Python lint/type-check tools
        run: pip install ruff==0.16.3 ty==0.0.72

      - name: Lint Python code
        run: ruff check .

      - name: Check Python formatting
        run: ruff format --check .

      - name: Type check Python code
        run: ty check

      - name: Run release version-calc tests
```

- [ ] **Step 2: Validate YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci(ci): add ruff and ty checks to fast-tests"
```

---

### Task 4: Document the standards in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:** none

- [ ] **Step 1: Add the new section**

Insert after the existing "## Testing" section, before "## See Also":

```markdown
## Python Code Standards

Applies to any Python file in this repo (currently
`tests/outcome-benchmark/fixtures/acceptance_tests.py`; applies to any
future Python code too). Modeled on
[data-science-kitchen/baeckerai](https://github.com/data-science-kitchen/baeckerai)'s
standards, enforced in CI (`fast-tests` job) and expected to be run
locally before opening a PR that touches Python:

```bash
ruff check .            # lint
ruff format --check .   # formatting (drop --check to auto-fix locally)
ty check                # type checking
```

`ty` is pre-1.0 software (Astral). CI pins an exact version
(`ty==0.0.72`) to avoid silent drift from its own changes — revisit this
choice if it proves unstable over time.

### Docstrings — numpydoc

All public functions, methods, and classes require
[numpydoc](https://numpydoc.readthedocs.io/en/latest/format.html)-format
docstrings — production code and test code equally. Private helpers
(single leading underscore) need at minimum a one-line summary. Magic
methods (`__init__`, `__repr__`) are exempt.

Test functions: type hints on every parameter, explicit `-> None` return
type. Unit test docstrings need at minimum a one-line summary of the
property being verified.

### Readability

- **Names say what something is**, not how it's implemented. Prefer 2-3
  word descriptive names (`document_path` over `p`). No cryptic
  abbreviations, no single-letter names outside mathematical contexts or
  standard idioms (`i` in a `range()` loop, `f` for a file handle, `exc`
  for a caught exception).
- **Functions start with an action verb** and do exactly one thing. If
  you need "and" to describe what a function does, split it.
- **Boolean-returning functions use question form** (`is_registered()`,
  not `check_registration()`).
- **Explicit over implicit.** State exact conditions
  (`if chunk_count >= 0:` not `if chunk_count:`) except for
  empty-collection guards (`if not nodes:`).
- **Comments explain why, not what.** If you feel the urge to explain
  what a block does, improve the names instead.
- **No function may exceed cyclomatic complexity 15** (enforced by
  ruff's `C901`).
```

- [ ] **Step 2: Verify placement and content**

```bash
grep -n "^## " CLAUDE.md
grep -c "numpydoc" CLAUDE.md
```

Expected: `## Python Code Standards` appears between `## Testing` and `## See Also`; `numpydoc` appears at least once.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(meta): document Python code standards"
```

---

### Task 5: Live verification, PR

**Files:** none (verification + git/GitHub operations only)

**Interfaces:** none

- [ ] **Step 1: Full local re-verification of everything together**

```bash
ruff check .
ruff format --check .
ty check
```

Expected: all three clean against the whole repo (not just the one file), confirming `pyproject.toml`'s config is correctly scoped and nothing else in the repo trips these checks.

- [ ] **Step 2: Push, open PR**

```bash
git push -u origin feature/python-code-standards
```

Open the PR with `gh pr create`, following this repo's established template: who's submitting, what problem (no Python standards existed; the outcome-benchmark architecture doc's "no lint pipeline" decision is being reversed, with the reason stated directly), what changed (tooling, rewritten file, CI wiring, CLAUDE.md section), which gate (none), alternatives considered (style-only vs. tooling-adopted -- tooling chosen; ty's pre-1.0 risk -- accepted with exact pinning, per explicit design-conversation decisions), existing-PRs checkbox, rigor section citing local ruff/ty runs and this PR's own live CI result, human-review checkbox unchecked.

- [ ] **Step 3: Confirm CI passes for real**

```bash
gh pr checks <PR-number>
```

Expected: `fast-tests` passes, including the three new steps. If `ruff`/`ty` fail in CI but passed locally, check for a version/environment mismatch before assuming the code is wrong.

- [ ] **Step 4: Report to human partner**

Show the complete diff (`git diff main...feature/python-code-standards`) and the PR URL. Per standing instruction, do not merge.

## Self-Review

1. **Spec coverage:** Task 1 (tooling config), Task 2 (file rewrite), Task 3 (CI), Task 4 (docs) map exactly to the design spec's four parts; Task 5 covers live verification and PR.
2. **Placeholder scan:** Task 2's exact type-hint signatures for `_get`/`_NoRedirect.redirect_request` are given with an explicit instruction to verify the real stdlib type rather than guess (`http.client.HTTPMessage` vs. the generic base) -- a deliberate "verify, don't assume" placeholder, not a gap.
3. **Type consistency:** the pinned versions (`ruff==0.16.3 ty==0.0.72`) are identical across `pyproject.toml`'s absence-of-pinning-there (config only), the CI step, and the PR body's rigor section -- no drift between where versions are stated.
