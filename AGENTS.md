<!-- AGENTS.md -->
# Agent guide for 5pm-ruby

This repository ships two paired gems from one source tree:

- `5pm` (core SDK, `lib/`, version in `lib/five_pm/version.rb`)
- `5pm-mcp` (MCP adapter, `mcp/`, version in `mcp/lib/five_pm/mcp/version.rb`)

Both always carry the same version and are released together.

## Working here

- The default branch is `master`. Branches are `feat/…`, `fix/…`, `docs/…`, `chore/…`, or
  `VERSION` for a release. Commits use Conventional Commits.
- Every change lands through a pull request with green CI, merged with a merge commit at
  the reviewed head (`gh pr merge N --merge --match-head-commit SHA`). A new push needs a
  new review. Never force-push `master` or skip hooks.
- Run commands through the `bin/` scripts, which select Ruby through mise when present:
  `bin/spec` (RSpec, SimpleCov ≥ 90%), `bin/lint` (RuboCop), `bin/package-mcp` (builds and
  smoke-tests both installed gems). Run all three before opening a pull request.
- With mise outside the scripts, use `mise exec -- bundle exec …`. Set
  `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`, or `spec/release_check_spec.rb` fails on encoding.
- New Ruby files start with a path comment and `# frozen_string_literal: true`.
- Add every user-visible change to `## Unreleased` in `CHANGELOG.md` in the same pull request.
  Create that heading under `# Changelog` if it is missing.
- Live 5PM checks (`bin/live-check`, `spec/support/live_*`) are opt-in, owner-controlled and
  never run in CI. Do not contact the live API unless the maintainer asks for it and
  names a disposable tenant.

## Releasing

Follow [docs/releasing.md](docs/releasing.md). In short:

1. `bin/release-prepare VERSION` on a clean, current `master`. It makes every release edit on
   a new `VERSION` branch; review, test, commit and open a `feat: vVERSION — SUMMARY` pull request.
2. After it merges: `bin/release-check VERSION MERGE_SHA`.
3. The maintainer dispatches **Release gems** with that version and SHA and approves its
   protected jobs. The workflow tags, publishes core then adapter, verifies the published
   bytes, and creates the GitHub release from the changelog.

Agents may prepare, test and open the release pull request, and may dispatch the workflow
only when the maintainer explicitly asks in this session. Agents must never approve
protected jobs, create or move release tags, push gems or edit a published release
without that request. Do not rerun a successful publish job. Published versions are
immutable; fix forward with a new patch version.

—
Stan Carver II
Made in Texas 🤠
https://stancarver.com
