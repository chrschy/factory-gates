---
name: program-design-gate
description: "Use IMMEDIATELY after architecture-gate's architecture document is approved — and BEFORE superpowers:writing-plans or any code is touched. Locks concrete types, function/method signatures, call stacks, and file/module layout as an explicit, human-approved 'interface contract' — like a C header file for the feature. This is Gate 3 of the factory-gates workflow (Dex Horthy's 4-gate model). This is the step teams skip most often, assuming a model can 'just cook' once architecture is set — skipping it is exactly why agents improvise mismatched signatures during implementation."
---

# Program Design Gate (Gate 3 of 4: Product → Architecture → **Program Design** → Vertical Slices)

## Why this skill exists

Dex Horthy calls this the most underemphasized gate: teams assume that once architecture is fixed, an agent can "just cook" the implementation. In practice this is exactly where agents improvise — inconsistent naming, signatures that drift between tasks, call stacks that only become visible once three files already disagree about them.

`superpowers:writing-plans` already has a "Type consistency" self-review check for this — but that catches drift *after* the plan is written. `program-design-gate` catches it *before* any task exists, by making the contract explicit and approved first.

Think of the output as a C header file: it declares what exists and how pieces call each other, not what's inside the function bodies.

<HARD-GATE>
Do NOT invoke superpowers:writing-plans until a program design document exists and the user has explicitly approved it.
</HARD-GATE>

**Announce at start:** "I'm using the program-design-gate skill to lock the interface contract before we write the implementation plan."

## Checklist

You MUST create a task for each of these and complete them in order:

1. **Read the approved architecture doc**
2. **For each component touched:** enumerate new/changed types, public function/method signatures (names, params, return types — no bodies), and how components call each other for the main flows (call stack / sequence)
3. **Define file/module layout** — which signatures live in which file, matching the architecture's component boundaries
4. **Present as one reviewable document**; explicitly flag anywhere the architecture doc underspecified something and you had to make a call
5. **Get explicit approval**
6. **Write the doc** — `docs/superpowers/specs/YYYY-MM-DD-<topic>-program-design.md`, commit
7. **Self-review:** does every signature referenced in one part of the doc get defined somewhere else in it? Any component from the architecture doc with no corresponding signatures here?
8. **User review gate** — ask the user to review the written doc before proceeding
9. **Next:** invoke `superpowers:writing-plans`, and explicitly tell it this document is the interface contract — task-level signatures in the plan MUST match it exactly, not drift from it.

## What belongs here vs. elsewhere

- **Here:** type definitions, function/method signatures, call stacks between components, file/module layout
- **Not here:** function bodies, test code (→ `writing-plans` / TDD), task sequencing (→ `writing-plans` / `vertical-slices-gate`), component-level boundaries (→ `architecture-gate`, already fixed)

## Document template

```markdown
# [Feature Name] — Program Design

**Architecture:** docs/superpowers/specs/<architecture-file>.md

## [Component/Module]
**File:** `path/to/file.ext`

```
[language-appropriate signature block — types, function signatures, no bodies]
```

## Call Stacks
[Main flows: which function calls which, across which components]

## Deviations from architecture
[Anything the architecture doc left open that got resolved here]
```
