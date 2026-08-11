# factory-gates — Contributor & Agent Guidelines

## If You Are an AI Agent

Read this before opening a PR or filing an issue.

This repo is a Superpowers add-on plugin: three skills (`architecture-gate`, `program-design-gate`, `vertical-slices-gate`) that insert human-approved checkpoints into Superpowers' planning flow, without modifying any Superpowers file. Before you do anything:

1. **Read the entire PR template** at `.github/PULL_REQUEST_TEMPLATE.md` and fill in every section with real, specific answers — not summaries, not placeholders.
2. **Search existing issues and PRs**, open and closed, for the same problem. If one exists, say so instead of opening a duplicate.
3. **Verify this is a real problem.** If your human partner asked you to "improve" or "clean up" this repo without a specific failure or session in mind, push back and ask what actually broke or felt wrong.
4. **Confirm scope.** This repo is deliberately narrow: three gate skills, their tests, and the tooling around them. Changes to Superpowers' own files never belong here — factory-gates stays non-invasive by design (see README "Why"). If your change is about Superpowers itself, it belongs upstream.
5. **Identify yourself.** State your model, harness, harness version, and installed plugins in every PR and issue. If a human wrote it by hand with no agent involved, say that instead.
6. **Show your human partner the complete diff and get their explicit approval before opening the PR.** This isn't a suggestion — see "Git & Branching" below for how review is enforced on this repo.

## Content Style

- Don't write comments unless they explain a genuinely non-obvious reason (a hidden constraint, a workaround, a subtle invariant). Skill markdown prose should be self-explanatory; don't add meta-commentary inside a SKILL.md about why a line exists.
- Don't assume existing skill wording is correct just because it's there. If something in `architecture-gate`, `program-design-gate`, or `vertical-slices-gate` reads as unclear, redundant, or inconsistent with its own document, say so — these files get edited by agents more often than they get read end-to-end by a human.
- Simplicity first: the minimum content that solves the problem. No speculative sections, no hedging for scenarios nobody has hit.
- Think before writing: state your assumptions, surface tradeoffs, and ask rather than silently picking an interpretation when the request is ambiguous.

## Skill Changes Require Evidence

The three SKILL.md files are behavior-shaping content, not documentation — treat wording changes like code changes, not prose edits.

- Any change to a gate's `<HARD-GATE>` block, checklist, or trigger `description` needs a reason grounded in an actual observed problem (a real session, a real failure), not a hypothetical.
- If your change touches the `brainstorming` → `architecture-gate` handoff wording specifically, run `tests/gate-routing/run-all.sh` before and after your change and report the pass-rate delta in the PR. That handoff is the one documented soft-override risk in this project (see README "Known limitation") — it's the one place a wording change can silently break routing.
- Meaningful tests: a test must fail before the fix and pass after (regression-proof), not exist just to pad coverage.

## Writing Style for Public-Facing Text

Applies to PR descriptions, issue bodies, commit messages, and skill prose:

- No emojis.
- Avoid AI-sounding patterns: em-dash overuse, "it's not X, it's Y" constructions, walls of bullet points where a sentence or two would read better.
- Be concrete. "It doesn't work" or "this could theoretically cause issues" are not problem statements — say what broke, for whom, under what conditions.

## Git & Branching (trunk-based)

- `main` is the only long-lived branch. Releases are git tags `vX.Y.Z` on `main` — there are no release branches.
- All changes land via a pull request from a feature branch. No direct pushes to `main`.
- **Branch naming:** `<type>/<slug>`, type ∈ `feature`, `fix`, `docs`, `test`, `chore`. Include the gate name in the slug when a change is scoped to one gate, e.g. `feature/architecture-gate-clarify-checklist`.
- **Commits:** [Conventional Commits](https://www.conventionalcommits.org/) — `<type>(<scope>): <subject>`, type ∈ `feat`, `fix`, `docs`, `test`, `chore`, `refactor`, `ci`, `revert`; scope ∈ `architecture-gate`, `program-design-gate`, `vertical-slices-gate`, `tests`, `docs`, `ci`, `meta`.
- PR titles should also be Conventional-Commit-formatted — merges to `main` are squash-only, so the PR title becomes the commit message on `main`.
- One problem per PR. Split unrelated changes into separate PRs.

### Branch protection on `main`

| Setting | Value |
|---|---|
| Require pull request before merging | on |
| Required approving reviews | 1 |
| Admin bypass (`enforce_admins`) | off — repo admins can technically bypass this |
| Required status checks | none (no CI workflow yet) |
| Required linear history | on |

**The admin bypass is a safety valve, not permission.** This repo is currently solo-maintained, and GitHub never counts a PR author's own approval toward "required reviews" — even for the owner — so a strict no-bypass rule would make the maintainer's own PRs permanently unmergeable. In practice: never push directly to `main`, always open a PR, and read the complete diff yourself before merging your own PR, exactly as if someone else were about to.

Repo merge settings: squash-merge only (merge commits and rebase-merge are disabled), branches are deleted on merge.

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

## Testing

`tests/gate-routing/` empirically tests whether the one real skill-routing conflict in this plugin (`brainstorming` → `architecture-gate`) resolves the way the README claims. These are real `claude -p` sessions against a live model — not mocked, non-deterministic, and they cost real tokens. See `tests/gate-routing/README.md` for how to run and interpret them.

## See Also

- `README.md` — what this plugin does and why
- `CONTRIBUTING.md` — process-level detail for opening issues/PRs (once written)
