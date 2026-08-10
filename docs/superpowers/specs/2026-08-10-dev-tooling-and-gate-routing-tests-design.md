# factory-gates — Dev Tooling & Gate-Routing Tests

**Status:** approved
**Date:** 2026-08-10

This spec covers two related but independently shippable pieces of work:

1. **Gate-routing tests** — empirically test whether the one real skill-routing conflict in the 4-gate chain (Superpowers' `brainstorming` hard-instructs "invoke writing-plans, do NOT invoke any other skill", while `architecture-gate` tries to insert itself first) actually resolves the way the README claims.
2. **Repo governance & tooling** — CLAUDE.md, PR/issue templates, LICENSE, and trunk-based branch/release conventions (including applying GitHub branch protection), so the repo is set up for ongoing contribution before more skill work lands.

## 1. Gate-routing tests

### Why

Of the three gate handoffs, only one has a genuine conflict:

- `brainstorming` → `architecture-gate`: **conflict.** `brainstorming`'s SKILL.md says, twice, "The ONLY skill you invoke after brainstorming is writing-plans" / "Do NOT invoke any other skill." `architecture-gate`'s trigger description is written to out-compete that via Superpowers' own "if a skill applies, you MUST use it" routing rule (`using-superpowers`). This is a soft override — untested until now.
- `architecture-gate` → `program-design-gate`: no conflict, both sides are our own skills.
- `program-design-gate` → `writing-plans`: no conflict, our own skill hands off to `writing-plans` itself, matching what `writing-plans` expects.
- `writing-plans` → `vertical-slices-gate` → execution: no conflict. `writing-plans` presents an execution-mode question with no hard "only invoke X" instruction blocking an earlier skill from inserting itself.

So the test suite targets exactly the `brainstorming` → `architecture-gate` handoff.

### Method

Real `claude -p` sessions, both `superpowers` and `factory-gates` loaded via `--plugin-dir`, driven through an actual brainstorming conversation to the handoff decision point. This mirrors the pattern already used by Superpowers' own `tests/explicit-skill-requests/`.

- **2 scenarios × 3 trials each** (6 trials total per full run):
  - *bare* — ordinary feature request, no special phrasing
  - *explicit* — same request, prefixed with the README's documented workaround: "Use the factory-gates workflow for this."
- **Feature used for every trial:** a small, fully-specified in-memory rate limiter (single `RateLimiter` class, `check(key)` method, fixed-window, 100 req/60s, no persistence, no external deps, single file) — deliberately unambiguous so brainstorming resolves in a few turns.
- **Turn script** (fed via `--continue`, capped at 4 turns/trial):
  1. initial feature request (bare or explicit)
  2. "Yes, that approach looks good — please continue."
  3. "Approved. Please write the spec and commit it."
  4. "I've reviewed the spec, it looks good, please proceed."
- **Isolation:** each trial runs in its own fresh `/tmp` project directory (pre-seeded with `docs/superpowers/specs/` and `docs/superpowers/plans/`), so `--continue` (which resumes "most recent conversation in cwd") never crosses trials.
- **Model:** whatever `claude -p` uses by default in the running account/environment (no `--model` pin).

### Outcome classification (per trial, written as `result.json`)

- **pass** — `architecture-gate` Skill invocation appears before any `writing-plans` invocation
- **fail** — `writing-plans` invoked directly, `architecture-gate` never fired first (the exact risk the README calls out)
- **inconclusive** — neither fired within 4 turns, OR `brainstorming` itself never triggered (environment/setup issue, not a signal about factory-gates)

Skill-invocation detection: grep the `stream-json` log for `"name":"Skill"` tool_use blocks and match the skill name with/without a plugin namespace prefix (`factory-gates:architecture-gate` or bare `architecture-gate`), same approach Superpowers' own tests use.

### Layout

```
tests/gate-routing/
  README.md        — what's tested, why, how to run/read it, known limitations (probabilistic, costs tokens)
  lib/common.sh     — plugin-dir discovery (auto-finds installed superpowers version, override via
                      SUPERPOWERS_PLUGIN_DIR env var), isolated project-dir setup, Skill-detection helpers
  run-trial.sh      — <scenario: bare|explicit> <trial-dir> → drives one 4-turn conversation, writes result.json
  run-all.sh        — orchestrates the 2×3 matrix (flags: --scenario, --trials for cheap single-trial iteration),
                      aggregates all result.json files via jq into a pass/fail/inconclusive table per scenario
```

### Out of scope

- Testing the other two (non-conflicting) handoffs — not needed, there's no conflict to measure.
- CI integration — these tests cost real tokens per run and need a locally-authenticated `claude` CLI with both plugins installed; they are not suited to running automatically on every push. They're a manual/occasional diagnostic, re-run when gate-1/gate-2 wording changes.

## 2. Repo governance & tooling

### LICENSE

MIT license file at repo root. `plugin.json` already declares `"license": "MIT"` but no `LICENSE` file exists yet — add one (standard MIT text, copyright Christopher Schymura, 2026).

### CLAUDE.md

Base structure follows Superpowers' own `CLAUDE.md` (agent-contribution guardrails, PR requirements, "what we will not accept," skill-changes-require-evidence), scaled to this repo's actual size — no borrowed rejection-rate statistics or claims that aren't true for this repo. Superpowers-specific sections that don't apply are dropped:

- **Dropped entirely:** "New Harness Support" / acceptance-test section (that's about Superpowers' own multi-harness bootstrap; factory-gates depends on Superpowers already being active, it has no bootstrap of its own) and the external `evals/`-submodule eval-harness section (we have our own `tests/gate-routing/` instead).
- **Adapted:** "Is this appropriate for core?" becomes "which gate does this touch, or is this repo tooling (tests/docs/CI)?" plus an explicit reminder that changes to Superpowers' own files are always out of scope — staying non-invasive is this project's whole premise.
- **Adapted:** "Skill Changes Require Evaluation" ties directly to `tests/gate-routing/`: any change to a gate's `<HARD-GATE>` block, checklist, or trigger description must run that suite before/after and report the pass-rate delta in the PR.
- **Added from LiteLLM's CLAUDE.md** (generalized — the Python/ruff/pyright-specific rules are dropped, only the transferable agent-behavior points are kept):
  - No unnecessary comments — skill markdown prose should be self-explanatory; don't add meta-commentary about why a line exists
  - Don't assume existing skill wording is correct just because it's there — speak up about unclear or contradictory content
  - Meaningful tests: a test must fail before the fix and pass after (regression-proof), not just pad coverage
  - "Think before coding" — state assumptions, surface tradeoffs, ask rather than silently pick when multiple interpretations exist
  - "Simplicity first" — minimum content that solves the problem, no speculative flexibility
  - Public-facing writing style: no emojis, avoid AI-sounding patterns (em-dash overuse, "it's not X, it's Y", walls of bullets where prose reads better), be concrete about problem statements
- **Not adopted from LiteLLM:** "don't add Co-Authored-By: Claude attribution" — this directly conflicts with Superpowers' (and this repo's) disclosure requirement that agent-authored contributions identify their model/harness/plugins. Disclosure fits a skills-development repo better than anonymization.
- **New section — Git & Branching:** documents trunk-based development, branch naming, commit conventions, and the exact branch-protection settings applied (see below), including the explicit caveat that admin-bypass is a safety valve, not permission to skip review.

### PR template (`.github/PULL_REQUEST_TEMPLATE.md`)

Adapted from Superpowers':

- **Kept:** "Who is submitting this PR" (model/harness/plugins/human reviewer table), "What problem are you trying to solve," "What does this PR change," "What alternatives did you considered," "Existing PRs" duplicate-check, a "Rigor" section (adapted to reference `tests/gate-routing/` instead of Superpowers' external eval methodology), "Human review" checkbox.
- **Adapted:** target-branch banner changed from "must target `dev`" to "must target `main`" (trunk-based — no `dev` branch here), "Is this appropriate for core" reframed as "which gate does this touch."
- **Dropped:** "New harness support" section entirely (not applicable — see CLAUDE.md rationale above).

### Issue templates (`.github/ISSUE_TEMPLATE/`)

- **Kept, adapted:** `bug_report.md`, `feature_request.md` — swap "Superpowers version" for "factory-gates version," add a "Which gate(s) are involved?" field (architecture-gate / program-design-gate / vertical-slices-gate / repo tooling).
- **Dropped:** `platform_support.md` — that's about requesting support for new IDEs/harnesses for Superpowers itself; factory-gates is a single-harness (Claude Code) plugin with no multi-harness ambition at this stage.
- **Kept, adapted:** `config.yml` — `blank_issues_enabled: false`; drop the Discord `contact_links` entry (no such community channel exists for this repo).

### Git & release conventions (trunk-based)

- `main` is the only long-lived branch. Releases are git tags `vX.Y.Z` on `main` — no release branches.
- All changes land via PR from a feature branch; no direct pushes to `main`.
- **Branch naming:** `<type>/<slug>`, type ∈ `{feature, fix, docs, test, chore}`; slug includes the gate name when the change is scoped to one gate, e.g. `feature/architecture-gate-clarify-checklist`.
- **Commits:** Conventional Commits — `<type>(<scope>): <subject>`, type ∈ `{feat, fix, docs, test, chore, refactor, ci, revert}`, scope ∈ `{architecture-gate, program-design-gate, vertical-slices-gate, tests, docs, ci, meta}`.
- PR titles should also be Conventional-Commit-formatted, since squash merge will use the PR title as the merge commit message.
- One problem per PR.

### GitHub branch protection on `main` (applied via `gh api`, not just documented)

Given this is currently a solo-maintained repo, and GitHub never counts a PR author's own approval toward "required reviews" (even for the repo owner) — enforcing a literal second-approver requirement would make the owner's own PRs permanently unmergeable. Settings applied:

| Setting | Value |
|---|---|
| Require pull request before merging | on |
| Required approving reviews | 1 |
| `enforce_admins` | **off** — repo admins (the owner) can bypass; this is a documented safety valve, not permission. CLAUDE.md/CONTRIBUTING.md state plainly: don't push directly to `main`, always go through a PR and read the full diff before merging your own PR |
| Required status checks | none (no CI workflow exists yet) |
| Required linear history | on |

Repo-level merge settings: squash-merge only (disable merge-commit and rebase-merge), delete branch on merge.

### CONTRIBUTING.md — follow-up, not in this pass

Once the above lands, write a dedicated `CONTRIBUTING.md` mirroring the same conventions (branching, commits, PR process, review expectations) in a form aimed at a human contributor reading it standalone, rather than CLAUDE.md's agent-guardrail framing. Explicitly deferred to a later task per your instruction ("later on when everything is set up").

## Self-review

- **Placeholders:** none left — every section above has concrete values (exact settings, exact file lists, exact turn scripts).
- **Internal consistency:** trunk-based `main`-only model is reflected consistently across CLAUDE.md, PR template, and the branch-protection settings (no leftover `dev`-branch references from the Superpowers source material).
- **Scope:** two sub-projects bundled in one spec because both are foundational "get the repo dev-ready" work requested together; they're independent enough that `writing-plans` may reasonably sequence them as two separate plans/PRs rather than one.
- **Ambiguity:** the admin-bypass caveat on branch protection is called out explicitly rather than left implicit, since it's the one place where the documented rule and the technical enforcement diverge.
