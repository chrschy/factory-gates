# factory-gates — Architecture Gate Quality Tests

**Status:** approved
**Date:** 2026-08-11

## Why

`tests/gate-routing/` answers "does `architecture-gate` get invoked at all" — a binary routing question. It says nothing about whether the document `architecture-gate` produces is actually *good*: whether component boundaries are real, whether data models are specified at the right level, whether it stays in its lane. Of the three gate skills in this plugin, none has been touched, exercised, or judged since the original scaffold. This spec adds a test suite that drives `architecture-gate` through a toy feature end-to-end and scores the resulting architecture document against a rubric derived from the skill's own checklist and template.

Scope is deliberately narrow: `architecture-gate` only (the most novel of the three gates), document quality only (not process/routing — already covered by `tests/gate-routing/`), one toy feature. This is a first cut, not the full 4-gate pipeline.

## Toy feature

A URL shortener: a public redirect endpoint and an admin API for creating short links, sharing a data store. Specified fully in the initial prompt (not left for `brainstorming` to draw out via clarifying questions) — same trick `tests/gate-routing/` uses to keep conversations short and cheap. Deliberately richer than gate-routing's single-file rate limiter: two components, data crossing a boundary, at least one real cross-cutting constraint (e.g. redirect latency) — enough for `architecture-gate`'s checklist to have real decisions to make, not a token boundary case.

## Conversation script

Longer than `tests/gate-routing/`'s 4 turns, since this has to walk through both `brainstorming` and the entirety of `architecture-gate`'s 8-step checklist, not just trigger the handoff:

1. Feature request (full spec upfront, as above)
2. "That approach looks good — please continue." (`brainstorming`'s proposed approaches)
3. "Approved. Please write the spec and commit it." (`brainstorming`'s spec write)
4. "I've reviewed the spec, it looks good, please proceed." (handoff into `architecture-gate`)
5. "That architecture approach looks good — please continue." (`architecture-gate`'s proposed approaches)
6. "Approved. Please write the architecture doc." (section presentation + doc write)
7. "I've reviewed the architecture doc, it looks good." (final user-review-gate approval)

Capped at 8 turns (one spare beyond the 7 scripted above, in case a section needs an extra round). Each trial costs meaningfully more than a gate-routing trial (a longer conversation, more tool calls) — budget accordingly.

## Judging mechanism

Once the trial's conversation completes, locate the produced `docs/superpowers/specs/*-architecture.md` file in the trial's isolated project directory (glob match — filename includes a date and topic slug the harness doesn't control). Score it with a **separate, headless `claude -p` call** — no plugins loaded, just the document content and the rubric below as the prompt. Not the interactive Agent tool: the whole harness has to remain a standalone bash script runnable outside a live Claude Code session, matching `tests/gate-routing/`'s existing convention.

Output format mirrors Superpowers' own `spec-document-reviewer-prompt.md` pattern exactly (a rubric table, then a categorical verdict) rather than inventing a new convention:

### Rubric

| Category | What to look for |
|---|---|
| Template compliance | Required sections present: Components, Data Models, Constraints, Multi-repo/multi-service (if relevant), Open questions |
| Component boundaries | Each component has a stated responsibility, owned data, and which other components it talks to — no vague/undefined boundaries |
| Data models | Specified at "shape crossing a component boundary" only — not missing, not over-specified as a full DB schema |
| Constraints | Relevant cross-cutting constraints (auth, versioning, latency, backwards-compat, external deps) stated with a reason each, where applicable to this toy feature |
| Traceability | References the approved spec file by path; "Open questions" section (if used) reflects real ambiguity the spec left open, not fabricated content |
| Scope discipline | Stays out of `program-design-gate`'s territory (no function/method signatures, no call stacks) and `writing-plans`' territory (no file-by-file task breakdown) |

### Calibration

Only flag issues that would cause a real problem for `program-design-gate` (the next gate in the chain) to build on this document: an undefined component boundary, a data model that's clearly needed but missing, real scope creep into the next gate's territory. Wording preferences, section ordering, and stylistic choices are not issues.

### Output format

```
## Architecture Doc Review

**Status:** Approved | Issues Found

**Issues (if any):**
- [Category]: [specific issue] — [why it would block program-design-gate]

**Recommendations (advisory, do not block approval):**
- [suggestions]
```

## Outcome classification (per trial)

- **pass** — judge returns `Approved`
- **fail** — judge returns `Issues Found`
- **inconclusive** — the conversation never produced an architecture doc within the turn cap (e.g. `brainstorming` or `architecture-gate` never triggered, or the doc file was never written) — an environment/harness signal, not a quality signal, same distinction `tests/gate-routing/` already makes

## File layout

```
tests/gate-quality/
  architecture-gate/
    run-trial.sh     — drives one trial's conversation, locates the doc, invokes the judge, writes result.json
    run-all.sh        — orchestrates N trials, aggregates via jq (mirrors tests/gate-routing/run-all.sh)
    lib/
      judge.sh          — run_judge(doc_path) -> writes judge verdict to a file; the one new piece of logic this suite adds
    README.md            — what's tested, why, how to run/read it, cost/limitations
```

Nested under `tests/gate-quality/` (not flat like `tests/gate-routing/`) so `program-design-gate`/`vertical-slices-gate` quality suites can be added later as siblings (`tests/gate-quality/program-design-gate/`, etc.) without restructuring. `run-trial.sh` and `run-all.sh` **source `tests/gate-routing/lib/common.sh`** for the already-reviewed, already-bug-fixed shared plumbing (`resolve_superpowers_dir`, `resolve_factory_gates_dir`, `setup_trial_dir`, `run_turn`, `skill_invoked_in`) rather than duplicating it — consistent with CLAUDE.md's "DRY without premature abstraction."

## Trial count

3 trials (not 3×2 scenarios like gate-routing — there's no "explicit workaround" scenario to compare here, this suite isn't testing routing). Default, overridable via a `--trials N` flag on `run-all.sh`, matching gate-routing's existing convention.

## Out of scope

- Process/routing behavior (already covered by `tests/gate-routing/`).
- `program-design-gate` and `vertical-slices-gate` quality (future, separate suites under the same `tests/gate-quality/` parent once this one proves the pattern).
- The full 4-gate pipeline end-to-end.
- CI integration (same reasoning as `tests/gate-routing/`: real tokens, real time, not suited to a required check on every push).

## Self-review

- **Placeholders:** none — rubric, turn script, and output format are all concrete.
- **Internal consistency:** outcome classification (pass/fail/inconclusive) mirrors `tests/gate-routing/`'s three-way split for consistency, adapted from "which skill fired" to "what the judge returned."
- **Scope:** deliberately narrower than "test the whole pipeline" per the brainstorming discussion — one gate, one toy feature, document quality only. Extending to the other two gates is explicitly deferred, not silently assumed.
- **Ambiguity:** the judge's calibration guidance is copied near-verbatim from Superpowers' own established pattern rather than invented fresh, so its bar for "real issue" vs. "nitpick" has precedent to lean on.
