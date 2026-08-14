---
name: factory-gates
description: Start a new feature using the factory-gates workflow (Product -> Architecture -> Program Design -> Vertical Slices), explicitly guaranteeing architecture-gate and program-design-gate run before writing-plans. Invoke directly via /factory-gates <feature description> when you want deterministic gate coverage regardless of brainstorming's own routing.
argument-hint: <feature description>
---

# Factory Gates — Explicit Workflow Entry Point

Use this when you want to guarantee the full factory-gates workflow (`architecture-gate`, `program-design-gate`, `vertical-slices-gate`) runs for a feature, rather than relying on `brainstorming`'s own trigger-description routing to pick it up automatically — see the repo README's "Known limitation" section for why that routing is a soft override, not a hard one.

**Announce at start:** "Using the factory-gates workflow for this feature — architecture-gate and program-design-gate will run before writing-plans, vertical-slices-gate before execution."

## Instructions

1. State explicitly, before doing anything else: this feature MUST go through `architecture-gate` (after `brainstorming`'s spec is approved, before `writing-plans`), `program-design-gate` (before `writing-plans`), and `vertical-slices-gate` (before execution). Do NOT invoke `writing-plans` directly even if `brainstorming`'s own instructions say to — that instruction predates this gate.
2. Invoke `superpowers:brainstorming` now, using `$ARGUMENTS` as the feature description. If no arguments were given, ask the user what they want to build first, then invoke `superpowers:brainstorming`.

The rest of the workflow proceeds exactly as documented in the repo README: `brainstorming` → `architecture-gate` → `program-design-gate` → `writing-plans` → `vertical-slices-gate` → execution.
