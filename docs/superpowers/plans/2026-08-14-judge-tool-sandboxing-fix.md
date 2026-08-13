# Fix Judge Tool Sandboxing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Confine `tests/gate-quality/architecture-gate/lib/judge.sh`'s `run_judge` to reasoning over only the document text it's given, closing the real bias risk PR #6's verification run surfaced (the judge referenced a fix commit by SHA, meaning it had normal filesystem/tool access instead of being isolated to the prompt).

**Architecture:** One-line change to `run_judge`'s `claude -p` invocation: add `--disallowedTools` (blocks Bash/Read/Write/Edit/NotebookEdit/Glob/Grep/WebFetch/WebSearch/Task/TodoWrite/ExitPlanMode) and `--strict-mcp-config` (blocks all MCP server tool access, since none is supplied via `--mcp-config`). `run_turn` (the actual conversation under test) is untouched — it needs full tool access to do real work.

**Tech Stack:** bash, the `claude` CLI's own flag surface — no new dependency.

## Global Constraints

- Only `run_judge` in `tests/gate-quality/architecture-gate/lib/judge.sh` changes. `run_turn` in `tests/gate-routing/lib/common.sh` (shared, used by both the routing and quality suites) is explicitly out of scope — it needs full tool access for the real conversation being tested.
- Exact flag values: `--disallowedTools "Bash,Read,Write,Edit,NotebookEdit,Glob,Grep,WebFetch,WebSearch,Task,TodoWrite,ExitPlanMode"` and `--strict-mcp-config`.
- Verification is a real re-run of `tests/gate-quality/architecture-gate/run-all.sh` (3 trials, real tokens, several minutes), checking both that the suite still works and that no judge output references anything outside the document it was given.

## File Structure

No new files. One file modified: `tests/gate-quality/architecture-gate/lib/judge.sh`.

---

### Task 1: Sandbox the judge, verify, PR

**Files:**
- Modify: `tests/gate-quality/architecture-gate/lib/judge.sh:59`

**Interfaces:** none (single-function change; `run_judge`'s signature and behavior on success are unchanged, only its tool access is restricted)

- [ ] **Step 1: Create the branch**

```bash
cd /home/christopher/PycharmProjects/factory-gates
git checkout main
git pull
git checkout -b fix/judge-tool-sandboxing
```

- [ ] **Step 2: Edit `run_judge`'s `claude -p` invocation**

Find this exact line:
```
    timeout 120 claude -p "$prompt" --dangerously-skip-permissions > "$output_file" 2>&1 || true
```

Replace it with:
```
    timeout 120 claude -p "$prompt" --dangerously-skip-permissions \
        --disallowedTools "Bash,Read,Write,Edit,NotebookEdit,Glob,Grep,WebFetch,WebSearch,Task,TodoWrite,ExitPlanMode" \
        --strict-mcp-config \
        > "$output_file" 2>&1 || true
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n tests/gate-quality/architecture-gate/lib/judge.sh
```

Expected: no output, exit 0.

- [ ] **Step 4: Smoke-test that the sandboxing actually works**

```bash
source tests/gate-quality/architecture-gate/lib/judge.sh
TMPDOC="$(mktemp)"
echo "# Test Doc" > "$TMPDOC"
echo "" >> "$TMPDOC"
echo "## Components" >> "$TMPDOC"
echo "- Foo -- does foo things" >> "$TMPDOC"
run_judge "$TMPDOC" /tmp/judge-sandbox-test-output.txt
cat /tmp/judge-sandbox-test-output.txt
rm -f "$TMPDOC"
```

Expected: the judge still produces a real review (it can read and reason about the document content embedded in its prompt — that's not blocked, only its ability to use tools is). It should NOT show any sign of exploring the filesystem, referencing git history, or mentioning anything not contained in the prompt/document. If you want to actively confirm the block works (not just its absence), you can temporarily test with a prompt that asks it to try using Bash (e.g. adapt the pattern already verified manually: `claude -p "try to list files using any tool" --disallowedTools "..." --strict-mcp-config --dangerously-skip-permissions`) and confirm it reports being unable to, matching the behavior already confirmed during this fix's brainstorming.

- [ ] **Step 5: Commit**

```bash
rm -f /tmp/judge-sandbox-test-output.txt
git add tests/gate-quality/architecture-gate/lib/judge.sh
git commit -m "fix(tests): sandbox the architecture-gate quality judge to the prompt only"
```

- [ ] **Step 6: Re-run the full gate-quality suite as verification**

```bash
tests/gate-quality/architecture-gate/run-all.sh
```

Expected: takes several minutes (3 real trials, ~7 turns each plus judge calls), real token cost. Record the full summary JSON.

- [ ] **Step 7: Check judge outputs for sandbox leakage**

For each trial's `judge_output_file` (paths are in each trial's `result.json`), read the content and confirm it contains nothing beyond what's traceable to the document text itself — no commit SHAs, no file paths not quoted in the document, no claims about "the rest of the repo" or anything requiring filesystem access. Report any leakage found as a real problem, not a pass.

- [ ] **Step 8: Push, open PR, human review gate, merge**

```bash
git push -u origin fix/judge-tool-sandboxing
```

Fill in the `<PASTE ...>` placeholder with Step 6/7's actual results before running this command.

```bash
gh pr create --title "fix(tests): sandbox architecture-gate quality judge to prompt only" --body "$(cat <<'EOF'
## Who is submitting this PR? (required)

| Field | Value |
|-------|-------|
| Your model + version | Claude Sonnet 5 |
| Harness + version | Claude Code |
| All plugins installed | superpowers |
| Human partner who reviewed this diff | [@chrschy](https://github.com/chrschy) |

## What problem are you trying to solve?

PR #6's verification run showed a judge output referencing the fix commit
under test by SHA -- the judge (tests/gate-quality/architecture-gate/lib/
judge.sh's run_judge) had normal tool access instead of being confined to
the document text in its prompt, and used it. A judge that can see it's
evaluating a specific named fix is a real bias risk, and this needed
closing before the same pattern gets reused for other gates' quality
suites.

## What does this PR change?

Adds --disallowedTools and --strict-mcp-config to run_judge's claude -p
invocation, confirmed empirically to block filesystem/Bash/MCP access
while leaving normal reasoning over the given prompt text intact.

## Which gate does this touch?

None directly -- this is test infrastructure (the judge harness used by
tests/gate-quality/architecture-gate/), not a gate's own SKILL.md.

## What alternatives did you consider?

Considered sandboxing run_turn too, but that's the actual conversation
under test (brainstorming/architecture-gate genuinely need to read/write
files and commit) -- only the read-only judge call needed restricting.

## Existing PRs
- [x] I have reviewed open AND closed PRs/issues for duplicates or prior art
- Related PRs/issues: none found

## Rigor
- [x] This change was tested adversarially, not just on the happy path
- [x] Confirmed empirically (during brainstorming, and again in Step 4)
      that --disallowedTools genuinely blocks filesystem/Bash access
- [x] Ran tests/gate-quality/architecture-gate/run-all.sh after the fix --
      results:

<PASTE Step 6's summary JSON here>

- [x] Checked every trial's judge_output_file for sandbox leakage (commit
      SHAs, untraced file paths, repo-context claims):

<PASTE Step 7's findings here -- "none found" or the leakage detail>

## Human review
- [ ] A human has reviewed the COMPLETE proposed diff before submission
EOF
)"
```

- [ ] **Step 9: Human review gate**

Stop here. Show the human partner the complete diff (`git diff main...fix/judge-tool-sandboxing`), the PR URL, and the verification results. Do not proceed to Step 10 until they explicitly approve.

- [ ] **Step 10: Merge**

```bash
gh pr merge --squash --delete-branch --admin
```

- [ ] **Step 11: Verify**

```bash
git checkout main
git pull
grep -n "disallowedTools" tests/gate-quality/architecture-gate/lib/judge.sh
```

Expected: one match, confirming the fix is live on `main`.

## Self-Review

1. **Spec coverage:** the exact flag change from the spec (Step 2), syntax + functional smoke-test (Steps 3-4), real-suite verification with explicit leakage checking (Steps 6-7, directly addressing what the spec calls out — not just "does it still work" but "is the leak actually closed"), PR/merge flow (Steps 8-11).
2. **Placeholder scan:** two intentional, explicitly-flagged placeholders in Step 8 (`<PASTE Step 6's summary JSON here>`, `<PASTE Step 7's findings here>`), same pattern as every prior plan in this repo.
3. **Type consistency:** N/A — no code interfaces change, `run_judge`'s signature and callers (`run-trial.sh`) are untouched.
