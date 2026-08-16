# factory-gates — Backlog

Living backlog for factory-gates development. Updated as items complete
or new ones surface — not a dated spec/plan, just current project state.
If you're picking this up in a fresh session with no prior conversation
context, read this file plus `README.md` and `CLAUDE.md` first.

## Next up (toward v1.0.0)

`plugin.json` is currently at `0.2.0` (first real release, cut
2026-08-16). The release automation is a pure SemVer bump from whatever
version is declared — it has no built-in concept of "graduate to 1.0.0."
Getting there is two separate steps: do the work that justifies calling
it 1.0, then deliberately bump the declared version to `1.0.0` in a small
prep PR before triggering the next release.

Three items make up that bar, in this order:

1. **Write `CONTRIBUTING.md`.** Referenced from `CLAUDE.md`'s "See Also"
   section but doesn't exist yet. A plugin at 1.0 claiming to be usable
   by outside contributors should have this.
2. **Confirm the release automation actually works end-to-end.**
   `.github/scripts/release.sh` was rewritten in PR #20 to land release
   commits through a PR (open branch → wait for `fast-tests` → admin-merge
   → tag the merge commit) instead of a direct push, because adding
   `fast-tests` as a required status check (PR #16/#17) broke the old
   direct-push approach — a required check can never be satisfied by a
   raw push, since the check needs the commit to exist first. That fix
   has never been exercised by an actual triggered release yet (v0.2.0
   itself was cut manually through a normal PR as a one-time workaround,
   before the fix existed). Trigger a real release once there are new
   commits to release from (item 1 and item 3 below will provide them)
   and confirm the PR opens, the check is genuinely waited on and
   passes, and the tag/release land on the correct merge commit.
3. **Real dogfooding.** See "Dogfooding" section below — this is the one
   that most needs a genuinely fresh session, not a context-primed one.

Once all three land: bump `plugin.json`'s declared version to `1.0.0`
directly (matching how v0.2.0 was force-set), then trigger the release
workflow for real.

## Dogfooding

factory-gates has been tested extensively (`tests/gate-routing/`,
`tests/gate-quality/`) but never actually *used* on a real feature by a
human directing it end-to-end. This is overdue and is the most
meaningful remaining validation before calling this 1.0.

**Do this in a genuinely fresh session, not one carrying prior
factory-gates development context.** The whole point is observing how
`/factory-gates` (or plain `brainstorming` routing) behaves for a normal
first-time user, not a context-primed one that already knows every
routing nuance. Pick a real, non-toy feature — something you actually
want built, not a fabricated example like the test suites' URL
shortener — and drive it through the full pipeline: `brainstorming` →
`architecture-gate` → `program-design-gate` → `writing-plans` →
`vertical-slices-gate` → execution. Note anything that feels off,
confusing, or actually valuable along the way — that's the real signal
this whole effort has been trying to measure.

## Also remaining (lower priority, not blocking 1.0)

- **Superpowers-vs-factory-gates outcome benchmark** — unblocked now
  that all three `tests/gate-quality/*/` suites exist (architecture-gate,
  program-design-gate, vertical-slices-gate). Needs its own design: what
  "outcome" means to compare, what counts as a fair baseline run without
  factory-gates.
- **Maintainability gate (Gate 5)** — static analysis (complexity,
  duplication, coupling, coverage) before/after `writing-plans`. Not yet
  spec'd; originally a "note for later" idea, not yet brainstormed.
- **Expand the bare-scenario gate-routing sample size.** PR #13's live
  verification was quota-limited to 3 trials (documented directly in the
  README's determinism table as a known small sample). Cheap to expand
  once there's API quota to spend on it.

## How work happens here

Full process is in `CLAUDE.md` — read it before starting anything. Key
points that matter most in practice:
- Every change: brainstorm → spec (`docs/superpowers/specs/`) → plan
  (`docs/superpowers/plans/`) → PR. Skill-wording changes to the three
  gate skills need before/after evidence from `tests/gate-routing/`.
- Trunk-based: `main` only, PRs from `<type>/<slug>` branches (`feature`,
  `fix`, `docs`, `test`, `chore` — not `ci`, despite Conventional Commits
  allowing it as a commit type), Conventional Commit messages, squash
  merge only.
- `main`'s branch protection requires 1 approving review (which a PR's
  own author can never satisfy) and the `fast-tests` status check. Admin
  bypass (`--admin` on `gh pr merge`) covers the missing review — but
  never use it to skip a genuinely failing check.
