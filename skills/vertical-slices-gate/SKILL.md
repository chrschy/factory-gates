---
name: vertical-slices-gate
description: "Use IMMEDIATELY after superpowers:writing-plans has saved an implementation plan — and BEFORE superpowers:subagent-driven-development or superpowers:executing-plans starts running tasks. Adds an explicit human sign-off on vertical-slice ordering and multi-repo/multi-service coordination — the part of Dex Horthy's Gate 4 that writing-plans' 'which execution mode?' question does not itself ask for. This is Gate 4 of the factory-gates workflow (Dex Horthy's 4-gate model)."
---

# Vertical Slices Gate (Gate 4 of 4: Product → Architecture → Program Design → **Vertical Slices**)

## Why this skill exists

`superpowers:writing-plans` already does most of Gate 4's work: it breaks work into bite-sized, independently testable tasks and asks the user to choose an execution mode before anything runs. What it does not do explicitly is ask the user to sign off on the *order* of the tasks/slices themselves, or flag multi-repo/multi-service sequencing risk before execution starts. This skill adds that one missing checkpoint — it does not replace or duplicate writing-plans' task breakdown.

**The payoff, in Horthy's words:** thirty minutes of pre-planning alignment here saves hours in review later. A good PR becomes confirmation of a prior agreement, not a discovery process.

<HARD-GATE>
Do NOT invoke superpowers:subagent-driven-development or superpowers:executing-plans until the user has explicitly confirmed the slice order below.
</HARD-GATE>

**Announce at start:** "I'm using the vertical-slices-gate skill to confirm the build order before execution starts."

## Checklist

1. **Read the saved plan** from `superpowers:writing-plans`
2. **Summarize the slice order** — list the tasks in the order they'll be built, one line each, and name what's independently testable/demoable after each one
3. **Flag coordination risk** — if this plan spans multiple repos or services (see the architecture doc's "Multi-repo / multi-service coordination" section, if one exists), call out the order dependencies explicitly: what must ship or be deployed before what
4. **Flag intermediate-test gaps** — any slice that can't be verified until a later slice lands? Surface it now, not during review
5. **Get explicit confirmation** of the order before handing off — a short "confirm this build order, or reorder?" question is enough; this is not a redesign step
6. **Next:** proceed to whichever execution mode the user already chose in `writing-plans` (`superpowers:subagent-driven-development` or `superpowers:executing-plans`)

## What belongs here vs. elsewhere

- **Here:** confirming slice order, multi-repo/service sequencing, intermediate-test gaps
- **Not here:** task-level implementation detail (already fixed in `writing-plans`), re-litigating architecture or signatures (already fixed in earlier gates — if you find yourself wanting to change those here, stop and say so explicitly rather than quietly deviating)
