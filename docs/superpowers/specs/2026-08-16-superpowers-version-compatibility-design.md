# factory-gates — Superpowers Version-Compatibility Stance

**Status:** approved
**Date:** 2026-08-16

## Why

factory-gates has never stated what Superpowers version range it's actually been developed and verified against. This repo's own Superpowers install auto-updated from 6.2.0 to 6.3.0 partway through this session's work, and every suite kept passing across that bump — real, first-hand evidence worth writing down rather than leaving implicit.

Checked directly (not assumed): the Claude Code plugin manifest format has no `dependencies` field for declaring a version range on another plugin — verified against every `plugin.json` in this environment's local marketplace cache, including Superpowers' own. So this can only be a **documented** stance, not a mechanically enforced one via the manifest. A lightweight runtime warning in the test harness is the closest thing to enforcement available, and it's cheap enough to add.

## Part A — README section

New section, placed after "Known limitation" and before "Credits" in the root `README.md`:

```markdown
## 🔗 Superpowers compatibility

Verified against Superpowers **6.2.0 – 6.3.0**. There's no dependency-version mechanism in the Claude Code plugin format to declare this formally — `plugin.json` has no `dependencies` field, checked directly against every plugin manifest in this environment's local marketplace cache, including Superpowers' own. This is a documented, empirically-tracked stance, not a mechanically enforced one.

The coupling is narrow but real: factory-gates' routing strategy (see "Known limitation" above) depends on specific wording in Superpowers' own skills, not any formal API —
- `brainstorming`'s hard "invoke writing-plans... do NOT invoke any other skill" instruction
- `using-superpowers`'s "if a skill applies, you MUST use it" routing rule

If a future Superpowers release changes that wording materially, factory-gates' soft-override strategy could degrade silently — there is no automated check outside of actually running the test suites.

`tests/gate-routing/lib/common.sh` prints a warning to stderr if the installed Superpowers version falls outside the verified range (older: a real warning; newer: a softer note, since untested doesn't mean broken) every time a test suite resolves the Superpowers plugin directory. If you see one, or if you've just updated Superpowers and something in the factory-gates workflow feels off, re-run `tests/gate-routing/run-all.sh` — that's exactly the empirical check this exists for.
```

## Part B — Runtime version check in the test harness

Added to `tests/gate-routing/lib/common.sh` (sourced by every suite in this repo):

```bash
# The Superpowers version range this repo's routing strategy has been
# empirically verified against (see README's "Superpowers compatibility"
# section for what that coupling actually depends on).
TESTED_SUPERPOWERS_MIN="6.2.0"
TESTED_SUPERPOWERS_MAX="6.3.0"

# Compares two dotted version strings. Prints "lt", "eq", or "gt" for how
# the first compares to the second.
_compare_versions() {
    local v1="$1" v2="$2"
    if [ "$v1" = "$v2" ]; then
        echo "eq"
        return
    fi
    local lower
    lower="$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -1)"
    if [ "$lower" = "$v1" ]; then
        echo "lt"
    else
        echo "gt"
    fi
}

# Warns (stderr only -- callers capture resolve_superpowers_dir's return
# value via command substitution, so stdout must stay clean) if the given
# Superpowers version falls outside the range this repo's tests have
# actually been run against.
_warn_if_superpowers_version_untested() {
    local version="$1"
    if [ "$(_compare_versions "$version" "$TESTED_SUPERPOWERS_MIN")" = "lt" ]; then
        echo "WARNING: installed Superpowers version ($version) is older than the minimum this repo's tests have been verified against ($TESTED_SUPERPOWERS_MIN). Routing/quality results may not reflect current expected behavior." >&2
    elif [ "$(_compare_versions "$version" "$TESTED_SUPERPOWERS_MAX")" = "gt" ]; then
        echo "NOTE: installed Superpowers version ($version) is newer than the last version this repo's tests have been verified against ($TESTED_SUPERPOWERS_MAX). If routing/quality results look unexpected, this is the first thing to check -- see the README's \"Superpowers compatibility\" section." >&2
    fi
}
```

`resolve_superpowers_dir` calls `_warn_if_superpowers_version_untested "$(basename "$version_dir")"` right before its final `echo "$version_dir"` (the function's actual return value, via stdout) — only in the auto-discovered path (`$HOME/.claude/plugins/cache/...`), not when `SUPERPOWERS_PLUGIN_DIR` overrides to a custom checkout, since a custom checkout's version can't be reliably read the same way and is out of scope for this check.

Reuses `sort -V` for comparison, consistent with `resolve_superpowers_dir`'s own existing version-directory discovery in the same file — no new external dependency.

## Verification

1. `_compare_versions` and `_warn_if_superpowers_version_untested` verified against the real installed versions on this machine (6.2.0, 6.3.0) plus synthetic below/above-range values (e.g. `6.1.0`, `6.4.0`), via a scratch script sourcing `common.sh` directly — no live `claude -p` calls needed, consistent with how this file's other recent additions (`first_skill_invoked_in`, `extract_assistant_text`) were verified this session.
2. Confirm `resolve_superpowers_dir`'s actual return value (stdout) is unaffected by the warning — the function must still print only the directory path on stdout, nothing else, since every call site captures it via `$(...)`.
3. One real `tests/gate-routing/run-trial.sh` invocation to confirm nothing broke end-to-end (the currently-installed version, 6.3.0, is within range, so this specific run should be silent — no warning expected, which is itself the thing being verified).

## Self-review

- **Placeholders:** none — exact README section and exact bash code given.
- **Internal consistency:** explicitly scoped to the auto-discovered path only, not `SUPERPOWERS_PLUGIN_DIR` overrides — stated directly rather than left ambiguous.
- **Scope:** one README section, one small addition to one already-shared file, no changes to any gate skill or to `run-all.sh`'s aggregation logic.
- **Ambiguity:** the "warn on older, softer note on newer" asymmetry was a deliberate design choice made during the design conversation (a hard ceiling would generate noise on every routine Superpowers update without evidence of actual breakage), not an accidental inconsistency.
