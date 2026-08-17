# Contributing to factory-gates

## Before you start

Read `CLAUDE.md` fully — it's the authoritative process document for this
repo, for human and AI-agent contributors alike. This file is a short
entry point, not a substitute for it.

This repo is deliberately narrow in scope: three gate skills
(`architecture-gate`, `program-design-gate`, `vertical-slices-gate`),
their tests, and the tooling around them. Changes to Superpowers' own
files never belong here (see README "Why") — factory-gates stays
non-invasive by design. If your change is about Superpowers itself, it
belongs upstream.

## Reporting issues

Search existing issues and PRs, open and closed, before filing a new
one. Use the issue templates under `.github/ISSUE_TEMPLATE/` (bug report
or feature request).

## Development setup

```bash
git clone https://github.com/chrschy/factory-gates.git
cd factory-gates
```

Requires [Superpowers](https://github.com/obra/superpowers) already
installed. Install factory-gates itself from your local checkout so you
test your actual changes, not the last published release:

```
/plugin marketplace add .
/plugin install factory-gates@factory-gates
```

## Running tests

**Fast suite** (seconds, no network, run before every PR):

```bash
ruff check .
ruff format --check .
ty check
tests/release/test-version-calc.sh
tests/gate-routing/test-common.sh
tests/gate-quality/architecture-gate/test-judge.sh
tests/gate-quality/program-design-gate/test-judge.sh
tests/gate-quality/vertical-slices-gate/test-judge.sh
tests/outcome-benchmark/test-scoring.sh
tests/outcome-benchmark/test-execute.sh
```

These are exactly what `.github/workflows/ci.yml`'s `fast-tests` job
runs — same commands, same order.

**Live-LLM suites** (real tokens, real time, not run in CI): see each
suite's own README before running —
[`tests/gate-routing/`](tests/gate-routing/README.md),
[`tests/gate-quality/architecture-gate/`](tests/gate-quality/architecture-gate/README.md),
[`tests/gate-quality/program-design-gate/`](tests/gate-quality/program-design-gate/README.md),
[`tests/gate-quality/vertical-slices-gate/`](tests/gate-quality/vertical-slices-gate/README.md),
[`tests/outcome-benchmark/`](tests/outcome-benchmark/README.md).

## Making changes

See `CLAUDE.md`'s "Git & Branching" section for branch naming, commit
format, and the one-problem-per-PR rule. Fill out
`.github/PULL_REQUEST_TEMPLATE.md` completely when opening a PR —
real, specific answers, not placeholders.

Both CI checks (`fast-tests`, `secrets-scan`) must pass, and a human
maintainer must review the complete diff before merge.

## Changing a gate skill

`architecture-gate`, `program-design-gate`, and `vertical-slices-gate`
are behavior-shaping content, not documentation. See `CLAUDE.md`'s
"Skill Changes Require Evidence" section before touching any of their
`<HARD-GATE>` blocks, checklists, or trigger descriptions — this is the
one place a casual wording change can silently break routing.

## Cutting a release

Maintainer-only. See `CLAUDE.md`'s "Cutting a release" section.
