# Superpowers Version-Compatibility Stance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document the real Superpowers version range factory-gates has been verified against, explain the coupling risk explicitly, and add a lightweight runtime warning in the test harness when the installed version falls outside that range.

**Architecture:** One new README section. Three small additions to `tests/gate-routing/lib/common.sh` (two constants, two helper functions), wired into the existing `resolve_superpowers_dir`. No changes to any gate skill.

**Tech Stack:** bash, `sort -V` for version comparison (already used elsewhere in the same file).

## Global Constraints

- The version check applies only to the auto-discovered Superpowers plugin directory (`$HOME/.claude/plugins/cache/claude-plugins-official/superpowers`). It must not run, or must be skipped cleanly, when `SUPERPOWERS_PLUGIN_DIR` overrides to a custom checkout.
- `resolve_superpowers_dir`'s stdout must remain exactly the directory path, nothing else — all warning/note output goes to stderr only, since every call site captures the function's return value via `$(...)`.
- `TESTED_SUPERPOWERS_MIN="6.2.0"` and `TESTED_SUPERPOWERS_MAX="6.3.0"` are the real versions this repo has actually been run against this session — not placeholders.

---

### Task 1: Add the version-check helpers and verify them

**Files:**
- Modify: `tests/gate-routing/lib/common.sh`

**Interfaces:**
- Produces: `_compare_versions <v1> <v2>` — prints `lt`/`eq`/`gt`. `_warn_if_superpowers_version_untested <version>` — prints a warning/note to stderr if outside range, silent otherwise. Both are internal helpers (leading underscore), not used outside this file.

- [ ] **Step 1: Add the constants and helper functions**

Add near the top of `tests/gate-routing/lib/common.sh`, after the `set -euo pipefail` line and before `resolve_superpowers_dir`:

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

- [ ] **Step 2: Wire the check into `resolve_superpowers_dir`**

Find the end of `resolve_superpowers_dir`:

```bash
    local version_dir
    version_dir="$(find "$cache_root" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
    if [ -z "$version_dir" ]; then
        echo "ERROR: No version directories found in $cache_root" >&2
        exit 1
    fi
    echo "$version_dir"
}
```

Replace with:

```bash
    local version_dir
    version_dir="$(find "$cache_root" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
    if [ -z "$version_dir" ]; then
        echo "ERROR: No version directories found in $cache_root" >&2
        exit 1
    fi
    _warn_if_superpowers_version_untested "$(basename "$version_dir")"
    echo "$version_dir"
}
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n tests/gate-routing/lib/common.sh
```

Expected: no output.

- [ ] **Step 4: Verify the comparison logic and warning behavior directly (no live API calls)**

```bash
source tests/gate-routing/lib/common.sh
echo "6.1.0 vs 6.2.0: $(_compare_versions 6.1.0 6.2.0)"
echo "6.2.0 vs 6.2.0: $(_compare_versions 6.2.0 6.2.0)"
echo "6.4.0 vs 6.3.0: $(_compare_versions 6.4.0 6.3.0)"
echo "--- below range (expect WARNING on stderr) ---"
_warn_if_superpowers_version_untested "6.1.0"
echo "--- in range (expect no output) ---"
_warn_if_superpowers_version_untested "6.2.5"
echo "--- above range (expect NOTE on stderr) ---"
_warn_if_superpowers_version_untested "6.4.0"
```

Expected: `lt`, `eq`, `gt` respectively for the three comparisons; a `WARNING:` line for 6.1.0; no output at all for 6.2.5; a `NOTE:` line for 6.4.0.

- [ ] **Step 5: Verify `resolve_superpowers_dir`'s stdout stays clean**

```bash
RESULT="$(resolve_superpowers_dir)"
echo "Captured: $RESULT"
```

Expected: `Captured: <path ending in .../superpowers/6.3.0>` (or whatever version is actually installed) with no warning text embedded in `$RESULT` — confirms the function's real callers (which all use `$(...)` capture) never see stray warning text mixed into the path they depend on.

- [ ] **Step 6: Commit**

```bash
git add tests/gate-routing/lib/common.sh
git commit -m "feat(tests): warn when installed Superpowers version is outside the verified range"
```

---

### Task 2: Add the README section

**Files:**
- Modify: `README.md`

**Interfaces:** none

- [ ] **Step 1: Add the new section**

Insert after the "Known limitation" section's closing content (after the `CLAUDE.md` snippet code block and before `## 🙏 Credits`):

```markdown
## 🔗 Superpowers compatibility

Verified against Superpowers **6.2.0 – 6.3.0**. There's no dependency-version mechanism in the Claude Code plugin format to declare this formally — `plugin.json` has no `dependencies` field, checked directly against every plugin manifest in this environment's local marketplace cache, including Superpowers' own. This is a documented, empirically-tracked stance, not a mechanically enforced one.

The coupling is narrow but real: factory-gates' routing strategy (see "Known limitation" above) depends on specific wording in Superpowers' own skills, not any formal API —
- `brainstorming`'s hard "invoke writing-plans... do NOT invoke any other skill" instruction
- `using-superpowers`'s "if a skill applies, you MUST use it" routing rule

If a future Superpowers release changes that wording materially, factory-gates' soft-override strategy could degrade silently — there is no automated check outside of actually running the test suites.

`tests/gate-routing/lib/common.sh` prints a warning to stderr if the installed Superpowers version falls outside the verified range (older: a real warning; newer: a softer note, since untested doesn't mean broken) every time a test suite resolves the Superpowers plugin directory. If you see one, or if you've just updated Superpowers and something in the factory-gates workflow feels off, re-run `tests/gate-routing/run-all.sh` — that's exactly the empirical check this exists for.

```

- [ ] **Step 2: Verify placement and content**

```bash
grep -n "^## " README.md
grep -c "6.2.0 – 6.3.0" README.md
```

Expected: the section list shows `## 🔗 Superpowers compatibility` between `## ⚠️ Known limitation` and `## 🙏 Credits`; the version-range string appears at least once.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(meta): document Superpowers version-compatibility stance"
```

---

### Task 3: Live verification, PR

**Files:** none (verification + git/GitHub operations only)

**Interfaces:** none

- [ ] **Step 1: One real trial to confirm nothing broke end-to-end**

```bash
tests/gate-routing/run-trial.sh bare /tmp/factory-gates-version-check-smoke-test
```

Expected: the trial runs and completes normally (produces a `result.json`), and since the currently-installed Superpowers version (6.3.0) is within the verified range, no `WARNING:`/`NOTE:` line should appear in the command's own output — confirming the check is silent in the expected common case, not just that it doesn't crash anything.

- [ ] **Step 2: Clean up the smoke-test directory**

```bash
rm -rf /tmp/factory-gates-version-check-smoke-test
```

- [ ] **Step 3: Push, open PR**

```bash
git push -u origin feature/superpowers-version-compatibility
```

Open the PR with `gh pr create`, following this repo's established template: who's submitting, what problem (no documented version-compatibility stance existed), what changed (README section + warning mechanism), which gate (none), alternatives considered (documented-only vs. documented + lightweight runtime warning — both chosen, per explicit design decision; also note the plugin-manifest `dependencies` field was checked to not exist rather than assumed), existing-PRs checkbox, rigor section citing the local verification and the live smoke-test result, human-review checkbox unchecked.

- [ ] **Step 4: Report to human partner**

Show the complete diff (`git diff main...feature/superpowers-version-compatibility`) and the PR URL. Per standing instruction, do not merge.

## Self-Review

1. **Spec coverage:** Task 1 covers the harness helpers and their verification; Task 2 covers the README section; Task 3 covers live confirmation and PR. Every part of the design spec has a corresponding task.
2. **Placeholder scan:** none — every code block and every doc paragraph is exact final text, including the real tested version numbers.
3. **Type consistency:** `TESTED_SUPERPOWERS_MIN`/`TESTED_SUPERPOWERS_MAX` and `_compare_versions`/`_warn_if_superpowers_version_untested` naming is identical between Task 1's definition and its own wiring into `resolve_superpowers_dir`; the README's stated range (6.2.0 – 6.3.0) matches the constants exactly.
