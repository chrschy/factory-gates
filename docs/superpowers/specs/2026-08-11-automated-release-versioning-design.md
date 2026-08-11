# factory-gates — Automated Release Versioning

**Status:** approved
**Date:** 2026-08-11

## Why

Releases are currently manual: no one computes the next SemVer number from history, `.claude-plugin/plugin.json`'s `version` field and `.claude-plugin/marketplace.json`'s `plugins[0].version` field can silently drift from whatever git tag (if any) exists, and there's no repeatable way to generate release notes. This spec adds a manually-triggered GitHub Actions workflow that computes the next version from Conventional Commits history since the last tag, bumps both version files, tags `main`, and publishes a GitHub Release with generated notes — one click, no separate release-PR to track.

## Trigger

`workflow_dispatch` only — no automatic trigger on push/merge. You start it from the Actions tab (or `gh workflow run release.yml`) whenever you want to cut a release. Input:

- `dry_run` (boolean, default `false`): when `true`, computes and prints the next version and release notes but makes no commit, no tag, no GitHub Release. Lets you sanity-check a release before committing to it — creating a tag/release is not something this workflow can silently undo.

## Version calculation

1. Find the latest tag matching `v*` (`git tag --list 'v*' --sort=-v:refname | head -1`). If none exists, treat the "last version" as the version currently in `plugin.json` (not `v0.0.0`) — see Bootstrap safety below.
2. Collect every commit on `main` since that tag: `git log <last-tag>..HEAD --pretty=format:%H`. Because this repo is squash-merge-only, this is exactly one commit per merged PR, and its subject line is that PR's Conventional-Commit-formatted title (GitHub also auto-appends ` (#N)` to the subject on squash merge — used as-is, no extra link-building needed since GitHub auto-linkifies bare `#N` in rendered release notes within the same repo).
3. For each commit, read the full message (`git log -1 --pretty=%B <hash>`) and classify it:
   - **Breaking**: header has `!` before the colon (e.g. `feat!:`, `fix(scope)!:`) OR the body contains a `BREAKING CHANGE:` footer.
   - **Feature**: header type is `feat`.
   - **Fix**: header type is `fix` or `perf`.
   - **Other**: everything else (`docs`, `chore`, `test`, `ci`, `refactor`, `revert`, `style`, ...).
4. Determine the bump from the highest-precedence category found among all commits since the last tag:
   - Any Breaking → **major** bump once current major version is ≥ 1, **minor** bump while major version is 0 (pre-1.0 SemVer convention — breaking changes don't jump you to 1.0.0 by accident).
   - Else any Feature → **minor** bump.
   - Else any Fix → **patch** bump.
   - Else (only Other commits, or somehow zero commits found but the workflow was still triggered) → **patch** bump anyway. Triggering the workflow is an explicit request for a release; it never silently no-ops.
5. **Bootstrap / never-regress safety:** compute the candidate next version from history as above, but also compare against `plugin.json`'s current declared version. If the computed version would be *less than or equal to* the declared version (e.g. first-ever run computes `0.0.1` from a patch-only bump against an implicit `0.0.0` baseline, but `plugin.json` already says `0.1.0`), use `plugin.json`'s version as the baseline instead and bump from *that*. The computed release version must never go backwards or sideways relative to what's already declared in the repo.

## Version file sync

Both files are updated to the new version in the same commit:
- `.claude-plugin/plugin.json` → top-level `version` field
- `.claude-plugin/marketplace.json` → `plugins[0].version` field

## Landing the commit on `main`

`main`'s branch protection requires a PR and blocks direct pushes — including for this workflow. Rather than opening (and needing to separately merge) a release PR every time, the workflow authenticates git operations with a **Personal Access Token stored as a repository secret** (`RELEASE_PAT`), generated from your own (chrschy) account. Since branch protection's `enforce_admins` is already `off` (documented in CLAUDE.md as the solo-maintainer safety valve), pushes authenticated as an actual admin account bypass the PR requirement — this is the exact same mechanism as the `--admin` merges used for PRs #1 and #2, just invoked by a script instead of by hand. No changes to branch protection settings are needed; this reuses the existing, already-documented exception rather than creating a new one.

Sequence: bump both JSON files → `git commit -m "chore(release): vX.Y.Z"` → `git tag vX.Y.Z` → `git push origin main --follow-tags`.

## Release notes

Built from the same classified commit list (Version calculation step 3), grouped into markdown sections, skipping empty sections:

```markdown
## Features
- <commit subject with type/scope prefix stripped>

## Fixes
- <commit subject with type/scope prefix stripped>

## Other Changes
- <commit subject with type/scope prefix stripped>
```

Published via `gh release create vX.Y.Z --title vX.Y.Z --notes-file <generated-file>`. No `CHANGELOG.md` file is maintained in-repo — the GitHub Release page is the permanent, linkable record of each release's notes.

## Workflow implementation

- `.github/workflows/release.yml`: `workflow_dispatch` trigger, single job, `permissions: contents: write` (belt-and-suspenders; the actual bypass comes from `RELEASE_PAT`, not the default `GITHUB_TOKEN`).
- `actions/checkout` pinned to a full commit SHA (not a floating version tag), `fetch-depth: 0` (full history + tags needed), `token: ${{ secrets.RELEASE_PAT }}` so subsequent `git push` carries admin bypass.
- All logic (version calculation, classification, file bumping, notes generation) lives in one script, `.github/scripts/release.sh`, invoked by the workflow — bash + `jq` + `git` + `gh` only, no new runtime dependency, consistent with `tests/gate-routing/`'s precedent and this repo's existing tooling choices.
- `dry_run: true` runs the same script up through printing the computed version and generated notes to the job log, then exits before the commit/tag/push/release steps.

## Out of scope

- No `CHANGELOG.md` file (GitHub Releases only, per decision above).
- No automatic/on-merge triggering — explicitly manual per your stated preference.
- No change to branch protection configuration — reuses the existing admin-bypass mechanism as-is.

## Self-review

- **Placeholders:** none — every rule has a concrete algorithm, not a TBD.
- **Internal consistency:** the "never regress" rule (step 5) is the one place two computations could disagree (history-derived vs. declared); resolved explicitly by always taking the higher of the two rather than leaving it ambiguous.
- **Scope:** single, focused deliverable — one workflow, one script, two files it's allowed to touch. Not bundled with the unrelated `plugin.json` homepage fix (that shipped separately as PR #3).
- **Ambiguity:** commit classification precedence (breaking > feat > fix/perf > other) is stated as an explicit ordered list, not left to interpretation.
