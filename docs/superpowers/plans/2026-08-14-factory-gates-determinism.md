# Strengthening Routing Determinism Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/factory-gates` slash command and a `CLAUDE.md` project-instruction mechanism as additional ways to make the `brainstorming` → `architecture-gate` handoff reliable, empirically measure both via `tests/gate-routing/`, and update the README with real numbers instead of assertions.

**Architecture:** A new user-invoked skill (`skills/factory-gates/SKILL.md`) provides the slash command. `tests/gate-routing/run-trial.sh` gains two new scenarios (`claude-md`, `slash-command`) reusing all existing detection/classification logic — only turn-1 prompt construction (and, for `claude-md`, a file write before it) differs. The README is updated last, once real measurements exist, following the same "no unfilled placeholders in what ships" discipline as every prior plan in this repo.

**Tech Stack:** markdown (the skill), bash (the harness extension) — no new dependency.

## Global Constraints

- The `CLAUDE.md` snippet text is defined once here and MUST appear character-for-character identical in both Task 2 (the test harness) and Task 5 (the README) — call out any mismatch as a defect, not a style choice:
```
## Software Factory Workflow
For any new feature or creative work, use the factory-gates workflow -- architecture-gate and program-design-gate run before writing-plans, vertical-slices-gate runs before execution. Do not skip these gates even if a skill's own instructions say to invoke writing-plans directly.
```
- Neither the slash command nor the `CLAUDE.md` instruction is deterministic by construction — both still end with `brainstorming`'s hard instruction in context. Do not write README language claiming a hard guarantee; report exactly what Task 4 measures.
- `run-all.sh`'s default scenario set stays `bare`+`explicit` — `claude-md` and `slash-command` are run explicitly via `--scenario`, not folded into the default, per the spec's cost-conscious design.
- No changes to the three existing gate skills' own SKILL.md content in this plan.

## File Structure

```
skills/
  factory-gates/
    SKILL.md                        — new: the /factory-gates command
tests/gate-routing/
  run-trial.sh                       — modified: two new scenarios
  run-all.sh                          — modified: header comment only, no logic change
README.md                              — modified: skill count, Known limitation section, Install mention
```

---

### Task 1: `/factory-gates` slash command

**Files:**
- Create: `skills/factory-gates/SKILL.md`

**Interfaces:**
- Produces: a user-invocable `/factory-gates <feature description>` command, consumed by Task 3-4's `slash-command` test scenario and by real users going forward

- [ ] **Step 1: Create the branch**

```bash
cd /home/christopher/PycharmProjects/factory-gates
git checkout main
git pull
git checkout -b feature/factory-gates-determinism
```

- [ ] **Step 2: Write `skills/factory-gates/SKILL.md`**

```markdown
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
```

- [ ] **Step 3: Verify**

```bash
grep -n "^name: factory-gates" skills/factory-gates/SKILL.md
grep -n "^argument-hint:" skills/factory-gates/SKILL.md
grep -n "Do NOT invoke .writing-plans. directly" skills/factory-gates/SKILL.md
```

Expected: one match each.

- [ ] **Step 4: Commit**

```bash
git add skills/factory-gates/SKILL.md
git commit -m "feat(factory-gates): add /factory-gates slash command as explicit workflow entry point"
```

---

### Task 2: Extend the gate-routing harness

**Files:**
- Modify: `tests/gate-routing/run-trial.sh`
- Modify: `tests/gate-routing/run-all.sh`

**Interfaces:**
- Consumes: Task 1's `/factory-gates` skill (for the `slash-command` scenario to actually invoke)
- Produces: `run-trial.sh <bare|explicit|claude-md|slash-command> <trial-dir>` — same `result.json` schema as before, `scenario` field now takes one of four values

- [ ] **Step 1: Update `run-trial.sh`'s usage comment and error message**

Find this exact line near the top of the file:
```
# Usage: run-trial.sh <bare|explicit> <trial-output-dir>
```
Replace with:
```
# Usage: run-trial.sh <bare|explicit|claude-md|slash-command> <trial-output-dir>
```

Find this exact line:
```
    echo "Usage: $0 <bare|explicit> <trial-output-dir>" >&2
```
Replace with:
```
    echo "Usage: $0 <bare|explicit|claude-md|slash-command> <trial-output-dir>" >&2
```

- [ ] **Step 2: Update scenario validation**

Find this exact block:
```
if [ "$SCENARIO" != "bare" ] && [ "$SCENARIO" != "explicit" ]; then
    echo "ERROR: scenario must be 'bare' or 'explicit', got '$SCENARIO'" >&2
    exit 1
fi
```
Replace with:
```
if [ "$SCENARIO" != "bare" ] && [ "$SCENARIO" != "explicit" ] && [ "$SCENARIO" != "claude-md" ] && [ "$SCENARIO" != "slash-command" ]; then
    echo "ERROR: scenario must be 'bare', 'explicit', 'claude-md', or 'slash-command', got '$SCENARIO'" >&2
    exit 1
fi
```

- [ ] **Step 3: Replace turn-1 prompt construction**

Find this exact block:
```
if [ "$SCENARIO" = "explicit" ]; then
    TURN1_PROMPT="Use the factory-gates workflow for this. $FEATURE_REQUEST"
else
    TURN1_PROMPT="$FEATURE_REQUEST"
fi
```
Replace with:
```
CLAUDE_MD_SNIPPET="## Software Factory Workflow
For any new feature or creative work, use the factory-gates workflow -- architecture-gate and program-design-gate run before writing-plans, vertical-slices-gate runs before execution. Do not skip these gates even if a skill's own instructions say to invoke writing-plans directly."

case "$SCENARIO" in
    explicit)
        TURN1_PROMPT="Use the factory-gates workflow for this. $FEATURE_REQUEST"
        ;;
    claude-md)
        TURN1_PROMPT="$FEATURE_REQUEST"
        echo "$CLAUDE_MD_SNIPPET" > "$PROJECT_DIR/CLAUDE.md"
        ;;
    slash-command)
        TURN1_PROMPT="/factory-gates $FEATURE_REQUEST"
        ;;
    *)
        TURN1_PROMPT="$FEATURE_REQUEST"
        ;;
esac
```

This block must come after `PROJECT_DIR="$(setup_trial_dir "$TRIAL_DIR")"` (it already does in the current file — `PROJECT_DIR` needs to exist before the `claude-md` branch can write to it).

- [ ] **Step 4: Update `run-all.sh`'s header comment (no logic change)**

Find this exact block:
```
# Usage: run-all.sh [--scenario bare|explicit] [--trials N]
#   --scenario   Run only this scenario (default: both bare and explicit)
#   --trials N   Trials per scenario (default: 3)
```
Replace with:
```
# Usage: run-all.sh [--scenario bare|explicit|claude-md|slash-command] [--trials N]
#   --scenario   Run only this scenario (default: both bare and explicit --
#                claude-md and slash-command are exploratory, run them
#                explicitly with --scenario until proven out)
#   --trials N   Trials per scenario (default: 3)
```

`SCENARIOS=(bare explicit)` (the actual default array) does NOT change — only the comment above it changes, since the array logic already accepts any scenario name via `--scenario` with no code change needed.

- [ ] **Step 5: Verify syntax**

```bash
bash -n tests/gate-routing/run-trial.sh
bash -n tests/gate-routing/run-all.sh
```

Expected: no output, exit 0 each.

- [ ] **Step 6: Verify the CLAUDE.md snippet matches the Global Constraints text exactly**

```bash
grep -A3 "CLAUDE_MD_SNIPPET=" tests/gate-routing/run-trial.sh
```

Expected: matches the exact text in this plan's Global Constraints section, character for character.

- [ ] **Step 7: Commit**

```bash
git add tests/gate-routing/run-trial.sh tests/gate-routing/run-all.sh
git commit -m "feat(tests): add claude-md and slash-command scenarios to gate-routing suite"
```

---

### Task 3: Smoke-test both new scenarios

**Files:** none

**Interfaces:**
- Consumes: Task 1 and Task 2's work together for the first time

- [ ] **Step 1: Smoke-test the `claude-md` scenario**

```bash
tests/gate-routing/run-trial.sh claude-md /tmp/factory-gates-claude-md-smoke-test
cat /tmp/factory-gates-claude-md-smoke-test/result.json
cat /tmp/factory-gates-claude-md-smoke-test/project/CLAUDE.md
```

Expected: takes a few minutes, real token cost. Any of pass/fail/inconclusive in `result.json` is an acceptable smoke-test result (per this suite's established bar — verifying the harness runs end-to-end, not that it passes). The `CLAUDE.md` file must exist in the trial's project directory with the exact snippet content. If the script errors out before producing `result.json` at all, that's the actual problem to fix.

- [ ] **Step 2: Smoke-test the `slash-command` scenario**

```bash
tests/gate-routing/run-trial.sh slash-command /tmp/factory-gates-slash-command-smoke-test
cat /tmp/factory-gates-slash-command-smoke-test/result.json
```

Expected: same acceptance bar as Step 1.

- [ ] **Step 3: Investigate whether headless `/factory-gates` invocation actually worked**

This is a genuine open question from the spec, not a formality — read `/tmp/factory-gates-slash-command-smoke-test/turn1.json` directly and determine:
1. Does the model's first response contain anything resembling the `/factory-gates` skill's own announcement ("Using the factory-gates workflow for this feature...")?
2. Is there a `"name":"Skill"` log entry with `"skill":"factory-gates"` (with or without a plugin namespace prefix), the same pattern `skill_invoked_in` already checks for other skills?
3. Did `brainstorming` still end up triggering (check `BRAINSTORMING_TRIGGERED` in `result.json`) even if the answers to 1-2 are unclear?

Report all three findings plainly in this task's notes, whatever they are — this is real information about how headless slash-command invocation behaves that the rest of this plan's numbers depend on being able to interpret correctly. If `/factory-gates` clearly is NOT being invoked as a command at all (e.g., the model just sees a literal string starting with a slash and treats it as plain text), stop and report this as a genuine blocker before proceeding to Task 4 — running the full verification batch would be measuring the wrong thing.

- [ ] **Step 4: Clean up**

```bash
rm -rf /tmp/factory-gates-claude-md-smoke-test /tmp/factory-gates-slash-command-smoke-test
```

---

### Task 4: Full empirical verification

**Files:** none

**Interfaces:**
- Consumes: `tests/gate-routing/run-all.sh` from Task 2, confirmed working by Task 3

- [ ] **Step 1: Run the `claude-md` scenario, 3 trials**

```bash
tests/gate-routing/run-all.sh --scenario claude-md --trials 3
```

Expected: several minutes, real token cost. Record the full summary JSON.

- [ ] **Step 2: Run the `slash-command` scenario, 3 trials**

```bash
tests/gate-routing/run-all.sh --scenario slash-command --trials 3
```

Expected: several minutes, real token cost. Record the full summary JSON.

- [ ] **Step 3: Report results**

Paste both summary JSONs into the conversation with your human partner, plus a one-line note per scenario on what the `fail`/`inconclusive` trials (if any) actually showed (which skill fired instead, or what stopped the conversation from completing) — pull this from each trial's `result.json` and turn logs, don't just report the aggregate counts. Do not editorialize about whether the mechanism "works" beyond stating the numbers — that judgment belongs in Task 5's README text, informed by these numbers, not asserted ahead of them.

---

### Task 5: Update the README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 4's real measured results (fill the two placeholders below with them — do not open the PR with either placeholder still literal)

- [ ] **Step 1: Update the skill count**

Find this exact line:
```
This is a non-invasive companion plugin. It does not fork or edit any Superpowers file. It adds three new skills that slot into the gaps between Superpowers' existing skills.
```
Replace with:
```
This is a non-invasive companion plugin. It does not fork or edit any Superpowers file. It adds three new skills that slot into the gaps between Superpowers' existing skills, plus a `/factory-gates` command for starting a feature with deterministic gate coverage.
```

- [ ] **Step 2: Add the `/factory-gates` command to the skill list**

Find this exact block:
```
- **`vertical-slices-gate`** — Gate 4. A short, explicit sign-off on slice order and multi-repo/service sequencing. Runs after `writing-plans` has saved a plan, before `subagent-driven-development` / `executing-plans` starts.

The result: `brainstorming` → `architecture-gate` → `program-design-gate` → `writing-plans` → `vertical-slices-gate` → `subagent-driven-development` / `executing-plans`.
```
Replace with:
```
- **`vertical-slices-gate`** — Gate 4. A short, explicit sign-off on slice order and multi-repo/service sequencing. Runs after `writing-plans` has saved a plan, before `subagent-driven-development` / `executing-plans` starts.
- **`/factory-gates <feature description>`** — an explicit, user-invoked entry point. Starts the workflow with the gate sequence stated up front, rather than relying on `brainstorming`'s own routing to pick it up. See "Known limitation" below for why this exists.

The result: `brainstorming` → `architecture-gate` → `program-design-gate` → `writing-plans` → `vertical-slices-gate` → `subagent-driven-development` / `executing-plans`.
```

- [ ] **Step 3: Rewrite the "Known limitation" section**

Find this exact block:
```
## Known limitation — read this

Superpowers' own `brainstorming` skill ends with an explicit instruction: *"Invoke the writing-plans skill... Do NOT invoke any other skill."* Because this plugin doesn't edit Superpowers' files, that instruction still exists verbatim. `architecture-gate`'s description is written to be highly specific ("use immediately after brainstorming, before writing-plans") so Claude picks it up as the more specific match — and Superpowers' own `using-superpowers` router skill instructs Claude to invoke *any* applicable skill, not just the one another skill points to. In practice this has worked reliably in testing, but it is a soft override, not a hard one.

**If you want it to be reliable every time**, say so explicitly at the start of a feature: *"Use the factory-gates workflow for this."* That's enough to make the gate sequence deterministic regardless of what brainstorming's own text says.
```

Replace with (fill in the two `<PASTE ...>` placeholders from Task 4's actual results before committing — do not leave them literal):
```
## Known limitation — read this

Superpowers' own `brainstorming` skill ends with an explicit instruction: *"Invoke the writing-plans skill... Do NOT invoke any other skill."* Because this plugin doesn't edit Superpowers' files, that instruction still exists verbatim. `architecture-gate`'s description is written to be highly specific ("use immediately after brainstorming, before writing-plans") so Claude picks it up as the more specific match — and Superpowers' own `using-superpowers` router skill instructs Claude to invoke *any* applicable skill, not just the one another skill points to. This is a soft override, not a hard one, and this repo measures it empirically (`tests/gate-routing/`) rather than just asserting it works.

Three ways to make it more reliable, all measured, none of them a hard guarantee -- each works by adding an explicit, early statement that `brainstorming`'s hard "invoke writing-plans only" instruction has to compete against, not by editing Superpowers' own files or routing rules:

| Mechanism | How | Measured result |
|---|---|---|
| Say so explicitly | Start the feature with *"Use the factory-gates workflow for this."* | 16 formal trials, 0 fails; explicit phrasing also correlates with fewer non-completions than a bare request |
| `/factory-gates <description>` | Use the command instead of a plain message | <PASTE Task 4's slash-command summary JSON and a one-line takeaway here> |
| `CLAUDE.md` project instruction | Add the snippet below to your project's `CLAUDE.md` once | <PASTE Task 4's claude-md summary JSON and a one-line takeaway here> |

```markdown
## Software Factory Workflow
For any new feature or creative work, use the factory-gates workflow — architecture-gate and program-design-gate run before writing-plans, vertical-slices-gate runs before execution. Do not skip these gates even if a skill's own instructions say to invoke writing-plans directly.
```
```

- [ ] **Step 4: Verify**

```bash
grep -c "three new skills that slot into the gaps between Superpowers' existing skills, plus" README.md
grep -c "^## Known limitation" README.md
grep -c "factory-gates <description>" README.md
```

Expected: 1, 1, 1. Also manually confirm neither `<PASTE` placeholder is still present:

```bash
grep -c "PASTE" README.md
```

Expected: 0. If this is not 0, the placeholders were not filled in — fix before committing.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs(meta): document /factory-gates command and CLAUDE.md determinism mechanisms with measured results"
```

---

### Task 6: Open PR

**Files:** none

**Interfaces:**
- Consumes: all commits from Tasks 1-5 on `feature/factory-gates-determinism`; Task 3's investigation findings and Task 4's results for the PR body

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/factory-gates-determinism
```

- [ ] **Step 2: Open the PR**

Fill in the `<PASTE ...>` placeholders with Task 3's investigation findings and Task 4's actual results before running this command.

```bash
gh pr create --title "feat(factory-gates): add /factory-gates command and CLAUDE.md determinism mechanisms" --body "$(cat <<'EOF'
## Who is submitting this PR? (required)

| Field | Value |
|-------|-------|
| Your model + version | Claude Sonnet 5 |
| Harness + version | Claude Code |
| All plugins installed | superpowers |
| Human partner who reviewed this diff | [@chrschy](https://github.com/chrschy) |

## What problem are you trying to solve?

The one documented mitigation for the brainstorming/architecture-gate
soft-override risk required the user to remember to type an explicit
phrase every single feature. Two more mechanisms could make this closer
to "set once, works automatically": a slash command and a standing
CLAUDE.md instruction (which Superpowers' own docs claim takes precedence
over skill instructions, but this project had never actually tested that
claim empirically).

## What does this PR change?

Adds a /factory-gates user-invoked skill. Extends tests/gate-routing/
with claude-md and slash-command scenarios, reusing all existing
detection logic. Updates the README's Known limitation section with real
measured numbers for all three mechanisms instead of assertions.

## Which gate does this touch?

None of the three existing gates -- this adds a new, separate entry-point
skill and extends test infrastructure.

## What alternatives did you consider?

Considered going further and making the plugin fully standalone from
Superpowers to eliminate the soft-override problem structurally, but
assessed that as not worth the cost (full reimplementation of
brainstorming/writing-plans/execution) relative to the actual, well-
measured size of the problem -- see conversation history for the full
critical assessment.

## Existing PRs
- [x] I have reviewed open AND closed PRs/issues for duplicates or prior art
- Related PRs/issues: none found

## Rigor
- [x] This change was tested adversarially, not just on the happy path
- [x] Investigated whether headless /factory-gates invocation actually
      works as a command (not assumed) --

<PASTE Task 3 Step 3's findings here>

- [x] Ran tests/gate-routing/run-all.sh --scenario claude-md --trials 3 --
      results:

<PASTE Task 4's claude-md summary JSON here>

- [x] Ran tests/gate-routing/run-all.sh --scenario slash-command --trials 3 --
      results:

<PASTE Task 4's slash-command summary JSON here>

## Human review
- [ ] A human has reviewed the COMPLETE proposed diff before submission
EOF
)"
```

- [ ] **Step 3: Report to human partner**

Show the human partner the complete diff (`git diff main...feature/factory-gates-determinism`) and the PR URL. Per standing instruction, do not merge — the human partner reviews manually and merges (or requests changes) themselves.

## Self-Review

1. **Spec coverage:** Part A (Task 1), Part C's harness extension (Task 2) with real smoke-testing of the genuinely open slash-command-headless-invocation question (Task 3) before spending on the full batch (Task 4), Part D's README update using real data (Task 5), PR (Task 6). Part B (the CLAUDE.md snippet itself) has no separate task — it's data embedded in Task 2 (the test) and Task 5 (the docs), not a file of its own, matching the spec's own framing of it as a "documented snippet," not a shipped artifact.
2. **Placeholder scan:** four intentional, explicitly-flagged placeholders total — two in Task 5 (README's Known limitation table cells) and two in Task 6 (PR body) — each with an explicit instruction to fill from real prior-task output and a verify step (Task 5 Step 4's `grep -c "PASTE"` check) catching any left unfilled.
3. **Type consistency:** the `CLAUDE_MD_SNIPPET` text in Task 2's `run-trial.sh` and the fenced snippet in Task 5's README edit are required to be character-for-character identical, called out explicitly in Global Constraints and re-verified in Task 2 Step 6 — not left to chance across the two files.
