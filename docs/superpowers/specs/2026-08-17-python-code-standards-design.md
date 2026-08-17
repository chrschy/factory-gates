# factory-gates — Python Code Standards

**Status:** approved
**Date:** 2026-08-17

## Why

`tests/outcome-benchmark/fixtures/acceptance_tests.py` (this repo's only Python file) has no type hints, no numpydoc docstrings, and old-style `%` formatting. The outcome-benchmark architecture doc explicitly decided "no linting or type-checking pipeline for the new Python file," matching the repo's then-true "no lint step anywhere in CI" convention. This spec reverses that decision, adopting [data-science-kitchen/baeckerai](https://github.com/data-science-kitchen/baeckerai)'s Python standards (confirmed by request, verified directly from their `CONTRIBUTING.md` and `CLAUDE.md`, not paraphrased from memory) — both the conventions and the tooling that enforces them.

## Part A — Tooling

New `pyproject.toml` at repo root — config only, no `[project]`/`[build-system]` tables, so this does not turn the repo into an installable package:

```toml
[tool.ruff]
target-version = "py39"
line-length = 100

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

`target-version`/`python-version` match the "Python 3.9+ floor" already decided in the outcome-benchmark architecture doc — not revisited here. `D` rules (pydocstyle, numpy convention) mechanically enforce the numpydoc docstring requirement for public functions/classes; ruff's pydocstyle rules already exempt private (leading-underscore) members by default, which lines up with the "private needs only a one-line summary" policy without extra config.

**Versions, verified live against PyPI, not assumed:** `ruff` 0.16.3 (mature, stable), `ty` 0.0.72 (pre-1.0 — real instability risk, confirmed and accepted explicitly during design). CI pins both exactly (`ruff==0.16.3 ty==0.0.72`) to prevent silent drift from either tool's own changes, `ty` especially.

## Part B — CI wiring

Three new steps added to the existing `fast-tests` job in `.github/workflows/ci.yml` (not a new job — that job already blends heterogeneous fast/deterministic checks beyond literal unit tests, e.g. `test-common.sh`, `test-scoring.sh`; Python lint/type-check fits the job's actual existing scope):

```yaml
      - name: Install Python lint/type-check tools
        run: pip install ruff==0.16.3 ty==0.0.72

      - name: Lint Python code
        run: ruff check .

      - name: Check Python formatting
        run: ruff format --check .

      - name: Type check Python code
        run: ty check
```

Placed right after the checkout step, before the existing bash-script test steps.

## Part C — Rewrite `acceptance_tests.py`

Bring the file into compliance:
- Type hints on every function parameter and return type (including the test methods themselves, per the numpydoc test-documentation policy: `-> None`).
- numpydoc docstrings on the public `AcceptanceTests` test methods (one-line summary of the property verified, matching the "unit test" tier of the policy, not the fuller "integration test" tier — these are synchronous black-box HTTP tests, not async integration fixtures).
- One-line docstrings on private helpers (`_request`, `_post_link`, `_post_raw`, `_parse_json`, `_get`) that currently lack one; keep/tighten the ones that already have partial docstrings into single clear lines.
- Modernize `%`-style string formatting to f-strings (idiomatic-Python convention from the readability policy), while preserving every existing assertion and behavior exactly — this is a style pass, not a logic change.
- No behavior change: same test cases, same assertions, same HTTP contract exercised.

## Part D — CLAUDE.md section

New `## Python Code Standards` section (placed after the existing "Testing" section, before "See Also"), condensed from baeckerai's `CONTRIBUTING.md`/`CLAUDE.md` down to the parts that generalize beyond their project (docstrings, naming, function shape, comments, complexity, the tooling commands) — not copying their RAG-specific project content, which doesn't apply here. States the `ty` pre-1.0 caveat explicitly rather than silently matching baeckerai's presentation of it as equally mature to `ruff`.

## Verification

1. `pyproject.toml` and the CI YAML change both validated locally (`ruff check .`, `ruff format --check .`, `ty check` all run against the rewritten file before commit — not just written and assumed correct).
2. This PR's own `pull_request` trigger is the real end-to-end CI test for the new steps, same as every other CI addition in this repo's history — checked via `gh pr checks`, not assumed.
3. `python3 tests/outcome-benchmark/fixtures/acceptance_tests.py` behavior is unchanged — the rewrite doesn't touch test logic, only types/docstrings/formatting, so no new live-server test run is needed to prove behavioral equivalence, but the file's own unit-test structure (asserting HTTP contract behavior when actually run against a server) stays intact for future benchmark runs.

## Self-review

- **Placeholders:** none — exact `pyproject.toml`, exact CI steps, exact version numbers (all verified live).
- **Internal consistency:** explicitly reconciles this decision with the outcome-benchmark architecture doc's opposite decision, stating why it's being reversed now rather than silently contradicting a recorded design choice.
- **Scope:** four clearly separated parts (tooling, CI, one file's rewrite, CLAUDE.md docs) — no changes to the PR template, no changes to other suites' scripts, no `uv` adoption (explicitly scoped out per the design conversation).
- **Ambiguity:** both real open risks (whether `chrschy/factory-gates`-scale Python warrants tooling at all, and `ty`'s maturity) were surfaced and explicitly resolved in conversation before this doc was written, not decided silently.
