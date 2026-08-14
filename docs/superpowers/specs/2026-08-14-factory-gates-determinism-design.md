# factory-gates — Strengthening Routing Determinism

**Status:** approved
**Date:** 2026-08-14

## Why

The one real soft-override risk in this plugin — `architecture-gate` competing against `brainstorming`'s hard "invoke writing-plans only" instruction — has one documented mitigation so far: typing "Use the factory-gates workflow for this" at the start of a feature. That requires the user to remember it every single time. Two more mechanisms exist that could make this closer to "set once, works automatically": a user-invoked `/factory-gates` slash command, and a standing project `CLAUDE.md` instruction (Superpowers' own `using-superpowers` skill documents that user instructions in `CLAUDE.md`/`AGENTS.md`/etc. take precedence over skill instructions — a claim this project has never actually tested empirically, only taken on faith).

Neither mechanism is deterministic *by construction* — both still end with `brainstorming`'s hard instruction sitting in context, and both work by adding an earlier, stronger, explicit statement that should bias the outcome, the same mechanism as the already-tested "explicit phrase" scenario. Both are measured here, not assumed.

This also updates the README's "Known limitation" section, which is out of date on two counts: it still says "three new skills" (about to become four), and it predates every empirical measurement this project now has (`tests/gate-routing/`, `tests/gate-quality/`).

## Part A — `/factory-gates` slash command

New skill, `skills/factory-gates/SKILL.md`, user-invoked only (not auto-triggered by description matching — Claude Code plugins support this via the same `skills/<name>/SKILL.md` layout, confirmed against the official example plugin's `commands/`-format-superseding convention).

```yaml
---
name: factory-gates
description: Start a new feature using the factory-gates workflow (Product -> Architecture -> Program Design -> Vertical Slices), explicitly guaranteeing architecture-gate and program-design-gate run before writing-plans. Invoke directly via /factory-gates <feature description> when you want deterministic gate coverage regardless of brainstorming's own routing.
argument-hint: <feature description>
---
```

Body: announces the workflow, explicitly states `architecture-gate`/`program-design-gate` must run before `writing-plans` "even if brainstorming's own instructions say otherwise," then invokes `superpowers:brainstorming` with `$ARGUMENTS` as the feature context (asking the user what they want to build if no arguments were given).

## Part B — `CLAUDE.md` project instruction

Documented in the README as a one-time, per-project setup step:

```markdown
## Software Factory Workflow
For any new feature or creative work, use the factory-gates workflow — architecture-gate and program-design-gate run before writing-plans, vertical-slices-gate runs before execution. Do not skip these gates even if a skill's own instructions say to invoke writing-plans directly.
```

The last sentence directly names and counters the specific conflict (`brainstorming`'s "do NOT invoke any other skill" line) rather than a vague "use factory-gates" — matching Superpowers' own documented precedence: *"User instructions (CLAUDE.md, AGENTS.md, GEMINI.md, etc, direct requests) take precedence over skills."*

## Part C — Empirical verification via `tests/gate-routing/`

Two new scenarios added to the existing suite, alongside `bare`/`explicit`:

- **`claude-md`**: writes the Part B snippet to the trial's isolated project directory as `CLAUDE.md` before turn 1 (Claude Code auto-discovers `CLAUDE.md` in its working directory — `run_turn` already `cd`s there, so no new plumbing beyond writing the file), then sends the *bare*, unprefixed feature request as turn 1.
- **`slash-command`**: turn 1's prompt is literally `/factory-gates <feature request>` instead of a bare or prefixed message. Requires confirming during implementation that `claude -p "/factory-gates ..."` invokes a plugin-provided user-command in headless mode the same as it would interactively — not assumed, verified as part of building this.

Both reuse the exact same downstream detection logic (`skill_invoked_in` for `brainstorming`/`architecture-gate`/`writing-plans`) unchanged — only turn 1's prompt construction (and, for `claude-md`, a file write before it) differs per scenario. Same three-way outcome classification (pass/fail/inconclusive) as the existing scenarios.

**Cost-conscious default:** `run-all.sh`'s default scenario set stays `bare`+`explicit` (6 trials) — the two new scenarios are exploratory until this plan's own verification run establishes whether they're worth recommending. They're run explicitly (`--scenario claude-md --trials 3`, `--scenario slash-command --trials 3`) as part of this plan's own rollout, not folded into the default.

## Part D — README update

- "It adds three new skills" → four (`architecture-gate`, `program-design-gate`, `vertical-slices-gate`, `factory-gates`).
- "Known limitation" section rewritten: keep the explicit-phrase mechanism (already measured: `tests/gate-routing/`'s two formal runs show 0 fails across 16 trials, explicit phrasing correlating with fewer non-completions), add the `/factory-gates` command and `CLAUDE.md` snippet as additional/complementary mechanisms, with their own measured results from Part C's verification run once it's run.
- Add an `## Install` mention of the `/factory-gates` command as the recommended way to start a feature when determinism matters.

## Self-review

- **Placeholders:** none — the skill frontmatter/body, the `CLAUDE.md` snippet, and the test scenario mechanics are all concrete. The README's exact final wording for the measured `claude-md`/`slash-command` results is necessarily written after Part C's verification run produces real numbers, same pattern as every prior plan in this repo.
- **Internal consistency:** the `CLAUDE.md` snippet text is defined once here and must appear identically in both the README (Part D) and the test harness (Part C) — call this out explicitly in the plan so they don't drift.
- **Scope:** four parts, each independently justified; no changes to the three existing gate skills' own content.
- **Ambiguity:** the "not deterministic by construction" correction is stated explicitly up front so neither mechanism gets oversold in the README beyond what Part C actually measures.
