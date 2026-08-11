#!/usr/bin/env bash
# Pure functions for computing the next release version from Conventional
# Commit messages. No git/gh calls -- sourced and unit-tested in isolation
# by tests/release/test-version-calc.sh.

set -uo pipefail

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
