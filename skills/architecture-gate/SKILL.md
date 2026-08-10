---
name: architecture-gate
description: "Use IMMEDIATELY after superpowers:brainstorming's spec is written and approved — and BEFORE superpowers:writing-plans or any code is touched. Locks component boundaries, data models, and cross-cutting constraints as an explicit, human-approved architecture document. This is Gate 2 of the factory-gates workflow (Dex Horthy's 4-gate model: Product → Architecture → Program Design → Vertical Slices). If a brainstorming spec was just approved and no architecture doc exists yet for this feature, you MUST use this skill before writing-plans — even though brainstorming's own 'Implementation' section points straight at writing-plans, that instruction predates this gate."
---

# Architecture Gate (Gate 2 of 4: Product → **Architecture** → Program Design → Vertical Slices)

## Why this skill exists

`superpowers:brainstorming` produces a *product* spec — what problem, for whom, what success looks like. It does not lock structural decisions: which components exist, where the boundaries sit, how data flows between them, what constraints apply system-wide. Those decisions currently get made implicitly, inside `superpowers:writing-plans`' "File Structure" section, mixed together with file-level task planning.

Dex Horthy's software-factory framework treats this as its own gate on purpose: architecture is the point where a wrong assumption is cheapest to fix. Once code exists, undoing an architectural choice costs a rewrite. Undoing it here costs a sentence.

**This skill runs between `superpowers:brainstorming` and `superpowers:writing-plans`.**

<HARD-GATE>
Do NOT invoke superpowers:writing-plans, and do NOT write or scaffold any code, until an architecture document exists for this feature and the user has explicitly approved it.
</HARD-GATE>

**Announce at start:** "I'm using the architecture-gate skill to lock down the system architecture before we plan implementation."

## Checklist

You MUST create a task for each of these and complete them in order:

1. **Read the approved spec** — `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
2. **Identify scope** — which components/services/modules this feature touches or introduces
3. **Propose 2-3 architectural approaches** with tradeoffs (same pattern as brainstorming's product approaches) — e.g. where the boundary sits, sync vs. async, which system owns which data, monolith vs. new service
4. **Present the architecture** in sections: component responsibilities, data models (shape, not full schema — only what crosses a component boundary), cross-cutting constraints (auth, versioning, latency budgets, backwards compatibility, external dependencies), and multi-repo/multi-service coordination if relevant. Get approval section by section for complex features.
5. **Write the doc** — `docs/superpowers/specs/YYYY-MM-DD-<topic>-architecture.md`, commit
6. **Self-review:** any component with an undefined boundary? Any data model referenced but not specified? Any constraint implied by the product spec but missing here?
7. **User review gate** — ask the user to review the written doc before proceeding
8. **Next:** invoke `program-design-gate`. Do NOT invoke `writing-plans` directly — `program-design-gate` is Gate 3 and comes first.

## What belongs here vs. elsewhere

- **Here:** component boundaries, data models (shape, not full schema), what talks to what, cross-cutting constraints, multi-repo/multi-service coordination
- **Not here:** function/method signatures and call stacks (→ `program-design-gate`), file-by-file task breakdown (→ `writing-plans`)

## Document template

```markdown
# [Feature Name] — Architecture

**Spec:** docs/superpowers/specs/<spec-file>.md

## Components
- **[Component]** — responsibility, owns which data, talks to which other components

## Data Models
[Shape of data crossing component boundaries — not a full DB schema]

## Constraints
- [Constraint] — why it applies

## Multi-repo / multi-service coordination
[Only if relevant — which repos/services are touched, in what order they must ship]

## Open questions the product spec left open
[Anything brainstorming's spec left ambiguous that architecture forced a decision on]
```
