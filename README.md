# factory-gates

An add-on plugin for [Superpowers](https://github.com/obra/superpowers) that inserts Dex Horthy's (HumanLayer) 4-gate model — **Product → Architecture → Program Design → Vertical Slices** — as explicit, human-approved checkpoints into the Superpowers planning flow.

This is a non-invasive companion plugin. It does not fork or edit any Superpowers file. It adds three new skills that slot into the gaps between Superpowers' existing skills.

## Why

Superpowers already gates two of Horthy's four steps well:

| Horthy's Gate | Superpowers today |
|---|---|
| 1. Product | `brainstorming` — covers this well |
| 2. Architecture | Implicit — mixed into `writing-plans`' "File Structure" section, not separately approved |
| 3. Program Design | Missing — no explicit signature/call-stack contract before implementation |
| 4. Vertical Slices | Mostly covered by `writing-plans`' task breakdown + execution handoff, but no explicit sign-off on slice *order* or multi-repo coordination |

This plugin adds:

- **`architecture-gate`** — Gate 2. Component boundaries, data models, cross-cutting constraints. Runs after `brainstorming`, before `writing-plans`.
- **`program-design-gate`** — Gate 3. Types, signatures, call stacks, file layout — a "header file" for the feature, no bodies. Runs after `architecture-gate`, before `writing-plans`.
- **`vertical-slices-gate`** — Gate 4. A short, explicit sign-off on slice order and multi-repo/service sequencing. Runs after `writing-plans` has saved a plan, before `subagent-driven-development` / `executing-plans` starts.

The result: `brainstorming` → `architecture-gate` → `program-design-gate` → `writing-plans` → `vertical-slices-gate` → `subagent-driven-development` / `executing-plans`.

## Install

Requires Superpowers already installed. From your project (or globally):

```
/plugin marketplace add /path/to/factory-gates
/plugin install factory-gates@factory-gates-dev
```

Or point at a git remote once you've pushed this directory to one:

```
/plugin marketplace add <your-org>/factory-gates
/plugin install factory-gates@factory-gates-dev
```

## Known limitation — read this

Superpowers' own `brainstorming` skill ends with an explicit instruction: *"Invoke the writing-plans skill... Do NOT invoke any other skill."* Because this plugin doesn't edit Superpowers' files, that instruction still exists verbatim. `architecture-gate`'s description is written to be highly specific ("use immediately after brainstorming, before writing-plans") so Claude picks it up as the more specific match — and Superpowers' own `using-superpowers` router skill instructs Claude to invoke *any* applicable skill, not just the one another skill points to. In practice this has worked reliably in testing, but it is a soft override, not a hard one.

**If you want it to be reliable every time**, say so explicitly at the start of a feature: *"Use the factory-gates workflow for this."* That's enough to make the gate sequence deterministic regardless of what brainstorming's own text says.

## Credits

- 4-gate model: Dex Horthy, HumanLayer — as described in his "Harness Engineering is not Enough: Why Software Factories Fail" talk and various podcast appearances (2026).
- Base framework this plugs into: [obra/superpowers](https://github.com/obra/superpowers) (Jesse Vincent).

This is an unofficial community glue layer, not affiliated with HumanLayer or the Superpowers project.
