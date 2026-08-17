# factory-gates — CONTRIBUTING.md

**Status:** approved
**Date:** 2026-08-17

## Why

`CLAUDE.md` and the README both reference `CONTRIBUTING.md` ("process-level detail for opening issues/PRs (once written)") but it doesn't exist yet — a real gap for a repo now shipping real releases (v0.3.0) and claiming to be usable by outside contributors. GitHub also surfaces `CONTRIBUTING.md` specially (linked from the "New issue"/"New PR" UI), so its absence is a visible gap, not just a missing file.

## Content

`CONTRIBUTING.md` at repo root. Deliberately short — it's an entry point, not a duplicate of `CLAUDE.md`'s already-thorough process documentation. Every section that has a fuller, already-written home in `CLAUDE.md` links there instead of restating it.

Sections:
1. **Before you start** — read `CLAUDE.md` fully (both human and agent contributors), scope reminder (this repo is deliberately narrow — three gate skills, their tests, the tooling around them; changes to Superpowers itself belong upstream).
2. **Reporting issues** — use the issue templates (`.github/ISSUE_TEMPLATE/`), search existing issues/PRs first.
3. **Development setup** — clone, install Superpowers, install factory-gates locally (`/plugin marketplace add .` + `/plugin install factory-gates@factory-gates`, matching the real install instructions already in the README).
4. **Running tests** — the fast suite (`ruff check .`, `ruff format --check .`, `ty check`, plus the four `test-*.sh` unit-test scripts CI runs) vs. the live-LLM suites (`tests/gate-routing/`, `tests/gate-quality/*/`, `tests/outcome-benchmark/` — real token cost, not run in CI, link to each suite's own README).
5. **Making changes** — link to `CLAUDE.md`'s "Git & Branching" section for branch naming/commit format/one-problem-per-PR; link to the PR template; note CI must pass (`fast-tests`, `secrets-scan`) and human review is required before merge.
6. **Changing a gate skill** — link to `CLAUDE.md`'s "Skill Changes Require Evidence" section, since this is the one place a casual contributor could cause real, hard-to-notice damage (routing regressions) without realizing it.
7. **Cutting a release** — link to `CLAUDE.md`'s "Cutting a release" section, noted as maintainer-only.

## Verification

`grep` checks confirming every cross-reference target actually exists (`CLAUDE.md`'s named sections, `.github/ISSUE_TEMPLATE/`, `.github/PULL_REQUEST_TEMPLATE.md`, each test suite's README) — a broken link in a contributor-facing doc is worse than no doc.

## Self-review

- **Placeholders:** none — every section states real, current process, not a TBD.
- **Internal consistency:** deliberately non-duplicative of `CLAUDE.md` — cross-references instead of restating, so the two docs can't silently drift apart on the same topic.
- **Scope:** one new file, no changes to `CLAUDE.md` itself (its own "See Also" entry for `CONTRIBUTING.md` already exists and stays accurate once this lands).
- **Ambiguity:** none — content is synthesis of already-decided, already-documented conventions, not new policy.
