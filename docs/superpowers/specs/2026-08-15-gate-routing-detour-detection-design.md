# factory-gates — Detect Mid-Brainstorming Detour in Gate-Routing Trials

**Status:** approved
**Date:** 2026-08-15

## Why

PR #12 fixed classification for trials where `brainstorming` never fires at all. Its own live verification run surfaced a related but distinct pattern: `brainstorming` fires correctly in turn 1, then gets abandoned mid-conversation for `superpowers:test-driven-development` in turn 2, before `architecture-gate` or `writing-plans` ever fires.

Investigating this directly (5 fresh `bare` trials, real `claude -p` runs) confirms it's reproducible, not one-off noise: combined with PR #12's verification run, 3 of 8 `bare` trials this session (37.5%) show this detour. Of those 3: 1 self-corrected — the model eventually invoked `architecture-gate` by turn 4 anyway (outcome: `pass`) — and 2 never recovered within the 4-turn budget (outcome: `inconclusive`).

This is currently invisible in `result.json`. A passing trial that detoured looks identical to one that never did. An inconclusive trial that got derailed into implementation looks identical to one that legitimately ran out of turns during ordinary design back-and-forth. Both are real, different situations worth being able to tell apart.

## Fix

Unlike PR #12's bypass fix, this does **not** change outcome classification. What this suite measures — does `architecture-gate` fire before `writing-plans` — is unaffected by whether the model took a detour first and self-corrected; a self-correcting detour that still reaches `architecture-gate` is a legitimate `pass` under that definition. This is purely a diagnostic addition.

**`tests/gate-routing/run-trial.sh`** — reuse `first_skill_invoked_in` (added in PR #12). Add `DETOUR_SKILL=""` alongside the existing tracking variables. In the per-turn loop, once `BRAINSTORMING_TRIGGERED` is true (i.e. after the point PR #12's bypass check no longer applies) and before the turn's `architecture-gate`/`writing-plans` checks would already have broken the loop, check whether the turn's log shows any skill other than `architecture-gate` or `writing-plans`; if so and `DETOUR_SKILL` is still empty, record it (first occurrence only — don't overwrite on a later turn).

```bash
    if [ "$BRAINSTORMING_TRIGGERED" = "true" ] && [ -z "$DETOUR_SKILL" ]; then
        CANDIDATE="$(first_skill_invoked_in "$LOG_FILE")"
        if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "architecture-gate" ] && [ "$CANDIDATE" != "writing-plans" ]; then
            DETOUR_SKILL="$CANDIDATE"
        fi
    fi
```

Placed after the existing `architecture-gate`/`writing-plans` checks in the loop (which `break` on match), so a turn that fires `architecture-gate` directly is never flagged as a detour. Does not `break` — the loop continues normally; this only records, it never changes control flow or `OUTCOME`.

`result.json` gains one new field, always present:

```json
"detour_skill": "test-driven-development"
```

(empty string when no detour occurred).

## Documentation updates

**`README.md`**, bare-scenario table row: add the detour rate as an additional data point alongside the existing pass/fail/inconclusive counts, using real numbers from this fix's verification run (8 cumulative bare trials: 3 detoured, 1 of those still passed, 2 went inconclusive).

**`tests/gate-routing/README.md`**, "Reading the output" section: add a short explanation of `detour_skill`, clarifying it's diagnostic only and does not affect `outcome`.

## Verification

1. Re-verify `first_skill_invoked_in` correctly identifies the detour skill against the already-captured logs from this investigation (`/tmp/factory-gates-item17-investigation/trial-3/turn2.json`, `trial-4/turn2.json`) — no new API calls needed for this part.
2. Fresh live run of `tests/gate-routing/run-all.sh --scenario bare --trials 3` to confirm the new field populates correctly end-to-end and `outcome` classification is unchanged from what it would have been without this fix.

## Self-review

- **Placeholders:** none — exact code, exact field name, exact file paths given.
- **Internal consistency:** explicitly does not touch `OUTCOME` or `run-all.sh`'s aggregation — stated twice (Fix section and Why section) to prevent scope creep into reclassification, which PR #12 already handled for the pre-brainstorming case.
- **Scope:** one file for the harness change (`run-trial.sh`), two READMEs for documentation, no changes to `common.sh` (reuses PR #12's existing helper) or `run-all.sh`.
- **Ambiguity:** none — the pattern was directly observed and reproduced (5 fresh trials plus PR #12's verification run) before this spec was written.
