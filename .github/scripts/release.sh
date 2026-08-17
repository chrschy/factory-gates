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
    echo "workflow can open and admin-merge the release PR. See" >&2
    echo "docs/superpowers/specs/2026-08-16-release-pr-flow-fix-design.md" >&2
    echo "for setup instructions. Re-run with --dry-run to test without it." >&2
    rm -f "$NOTES_FILE"
    exit 1
fi

jq --arg v "$NEXT_VERSION" '.version = $v' "$PLUGIN_JSON" > "${PLUGIN_JSON}.tmp" && mv "${PLUGIN_JSON}.tmp" "$PLUGIN_JSON"
jq --arg v "$NEXT_VERSION" '.plugins[0].version = $v' "$MARKETPLACE_JSON" > "${MARKETPLACE_JSON}.tmp" && mv "${MARKETPLACE_JSON}.tmp" "$MARKETPLACE_JSON"

RELEASE_BRANCH="release/v${NEXT_VERSION}"

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git checkout -b "$RELEASE_BRANCH"
git add "$PLUGIN_JSON" "$MARKETPLACE_JSON"
git commit -m "chore(release): v${NEXT_VERSION}"

git remote set-url origin "https://x-access-token:${RELEASE_PAT}@github.com/chrschy/factory-gates.git"
git push origin "$RELEASE_BRANCH"

export GH_TOKEN="$RELEASE_PAT"

PR_URL="$(gh pr create --title "chore(release): v${NEXT_VERSION}" --base main --head "$RELEASE_BRANCH" --body "Automated release PR for v${NEXT_VERSION}. See the workflow run for the full computed release notes.")"
echo "Release PR: $PR_URL"

echo "Waiting for required checks on the release PR..."
CHECKS_OK=0
for attempt in 1 2 3 4 5 6; do
    if CHECKS_OUTPUT="$(gh pr checks "$RELEASE_BRANCH" --watch --fail-fast 2>&1)"; then
        echo "$CHECKS_OUTPUT"
        CHECKS_OK=1
        break
    fi
    echo "$CHECKS_OUTPUT"
    if printf '%s' "$CHECKS_OUTPUT" | grep -q "no checks reported"; then
        echo "Checks not registered yet (attempt $attempt/6) -- retrying in 5s..."
        sleep 5
        continue
    fi
    break
done

if [ "$CHECKS_OK" != "1" ]; then
    echo "" >&2
    echo "ERROR: required checks failed (or never appeared) on the release PR ($PR_URL)." >&2
    echo "Not merging, not tagging, not releasing. Fix the failure, then either" >&2
    echo "push a fix to $RELEASE_BRANCH or close the PR and re-run this workflow." >&2
    rm -f "$NOTES_FILE"
    exit 1
fi

gh pr merge "$RELEASE_BRANCH" --squash --admin

git fetch origin main
git checkout main
git reset --hard origin/main

git tag "v${NEXT_VERSION}"
git push origin "v${NEXT_VERSION}"

gh release create "v${NEXT_VERSION}" --title "v${NEXT_VERSION}" --notes-file "$NOTES_FILE"

rm -f "$NOTES_FILE"

echo ""
echo "Released v${NEXT_VERSION}"
