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
