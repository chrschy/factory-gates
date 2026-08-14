# factory-gates — Fix Judge Tool Sandboxing

**Status:** approved
**Date:** 2026-08-14

## Why

PR #6's verification run (`tests/gate-quality/architecture-gate/`) surfaced a real methodological gap: one trial's judge output referenced the fix commit under test by SHA, in its own reasoning. The judge is meant to score a document based solely on the text it's given in the prompt — but `run_judge`'s `claude -p` invocation runs with normal tool access (Bash, Read, Glob, etc.), so the model can and did look around the actual repo checkout instead of staying confined to the prompt. In that instance the document-level reasoning was still substantive, not just deferential — but a judge that can see it's evaluating a specific, named fix is a real bias risk, and this needs to be closed before the same judge pattern gets reused for `program-design-gate` and `vertical-slices-gate`.

## Fix

One change, scoped to `run_judge` only, in `tests/gate-quality/architecture-gate/lib/judge.sh`:

Add two flags to the `claude -p` invocation:
- `--disallowedTools "Bash,Read,Write,Edit,NotebookEdit,Glob,Grep,WebFetch,WebSearch,Task,TodoWrite,ExitPlanMode"` — blocks filesystem, command execution, and subagent dispatch. Verified empirically: with this list, a `claude -p` call genuinely cannot read local files or run commands, and says so rather than silently working around it.
- `--strict-mcp-config` (with no `--mcp-config` supplied) — disables all MCP server tool access (this environment has Google Drive/Atlassian/Notion connectors available by default; none of them can see local repo state, but closing this off matches the design intent of "the judge sees only the prompt").

`run_turn` (the actual conversation under test — `brainstorming`/`architecture-gate` genuinely doing work) is not touched; it needs full tool access to write files, commit, etc. Only the read-only judge call changes.

## Verification

Re-run `tests/gate-quality/architecture-gate/run-all.sh` (default 3 trials) and confirm:
1. The suite still functions normally (trials complete, verdicts parse).
2. No judge output references anything outside the document it was given (no commit SHAs, no file paths beyond what's quoted in the doc itself, no claims about "the rest of the repo").

## Self-review

- **Placeholders:** none — the exact flag values are given.
- **Internal consistency:** scoped explicitly to not touch `run_turn`, which the spec states outright to prevent a well-intentioned but wrong "sandbox everything" overreach.
- **Scope:** one function, two flags, in the one file responsible for the judge call.
- **Ambiguity:** none — the fix was validated empirically before this spec was written, not proposed speculatively.
