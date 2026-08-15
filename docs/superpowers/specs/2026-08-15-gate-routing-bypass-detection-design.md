# factory-gates — Detect Skill-Bypass in Gate-Routing Trials

**Status:** approved
**Date:** 2026-08-15

## Why

Re-running `tests/gate-routing/run-all.sh` (default 3 bare + 3 explicit trials) after both the `git init` fix (PR #9) and the canned-feature-request language fix (PR #11) surfaced a new, real failure mode: all 3 `bare` trials show `brainstorming` never invoked at all — turn 1 instead invokes `superpowers:test-driven-development` directly and starts implementing. This is a more severe failure than the one the harness was built to detect (`writing-plans` invoked without `architecture-gate` first): the model skips the entire gate model, not just one gate.

The harness already logs this correctly (the `Skill` tool call for `test-driven-development` is right there in `turn1.json`), but `run-trial.sh`'s classification logic doesn't look for it. Its final line unconditionally sets `outcome="inconclusive"` whenever `brainstorming` never triggered, regardless of what else happened — collapsing "nothing happened, harness/environment issue" and "something else happened instead of brainstorming" into the same bucket. The suite's own README describes `inconclusive` as "not a signal about factory-gates' routing," which is actively wrong for this case.

## Fix

Two files change:

**`tests/gate-routing/lib/common.sh`** — add one helper:

```bash
# Returns the name of the first Skill tool invocation in a log file
# (namespace prefix stripped, e.g. "superpowers:test-driven-development"
# -> "test-driven-development"), or nothing if no Skill call appears.
first_skill_invoked_in() {
    local log_file="$1"
    grep -o '"skill":"[^"]*"' "$log_file" 2>/dev/null | head -1 | \
        sed -E 's/"skill":"([^:"]*:)?([^"]*)"/\2/'
}
```

**`tests/gate-routing/run-trial.sh`** — in the per-turn loop, after the existing `architecture-gate` and `writing-plans` checks (which already `break` on match), add a third check:

```bash
    if [ "$BRAINSTORMING_TRIGGERED" = "false" ]; then
        CANDIDATE="$(first_skill_invoked_in "$LOG_FILE")"
        if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "brainstorming" ]; then
            BYPASS_SKILL="$CANDIDATE"
            OUTCOME="fail"
            break
        fi
    fi
```

with `BYPASS_SKILL=""` initialized alongside the loop's other tracking variables. This only fires while `brainstorming` genuinely hasn't triggered yet (the guard reads the same flag the existing `architecture-gate`/`writing-plans` checks already set), so a turn where `brainstorming` and another skill both happen to appear together is never misclassified.

The existing final fallback (`if BRAINSTORMING_TRIGGERED=false: OUTCOME=inconclusive`) stays as-is, now correctly reserved for genuine no-signal cases: a crash, a timeout, or a turn where literally nothing was invoked.

`result.json` gains one new field, always present:

```json
"bypass_skill": "test-driven-development"
```

(empty string `""` when not applicable), so a `fail` outcome's cause is visible without opening raw turn logs.

`run-all.sh`'s summary logic is untouched — `outcome` stays a three-value enum (`pass`/`fail`/`inconclusive`), so its `jq` aggregation continues to work without modification.

## Documentation updates

**`README.md`** (repo root), "Known limitation" section: the `[!WARNING]` callout currently describes the risk narrowly as `architecture-gate` losing out to `writing-plans`. Add that a bare request can skip `brainstorming` entirely and go straight to an unrelated skill (e.g. `test-driven-development`) — the more severe pattern this fix newly makes visible.

Determinism table: refresh with real post-fix numbers.
- **explicit**: fold the 3 fresh trials from this fix's verification run into the existing "16 formal trials, 0 fails" figure (19 total), since explicit's classification behavior is unaffected by this fix (the bypass check only matters when `brainstorming` doesn't fire) — the underlying trials remain valid evidence.
- **bare**: publish an actual measured baseline for the first time. Previously the table only had the qualitative line "explicit phrasing also correlates with fewer non-completions than a bare request"; now there's a real number to state directly instead.

**`tests/gate-routing/README.md`**, "Reading the output" section: explain the new `bypass_skill` field and that `fail` now covers two distinct patterns (writing-plans without architecture-gate, and any other skill invoked before brainstorming fires).

## Verification

Two steps, in order:

1. **Free, deterministic check against already-captured data.** The bare-scenario logs from the run that surfaced this bug (`/tmp/factory-gates-tests/1786783482/bare/trial-{1,2,3}/turn1.json`) already contain the exact case under test. Run `first_skill_invoked_in` against them directly and confirm it returns `test-driven-development` for all three, before spending any new API calls.
2. **Fresh live run** of `tests/gate-routing/run-all.sh` (default 3 bare + 3 explicit trials) as real before/after evidence for the PR — "before" is the run already captured in this conversation (bare: 3/3 inconclusive under the old classification; explicit: 3/3 pass), "after" should show bare reclassified as fail with `bypass_skill` populated, and explicit unchanged at pass.

## Scope note

This fix applies to `bare`/`explicit` only. The `claude-md` and `slash-command` scenarios were measured before this classification existed too (3 trials each, 2 pass/1 inconclusive), but re-verifying those is out of scope here — tracked as a separate backlog item.

## Self-review

- **Placeholders:** none — exact code, exact field names, exact file paths given.
- **Internal consistency:** the fix only changes classification of an existing signal already present in the logs; it does not change what `run_turn` does or how trials are driven.
- **Scope:** two files for the harness fix, two READMEs for documentation, no changes to `run-all.sh`'s aggregation logic or to any gate skill.
- **Ambiguity:** none — the failure mode was observed directly in real trial logs before this spec was written, not proposed speculatively.
