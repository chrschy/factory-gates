# Automated Release Versioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A manually-triggered GitHub Actions workflow that computes the next SemVer version from Conventional Commits history since the last tag, bumps `plugin.json`/`marketplace.json`, tags `main`, and publishes a GitHub Release with generated notes.

**Architecture:** Pure-function version-calculation logic lives in a sourceable bash library (`.github/scripts/lib/version-calc.sh`), unit-tested in isolation with no git/network calls (`tests/release/test-version-calc.sh`) — this is the one place in this feature with real, easy-to-get-subtly-wrong logic (bump precedence, pre-1.0 breaking-change handling, the bootstrap/never-regress rule), so it gets real regression tests, not just transcription-verification. A driver script (`.github/scripts/release.sh`) does the git/gh plumbing: find last tag, classify commits, call the library, bump files, commit/tag/push, build and publish release notes. A thin workflow (`.github/workflows/release.yml`) wires `workflow_dispatch` (with a `dry_run` input) to the driver script.

**Tech Stack:** bash, jq, git, gh — no new runtime dependency, consistent with `tests/gate-routing/`.

## Global Constraints

- Version files touched: `.claude-plugin/plugin.json` (`.version`), `.claude-plugin/marketplace.json` (`.plugins[0].version`).
- Bump precedence: any Breaking commit → major (if current major ≥ 1) or minor (if current major is 0); else any `feat` → minor; else any `fix`/`perf` → patch; else (only `docs`/`chore`/`test`/`ci`/`refactor`/`revert`/`style`/etc., or literally zero commits) → patch fallback. Never a silent no-op.
- Breaking-change detection: header has `!` before the colon (e.g. `feat!:`, `fix(scope)!:`) OR the message body contains a line starting `BREAKING CHANGE:`.
- Bootstrap / never-regress rule: compute a candidate version from the git-tag-derived baseline AND a candidate from `plugin.json`'s currently declared version (both using the same commit classification), then take whichever candidate is larger. This guarantees the release always moves forward even on the first-ever run (no tag yet) or if the declared version and tags have drifted.
- Tag format: `vX.Y.Z`.
- `dry_run: true` (workflow input, default `false`) must compute and print the version and release notes but make no commit, no tag, no push, no GitHub Release, and must not require `RELEASE_PAT` to be set.
- A real (non-dry-run) release requires a repository secret `RELEASE_PAT` — a Personal Access Token from the repo admin's own account, used only for the final `git push` so it carries the same branch-protection bypass as the manual `--admin` PR merges already documented in `CLAUDE.md`. `release.sh` must fail with a clear, actionable error message (not a cryptic git-auth failure) if a non-dry-run invocation is attempted without it set.
- `actions/checkout` pinned to a full commit SHA, not a floating tag: `3d3c42e5aac5ba805825da76410c181273ba90b1` (verified via `gh api repos/actions/checkout/tags`, corresponds to release `v7.0.1`).
- This repo is squash-merge-only, so every commit on `main` since the last tag is exactly one PR, and its subject line is that PR's Conventional-Commit-formatted title (with GitHub's auto-appended ` (#N)` suffix, which is fine to keep as-is in release notes — GitHub auto-linkifies bare `#N` within the same repo).
- No `CHANGELOG.md` file — GitHub Releases are the only persisted record.
- No change to branch-protection configuration.

## File Structure

```
.github/
  scripts/
    lib/
      version-calc.sh   — pure functions: classify_commit_message, parse_version,
                           compute_next_version, version_gt. No git/gh/network calls.
    release.sh            — driver: git plumbing, calls the lib, bumps version files,
                           commits/tags/pushes, builds + publishes release notes.
  workflows/
    release.yml            — workflow_dispatch trigger, dry_run input, calls release.sh.
tests/
  release/
    test-version-calc.sh   — unit tests for lib/version-calc.sh (fast, deterministic,
                           runnable locally, no external services).
    README.md               — how to run the unit tests.
CLAUDE.md                    — gains a "Cutting a Release" subsection (RELEASE_PAT setup,
                           how to trigger).
```

---

### Task 1: Version-calculation library + unit tests

**Files:**
- Create: `tests/release/test-version-calc.sh`
- Create: `.github/scripts/lib/version-calc.sh`

**Interfaces:**
- Produces (consumed by Task 2's `release.sh`): `classify_commit_message(message) -> "breaking"|"feat"|"fix"|"other"`, `parse_version(version_string) -> "MAJOR MINOR PATCH"`, `compute_next_version(current_version, has_breaking, has_feat, has_fix) -> "MAJOR.MINOR.PATCH"`, `version_gt(a, b) -> exit 0 if a>b else 1`

- [ ] **Step 1: Write the failing tests — `tests/release/test-version-calc.sh`**

```bash
#!/usr/bin/env bash
# Unit tests for .github/scripts/lib/version-calc.sh
# Pure bash logic, no network/git/gh calls -- fast and deterministic.
# Usage: tests/release/test-version-calc.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../.github/scripts/lib/version-calc.sh
source "$REPO_ROOT/.github/scripts/lib/version-calc.sh"

PASS=0
FAIL=0

assert_eq() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $description"
        echo "  expected: $expected"
        echo "  actual:   $actual"
    fi
}

assert_true() {
    local description="$1"
    if [ "$2" = "0" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $description (expected success/exit 0)"
    fi
}

assert_false() {
    local description="$1"
    if [ "$2" != "0" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $description (expected failure/nonzero exit)"
    fi
}

# --- classify_commit_message ---

assert_eq "feat header -> feat" "feat" "$(classify_commit_message 'feat: add thing')"
assert_eq "feat with scope -> feat" "feat" "$(classify_commit_message 'feat(architecture-gate): add thing')"
assert_eq "fix header -> fix" "fix" "$(classify_commit_message 'fix: correct thing')"
assert_eq "perf header -> fix" "fix" "$(classify_commit_message 'perf: speed up thing')"
assert_eq "docs header -> other" "other" "$(classify_commit_message 'docs: update readme')"
assert_eq "chore header -> other" "other" "$(classify_commit_message 'chore(meta): bump deps')"
assert_eq "feat with ! -> breaking" "breaking" "$(classify_commit_message 'feat!: remove old API')"
assert_eq "fix with scope and ! -> breaking" "breaking" "$(classify_commit_message 'fix(scope)!: remove old API')"
assert_eq "BREAKING CHANGE footer -> breaking" "breaking" "$(classify_commit_message 'feat: add thing

BREAKING CHANGE: removes the old thing entirely')"
assert_eq "feat header, unrelated body text -> feat (no false breaking match)" "feat" "$(classify_commit_message 'feat: add thing

This is a normal body paragraph that happens to mention breaking things
informally but is not a real footer.')"

# --- parse_version ---

assert_eq "parse with v prefix" "1 2 3" "$(parse_version 'v1.2.3')"
assert_eq "parse without v prefix" "1 2 3" "$(parse_version '1.2.3')"

# --- compute_next_version ---

assert_eq "patch bump" "1.2.4" "$(compute_next_version "1.2.3" 0 0 1)"
assert_eq "minor bump" "1.3.0" "$(compute_next_version "1.2.3" 0 1 0)"
assert_eq "major bump (post-1.0)" "2.0.0" "$(compute_next_version "1.2.3" 1 0 0)"
assert_eq "breaking pre-1.0 -> minor bump, not major" "0.2.0" "$(compute_next_version "0.1.0" 1 0 0)"
assert_eq "breaking + feat present -> breaking wins" "2.0.0" "$(compute_next_version "1.2.3" 1 1 0)"
assert_eq "feat + fix present -> feat wins" "1.3.0" "$(compute_next_version "1.2.3" 0 1 1)"
assert_eq "only other commits -> patch fallback" "1.2.4" "$(compute_next_version "1.2.3" 0 0 0)"
assert_eq "resets minor/patch on major bump" "2.0.0" "$(compute_next_version "1.9.9" 1 0 0)"
assert_eq "resets patch on minor bump" "1.3.0" "$(compute_next_version "1.2.9" 0 1 0)"

# --- version_gt ---

version_gt "1.2.3" "1.2.2"; assert_true "1.2.3 > 1.2.2" "$?"
version_gt "1.3.0" "1.2.9"; assert_true "1.3.0 > 1.2.9" "$?"
version_gt "2.0.0" "1.9.9"; assert_true "2.0.0 > 1.9.9" "$?"
version_gt "1.2.3" "1.2.3"; assert_false "1.2.3 not > 1.2.3 (equal)" "$?"
version_gt "1.2.2" "1.2.3"; assert_false "1.2.2 not > 1.2.3" "$?"

echo ""
echo "Passed: $PASS, Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
```

- [ ] **Step 2: Run the tests, verify they fail**

```bash
chmod +x tests/release/test-version-calc.sh
tests/release/test-version-calc.sh
```

Expected: FAIL — `source: .../version-calc.sh: No such file or directory` (the library doesn't exist yet).

- [ ] **Step 3: Write the minimal implementation — `.github/scripts/lib/version-calc.sh`**

```bash
#!/usr/bin/env bash
# Pure functions for computing the next release version from Conventional
# Commit messages. No git/gh calls -- sourced and unit-tested in isolation
# by tests/release/test-version-calc.sh.

set -euo pipefail

# Classify a single commit's full message (header + body) into one of:
# breaking, feat, fix, other. Reads the message from argument $1.
classify_commit_message() {
    local message="$1"
    local header
    header="$(printf '%s\n' "$message" | head -1)"

    if printf '%s\n' "$header" | grep -qE '^[a-z]+(\([a-zA-Z0-9_.-]+\))?!:'; then
        echo "breaking"
        return
    fi
    if printf '%s\n' "$message" | grep -qE '^BREAKING CHANGE:'; then
        echo "breaking"
        return
    fi
    if printf '%s\n' "$header" | grep -qE '^feat(\([a-zA-Z0-9_.-]+\))?:'; then
        echo "feat"
        return
    fi
    if printf '%s\n' "$header" | grep -qE '^(fix|perf)(\([a-zA-Z0-9_.-]+\))?:'; then
        echo "fix"
        return
    fi
    echo "other"
}

# Parse "vX.Y.Z" or "X.Y.Z" into three space-separated integers: "X Y Z"
parse_version() {
    local v="$1"
    v="${v#v}"
    if ! printf '%s' "$v" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "ERROR: invalid version string: $1" >&2
        exit 1
    fi
    printf '%s' "$v" | tr '.' ' '
}

# Compute the next version given the current version and which commit
# categories were present since the last release.
# Usage: compute_next_version <current_version> <has_breaking:0|1> <has_feat:0|1> <has_fix:0|1>
compute_next_version() {
    local current="$1"
    local has_breaking="$2"
    local has_feat="$3"
    local has_fix="$4"

    local major minor patch
    read -r major minor patch <<< "$(parse_version "$current")"

    if [ "$has_breaking" = "1" ]; then
        if [ "$major" -ge 1 ]; then
            major=$((major + 1)); minor=0; patch=0
        else
            minor=$((minor + 1)); patch=0
        fi
    elif [ "$has_feat" = "1" ]; then
        minor=$((minor + 1)); patch=0
    else
        # has_fix=1, or the "other-only"/fallback case -- both are a patch bump
        patch=$((patch + 1))
    fi

    echo "${major}.${minor}.${patch}"
}

# Return 0 (true) if version $1 is strictly greater than version $2.
version_gt() {
    local a_major a_minor a_patch b_major b_minor b_patch
    read -r a_major a_minor a_patch <<< "$(parse_version "$1")"
    read -r b_major b_minor b_patch <<< "$(parse_version "$2")"

    if [ "$a_major" -gt "$b_major" ]; then return 0; fi
    if [ "$a_major" -lt "$b_major" ]; then return 1; fi
    if [ "$a_minor" -gt "$b_minor" ]; then return 0; fi
    if [ "$a_minor" -lt "$b_minor" ]; then return 1; fi
    [ "$a_patch" -gt "$b_patch" ]
}
```

- [ ] **Step 4: Run the tests again, verify they pass**

```bash
chmod +x .github/scripts/lib/version-calc.sh
tests/release/test-version-calc.sh
```

Expected: `Passed: <N>, Failed: 0`, exit code 0. Every `assert_eq`/`assert_true`/`assert_false` line above must show as passed — if any FAIL lines print, fix `version-calc.sh` (not the test) and re-run until clean.

- [ ] **Step 5: Commit**

```bash
git add tests/release/test-version-calc.sh .github/scripts/lib/version-calc.sh
git commit -m "test(ci): add version-calculation library with unit tests"
```

---

### Task 2: Release driver script

**Files:**
- Create: `.github/scripts/release.sh`

**Interfaces:**
- Consumes: `classify_commit_message`, `compute_next_version`, `version_gt` from Task 1's `.github/scripts/lib/version-calc.sh`
- Produces: exit 0 with "Next version: X.Y.Z" and a release-notes block printed to stdout in both dry-run and real mode; in real mode additionally commits, tags, pushes, and creates a GitHub Release. Consumed by Task 3's `release.yml`.

- [ ] **Step 1: Write `.github/scripts/release.sh`**

```bash
#!/usr/bin/env bash
# Compute the next release version from Conventional Commits history,
# bump version files, tag main, and publish a GitHub Release.
#
# Usage: release.sh [--dry-run]
# Expects to run from the repo root with full git history (fetch-depth 0)
# and `gh` authenticated. For a real (non-dry-run) release, RELEASE_PAT
# must be set in the environment (used to push past main's branch
# protection) -- see docs/superpowers/specs/2026-08-11-automated-release-versioning-design.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib/version-calc.sh
source "$SCRIPT_DIR/lib/version-calc.sh"

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
fi

cd "$REPO_ROOT"

PLUGIN_JSON=".claude-plugin/plugin.json"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"

DECLARED_VERSION="$(jq -r '.version' "$PLUGIN_JSON")"

LAST_TAG="$(git tag --list 'v*' --sort=-v:refname | head -1)"
if [ -n "$LAST_TAG" ]; then
    COMMIT_RANGE="${LAST_TAG}..HEAD"
    TAG_BASELINE_VERSION="${LAST_TAG#v}"
else
    COMMIT_RANGE="HEAD"
    TAG_BASELINE_VERSION="0.0.0"
fi

echo "Last tag: ${LAST_TAG:-<none>}"
echo "Declared version (plugin.json): $DECLARED_VERSION"

COMMIT_HASHES="$(git log $COMMIT_RANGE --pretty=format:%H)"

HAS_BREAKING=0
HAS_FEAT=0
HAS_FIX=0
COMMIT_COUNT=0

FEATURES=()
FIXES=()
OTHERS=()

if [ -n "$COMMIT_HASHES" ]; then
    while IFS= read -r hash; do
        [ -z "$hash" ] && continue
        COMMIT_COUNT=$((COMMIT_COUNT + 1))
        MESSAGE="$(git log -1 --pretty=%B "$hash")"
        SUBJECT="$(git log -1 --pretty=%s "$hash")"
        CATEGORY="$(classify_commit_message "$MESSAGE")"
        case "$CATEGORY" in
            breaking)
                HAS_BREAKING=1
                FEATURES+=("$SUBJECT")
                ;;
            feat)
                HAS_FEAT=1
                FEATURES+=("$SUBJECT")
                ;;
            fix)
                HAS_FIX=1
                FIXES+=("$SUBJECT")
                ;;
            *)
                OTHERS+=("$SUBJECT")
                ;;
        esac
    done <<< "$COMMIT_HASHES"
fi

echo "Commits since last tag: $COMMIT_COUNT"
echo "has_breaking=$HAS_BREAKING has_feat=$HAS_FEAT has_fix=$HAS_FIX"

CANDIDATE_FROM_TAG="$(compute_next_version "$TAG_BASELINE_VERSION" "$HAS_BREAKING" "$HAS_FEAT" "$HAS_FIX")"
CANDIDATE_FROM_DECLARED="$(compute_next_version "$DECLARED_VERSION" "$HAS_BREAKING" "$HAS_FEAT" "$HAS_FIX")"

if version_gt "$CANDIDATE_FROM_DECLARED" "$CANDIDATE_FROM_TAG"; then
    NEXT_VERSION="$CANDIDATE_FROM_DECLARED"
else
    NEXT_VERSION="$CANDIDATE_FROM_TAG"
fi

echo ""
echo "Next version: $NEXT_VERSION"

# --- Build release notes ---

NOTES_FILE="$(mktemp)"
{
    if [ "${#FEATURES[@]}" -gt 0 ]; then
        echo "## Features"
        for line in "${FEATURES[@]}"; do echo "- $line"; done
        echo ""
    fi
    if [ "${#FIXES[@]}" -gt 0 ]; then
        echo "## Fixes"
        for line in "${FIXES[@]}"; do echo "- $line"; done
        echo ""
    fi
    if [ "${#OTHERS[@]}" -gt 0 ]; then
        echo "## Other Changes"
        for line in "${OTHERS[@]}"; do echo "- $line"; done
        echo ""
    fi
} > "$NOTES_FILE"

echo "--- Release notes ---"
cat "$NOTES_FILE"
echo "---------------------"

if [ "$DRY_RUN" = "1" ]; then
    echo ""
    echo "DRY RUN: stopping before commit/tag/push/release."
    rm -f "$NOTES_FILE"
    exit 0
fi

if [ -z "${RELEASE_PAT:-}" ]; then
    echo "ERROR: RELEASE_PAT is not set. A real release needs a repository secret" >&2
    echo "named RELEASE_PAT (a Personal Access Token from an admin account) so this" >&2
    echo "workflow can push past main's branch protection. See" >&2
    echo "docs/superpowers/specs/2026-08-11-automated-release-versioning-design.md" >&2
    echo "for setup instructions. Re-run with --dry-run to test without it." >&2
    rm -f "$NOTES_FILE"
    exit 1
fi

jq --arg v "$NEXT_VERSION" '.version = $v' "$PLUGIN_JSON" > "${PLUGIN_JSON}.tmp" && mv "${PLUGIN_JSON}.tmp" "$PLUGIN_JSON"
jq --arg v "$NEXT_VERSION" '.plugins[0].version = $v' "$MARKETPLACE_JSON" > "${MARKETPLACE_JSON}.tmp" && mv "${MARKETPLACE_JSON}.tmp" "$MARKETPLACE_JSON"

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add "$PLUGIN_JSON" "$MARKETPLACE_JSON"
git commit -m "chore(release): v${NEXT_VERSION}"
git tag "v${NEXT_VERSION}"

git remote set-url origin "https://x-access-token:${RELEASE_PAT}@github.com/chrschy/factory-gates.git"
git push origin main --follow-tags

gh release create "v${NEXT_VERSION}" --title "v${NEXT_VERSION}" --notes-file "$NOTES_FILE"

rm -f "$NOTES_FILE"

echo ""
echo "Released v${NEXT_VERSION}"
```

- [ ] **Step 2: Verify syntax**

```bash
chmod +x .github/scripts/release.sh
bash -n .github/scripts/release.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Integration test of the bootstrap/never-regress rule in a disposable temp repo**

This is the one piece of `release.sh`'s own logic (beyond what Task 1 already unit-tests) that's easy to get wrong and worth verifying directly: does it correctly bump forward from the *declared* version, not just re-print it, when there's no tag yet?

```bash
TMPDIR="$(mktemp -d)"
git -C "$TMPDIR" init -q -b main
mkdir -p "$TMPDIR/.claude-plugin"
cat > "$TMPDIR/.claude-plugin/plugin.json" <<'EOF'
{"version": "0.1.0"}
EOF
cat > "$TMPDIR/.claude-plugin/marketplace.json" <<'EOF'
{"plugins": [{"version": "0.1.0"}]}
EOF
git -C "$TMPDIR" add -A
git -C "$TMPDIR" -c user.name=test -c user.email=test@test.com commit -q -m "feat: initial bootstrap commit"

REPO_ROOT="$(git rev-parse --show-toplevel)"
(cd "$TMPDIR" && bash "$REPO_ROOT/.github/scripts/release.sh" --dry-run)

rm -rf "$TMPDIR"
```

Expected: output includes `Last tag: <none>`, `Declared version (plugin.json): 0.1.0`, and — critically — `Next version: 0.2.0` (bumped forward from the declared 0.1.0 via the `feat` commit found, NOT `0.1.0` unchanged and NOT `0.0.1` computed from an unseen `0.0.0` baseline). If it prints anything other than `0.2.0`, the bootstrap logic has a bug — fix `release.sh` before proceeding.

- [ ] **Step 4: Dry-run smoke test against this actual repo**

```bash
.github/scripts/release.sh --dry-run
```

Expected: runs to completion without error, prints a `Last tag:`, `Declared version:`, a `Next version:`, and a release-notes block. This repo has no tags yet, so this exercises the same "no tag" branch as Step 3's synthetic test, but against real history — read the output and confirm it looks sane (matches what you'd expect given the commits merged so far), no need to assert an exact number since real repo history will keep changing.

- [ ] **Step 5: Commit**

```bash
git add .github/scripts/release.sh
git commit -m "feat(ci): add release driver script"
```

---

### Task 3: Release workflow

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `.github/scripts/release.sh` from Task 2 (invoked as a subprocess)

- [ ] **Step 1: Write `.github/workflows/release.yml`**

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      dry_run:
        description: "Compute version and notes without creating a commit, tag, or release"
        type: boolean
        default: false

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0

      - name: Run release script (dry run)
        if: ${{ inputs.dry_run }}
        run: .github/scripts/release.sh --dry-run

      - name: Run release script
        if: ${{ !inputs.dry_run }}
        env:
          RELEASE_PAT: ${{ secrets.RELEASE_PAT }}
          GH_TOKEN: ${{ secrets.RELEASE_PAT }}
        run: .github/scripts/release.sh
```

Note: `GH_TOKEN` is set for the real-run step because `gh release create` (invoked inside `release.sh`) needs `gh` to be authenticated — reusing `RELEASE_PAT` for this is fine since it already needs `repo` scope for the push.

- [ ] **Step 2: Verify YAML is well-formed**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "valid YAML"
```

Expected: `valid YAML`, no traceback.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat(ci): add release workflow"
```

---

### Task 4: Documentation + real dry-run verification on GitHub Actions

**Files:**
- Create: `tests/release/README.md`
- Modify: `CLAUDE.md` (append a "Cutting a Release" subsection under "Git & Branching (trunk-based)")

**Interfaces:** none (documentation + a live verification step, nothing later depends on this task's files)

- [ ] **Step 1: Write `tests/release/README.md`**

```markdown
# Release Version-Calculation Tests

Unit tests for `.github/scripts/lib/version-calc.sh` — the pure-function
core of the release automation (bump precedence, breaking-change
detection, SemVer arithmetic). Fast and deterministic: no git, network, or
`gh` calls, safe to run anytime.

## Running

```bash
./test-version-calc.sh
```

Expected output ends with `Passed: <N>, Failed: 0` and exit code 0. Any
`FAIL:` lines point at the specific assertion that broke, with expected
vs. actual values.

## Scope

This suite only covers the pure calculation logic. The git/gh plumbing in
`.github/scripts/release.sh` (finding the last tag, classifying real
commits, bumping the version files, committing/tagging/pushing, creating
the GitHub Release) is exercised via `release.sh --dry-run` directly
against a real or disposable repo instead — see that script's own
integration-style verification in
`docs/superpowers/plans/2026-08-11-automated-release-versioning.md` (Task 2).
```

- [ ] **Step 2: Append a "Cutting a Release" subsection to `CLAUDE.md`**

Find the `## Git & Branching (trunk-based)` section (ends right before `## Testing`) and insert this new subsection immediately after the existing "Repo merge settings: squash-merge only..." paragraph, before `## Testing`:

```markdown

### Cutting a release

Releases are automated but manually triggered — nothing ships without you
asking for it:

1. **One-time setup:** create a Personal Access Token from your own
   (admin) GitHub account with `repo` scope (classic) or `contents: write`
   (fine-grained), then add it as a repository secret named `RELEASE_PAT`
   (Settings → Secrets and variables → Actions → New repository secret).
   This is what lets the release workflow push past `main`'s branch
   protection — the same admin-bypass mechanism documented above, just
   invoked by a script instead of by hand. Without this secret, the
   workflow still works in dry-run mode; it only fails (with a clear
   error, not a cryptic git-auth failure) if you try a real release
   without it.
2. **Trigger a release:** from the Actions tab, run the "Release" workflow
   (or `gh workflow run release.yml`). Leave `dry_run` unchecked for a
   real release, or check it to preview the computed version and release
   notes without changing anything.
3. The workflow computes the next version from Conventional Commits since
   the last tag (see `docs/superpowers/specs/2026-08-11-automated-release-versioning-design.md`
   for the exact bump rules), bumps `plugin.json`/`marketplace.json`,
   commits, tags `vX.Y.Z`, and publishes a GitHub Release with generated
   notes.
```

- [ ] **Step 3: Verify the CLAUDE.md edit landed in the right place**

```bash
grep -n "Cutting a release\|^## Testing" CLAUDE.md
```

Expected: the "### Cutting a release" line appears before the "## Testing" line.

- [ ] **Step 4: Commit**

```bash
git add tests/release/README.md CLAUDE.md
git commit -m "docs(ci): document release process and version-calc test suite"
```

- [ ] **Step 5: Push the branch and dispatch a real dry-run on GitHub Actions**

This is real end-to-end verification of the YAML/Actions wiring (secrets context, checkout, input handling) that no local test can substitute for — GitHub lets you dispatch a workflow against a non-default branch by specifying `--ref` explicitly, so this can run before the branch is merged.

```bash
git push -u origin feature/automated-release-versioning
gh workflow run release.yml --ref feature/automated-release-versioning -f dry_run=true
```

- [ ] **Step 6: Watch the run and verify its output**

```bash
sleep 15
RUN_ID=$(gh run list --workflow=release.yml --branch=feature/automated-release-versioning --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN_ID" --exit-status
gh run view "$RUN_ID" --log | grep -E "Next version:|DRY RUN:|Last tag:"
```

Expected: the run succeeds (exit status 0), and the log shows `Last tag:`, a `Next version:` line, and `DRY RUN: stopping before commit/tag/push/release.` — confirming the real workflow, not just the local script, computes and stops correctly. If the run fails, read `gh run view "$RUN_ID" --log` for the actual error and fix before proceeding — do not mark this task complete on a failed run.

---

### Task 5: Open PR, review, merge

**Files:** none

**Interfaces:**
- Consumes: all commits from Tasks 1-4 on `feature/automated-release-versioning`; Task 4's real Actions dry-run output for the PR body

- [ ] **Step 1: Open the PR**

Fill in the `<PASTE ...>` placeholder with Task 4 Step 6's actual log output before running this command.

```bash
gh pr create --title "feat(ci): add automated release versioning" --body "$(cat <<'EOF'
## Who is submitting this PR? (required)

| Field | Value |
|-------|-------|
| Your model + version | Claude Sonnet 5 |
| Harness + version | Claude Code |
| All plugins installed | superpowers |
| Human partner who reviewed this diff | [@chrschy](https://github.com/chrschy) |

## What problem are you trying to solve?

Releases were entirely manual: no automated SemVer computation from
commit history, plugin.json/marketplace.json version fields could drift
from whatever tag (if any) existed, and there was no repeatable way to
generate release notes.

## What does this PR change?

Adds a workflow_dispatch-triggered GitHub Actions workflow that computes
the next version from Conventional Commits since the last tag, bumps
plugin.json/marketplace.json, tags main, and publishes a GitHub Release
with generated notes. Includes a dry_run input, and a unit-tested
pure-function library for the version-bump logic itself.

## Which gate does this touch?

None -- repo tooling / CI only.

## What alternatives did you consider?

Considered release-please-action, but its natural idiom is a perpetual
"Release PR" that accumulates until merged, which fights the
single-manual-trigger behavior that was explicitly wanted here. Went with
a small custom bash+jq script instead, consistent with the
tests/gate-routing/ precedent and this repo's no-new-dependency pattern.

## Existing PRs
- [x] I have reviewed open AND closed PRs/issues for duplicates or prior art
- Related PRs/issues: none found

## Rigor
- [x] This change was tested adversarially, not just on the happy path
- [x] Unit tests: tests/release/test-version-calc.sh, all passing
- [x] Integration test of the bootstrap/never-regress rule against a disposable temp repo
- [x] Real dry-run dispatched on GitHub Actions against this branch -- log output:

<PASTE Task 4 Step 6's log output here>

## Human review
- [ ] A human has reviewed the COMPLETE proposed diff before submission
EOF
)"
```

- [ ] **Step 2: Human review gate**

Stop here. Show the human partner the complete diff (`git diff main...feature/automated-release-versioning`) and the PR URL. Remind them that a real (non-dry-run) release additionally needs the one-time `RELEASE_PAT` repository secret (documented in CLAUDE.md's new "Cutting a release" section) before it can be used for real — this does not block merging this PR, only cutting an actual release afterward. Do not proceed to Step 3 until they explicitly approve.

- [ ] **Step 3: Merge**

```bash
gh pr merge --squash --delete-branch --admin
```

- [ ] **Step 4: Verify**

```bash
git checkout main
git pull
ls .github/workflows/release.yml .github/scripts/release.sh .github/scripts/lib/version-calc.sh tests/release/
```

Expected: all files present on `main`.

## Self-Review

1. **Spec coverage:** version-calculation library + unit tests (Task 1), driver script with the corrected bootstrap/never-regress logic and its own integration-style verification (Task 2), workflow wiring with `dry_run` input and pinned `actions/checkout` (Task 3), documentation (README for the test suite, CLAUDE.md's "Cutting a release" section) plus real on-GitHub dry-run verification (Task 4), PR/merge flow with the `RELEASE_PAT` reminder (Task 5). Every rule from the spec's Version calculation, Version file sync, Landing the commit on main, Release notes, and Workflow implementation sections has a corresponding task.
2. **Placeholder scan:** one intentional, explicitly-flagged placeholder in Task 5 Step 1 (`<PASTE Task 4 Step 6's log output here>`), same pattern as the two prior plans in this repo — must be filled from real output before opening the PR, not left literal.
3. **Type consistency:** `version-calc.sh`'s four function names and signatures (`classify_commit_message`, `parse_version`, `compute_next_version`, `version_gt`) are identical across Task 1's test file, Task 1's implementation, and Task 2's `release.sh` consumption of them — no drift.
