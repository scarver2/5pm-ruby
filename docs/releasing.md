<!-- docs/releasing.md -->
# Releases

`bin/package` builds the gem, checks its exact file inventory and MIT license, then
loads the installed artifact in a subprocess outside Bundler's source checkout.
It does not publish. `bin/release-check VERSION FULL_COMMIT_SHA` is also read-only.


## Published releases

From 0.2.2 on, the workflow creates each version's GitHub release from its
changelog section after both gems are published; that release is the record.

### 0.2.1

Both gems were published on 2026-11-25 by the protected **Release gems** workflow
through RubyGems trusted publishing, from accepted commit
`e1bc8a1743c8cb3ae36f93ae0f579d7a952ff705`, tagged `v0.2.1`. It widens the `mcp`
dependency of `5pm-mcp`; the core gem has no code changes.

- [5pm 0.2.1](https://rubygems.org/gems/5pm/versions/0.2.1)
- [5pm-mcp 0.2.1](https://rubygems.org/gems/5pm-mcp/versions/0.2.1)
- [Successful release workflow run](https://github.com/scarver2/5pm-ruby/actions/runs/45686308853)

```sh
gem install 5pm --version 0.2.1
# Install this for MCP support; it includes the core SDK:
gem install 5pm-mcp --version 0.2.1
```

Bundler applications use `gem "5pm", "~> 0.2.1"` or
`gem "5pm-mcp", "~> 0.2.1"`, followed by `bundle install`.
Version 0.2.1 is immutable: do not repeat its pushes or move its tag.

### 0.2.0

Both gems were published on 2026-11-24 by the protected **Release gems** workflow
through RubyGems trusted publishing, from accepted commit
`b6325c87f660624c4dac4abf1e3639ca8b673231`, tagged `v0.2.0`.

- [5pm 0.2.0](https://rubygems.org/gems/5pm/versions/0.2.0)
- [5pm-mcp 0.2.0](https://rubygems.org/gems/5pm-mcp/versions/0.2.0)
- [GitHub release notes](https://github.com/scarver2/5pm-ruby/releases/tag/v0.2.0)
- [Successful release workflow run](https://github.com/scarver2/5pm-ruby/actions/runs/45461974540)

```sh
gem install 5pm --version 0.2.0
# Install this for MCP support; it includes the core SDK:
gem install 5pm-mcp --version 0.2.0
```

Bundler applications use `gem "5pm", "~> 0.2.0"` or
`gem "5pm-mcp", "~> 0.2.0"`, followed by `bundle install`.
Version 0.2.0 is immutable: do not repeat its pushes or move its tag.

### 0.1.0

Both gems were published on 2026-10-30 from accepted commit
`0a48bcd297a28e0ee7c22be8bc594daad4a88511`, tagged `v0.1.0`.

- [5pm 0.1.0](https://rubygems.org/gems/5pm/versions/0.1.0)
- [5pm-mcp 0.1.0](https://rubygems.org/gems/5pm-mcp/versions/0.1.0)
- [GitHub release, artifacts and SHA256SUMS](https://github.com/scarver2/5pm-ruby/releases/tag/v0.1.0)

The owner completed manual RubyGems publication with security-key approval, core
first and MCP second. Both public downloads matched the final build byte for byte;
a fresh isolated installation and loading of both gems succeeded. Offline validation
passed 149 specs, 98.19% coverage, lint, RBS, package checks and four-version hosted CI.
See the [completed first-publication record](release-preparation/manual-first-publication.md).
Version 0.1.0 is immutable: do not repeat its pushes or move its tag. The procedures
below apply to future versions.

## Owner-controlled live validation

Stan Carver II decides when another live API check is useful. Live API access,
an active trial or paid subscription, Keychain credentials, and fresh live evidence
are not release prerequisites. The 15-day trial does not create an ongoing account
requirement. Releases and CI use offline tests, stored contracts, package verification
and maintainer acceptance of the exact candidate.

Historical reports retain their actual outcomes and tested source. Do not relabel
an old report as a fresh check. `bin/validate` reuses its local sanitized report
without expiration or network requests, even if source changes; `source_matches`
indicates whether its fingerprint still matches. Only an explicit owner-requested
refresh contacts 5PM. See [cached validation](cached-validation.md).

## Releasing a new version

Record user-visible changes under `## Unreleased` in `CHANGELOG.md` as they merge.
Then, with explicit maintainer approval for the version:

1. From a clean `master` that matches `origin/master`, run
   `bin/release-prepare VERSION` (add `--date YYYY-MM-DD` to date it for another
   day). On a new `VERSION` branch it bumps both gem versions, moves the Unreleased
   entries under `## VERSION — DATE`, keeps the adapter's `5pm` requirement on the
   same minor series, updates both lockfiles and the install instructions in both
   READMEs. It refuses a dirty or stale checkout, an existing tag, a version that is
   not greater, or an empty Unreleased section. It never commits, pushes, tags or
   publishes.
2. Review the diff, run `bin/spec`, `bin/lint --cache false` and `bin/package-mcp`,
   commit (`chore: prepare VERSION release`), and open a pull request titled
   `feat: vVERSION — SUMMARY`. Merge it only after review at its exact head.
3. Fetch `origin/master` and tags, then run `bin/release-check VERSION MERGE_SHA`.
   It checks accepted source ancestry, matching versions, the dated changelog and
   conflicting tags. It does not contact 5PM or require live evidence.
4. Dispatch **Release gems** with that version and merge SHA, the same day as the
   changelog date. The maintainer approves the protected tag job and each publish
   job. The final job posts the GitHub release notes from the changelog; preview
   them with `bin/release-notes VERSION` once the tag exists.

If the release slips past the changelog date, re-date it in a follow-up pull request
and use that merge commit instead.

Optional live checks remain available when the owner requests them. If used, keep
them outside CI, designate a disposable tenant, and enable mutations separately.
Record actual results and clean up labelled records; do not invent success receipts.
See [live validation](live-validation.md). Outstanding API observations can be
tracked as known issues without imposing a mandatory new live test campaign.

## Connect GitHub and RubyGems once

This follows [abbu's release workflow](https://github.com/scarver2/abbu/blob/4c64d0eb0ccdbc0a8c04b2e50da92594faf75d09/.github/workflows/release.yml)
(browser dispatch, exact commit, separate tag and publish jobs) and
[printavo's release workflow](https://github.com/scarver2/printavo-ruby/blob/464ae6f29b8ff7627cf829c02351d1b9eadea37d/.github/workflows/release.yml)
(pinned RubyGems action and Bundler tasks). Both packages publish through
[trusted publishing](https://guides.rubygems.org/trusted-publishing/), without a
long-lived RubyGems API key or GitHub PAT in repository secrets.

A repository administrator must create the
[release environment](https://github.com/scarver2/5pm-ruby/settings/environments):

- Name: `release`; required reviewer: `scarver2`.
- Disable administrator bypass. Allow the initiating maintainer to approve, matching abbu.
- Select deployment branches and tags: branch `master` and tag `v*`, only.

Both owner prerequisites remain required: this protected GitHub `release`
environment and RubyGems trusted publishers for **both** `5pm` and `5pm-mcp`.
Workflow environment variables only describe execution context and the selected
candidate; they are not independent authorization. GitHub's required-reviewer
approval gate and RubyGems' matching OIDC publisher policies enforce authorization.

The workflow checks these protections before building or tagging. Missing protection
or inaccessible environment metadata stops the run. The first release (0.1.0) used manual publication. Release 0.2.0 was the first
automated publication through this workflow, confirming that the protected
environment and both trusted publishers are configured.

Each existing gem (`5pm` and `5pm-mcp`) has a RubyGems trusted publisher using
GitHub owner `scarver2`, repository `5pm-ruby`, workflow `release.yml`, and
environment `release`. Keep these in sync if the workflow filename or environment
changes; repository configuration alone does not establish RubyGems authorization.

## Shared bin-script conventions

Like abbu and printavo, Bash entrypoints source `bin/_lib.sh`, change to the
repository root, and select Ruby through mise when available. Run them directly:

```sh
bin/spec
bin/lint
bin/package
bin/package-mcp
bin/release-check VERSION FULL_COMMIT_SHA
bin/release-prepare VERSION [--date YYYY-MM-DD]
bin/release-notes VERSION [--run-url URL]
```

`bin/package` writes `pkg/5pm-VERSION.gem`; `bin/package-mcp` also writes
`mcp/pkg/5pm-mcp-VERSION.gem`. Inventory checks live in `bin/verify-package.rb`;
package installation, smoke checks, and release logic live in Ruby helpers under
`bin/support/`, following printavo's layout. Temporary installs are removed on exit.
Dependencies come from the verified bundle, as in abbu, without network installation.

`bin/verify-release-tag` reads `RELEASE_TAG_REF` (or `GITHUB_REF` on tag events), requires `refs/tags/vVERSION`, and
verifies that the tag matches HEAD and passes the accepted-commit preflight.
It is read-only. Publication remains the protected workflow's `rake release`.

`bin/release-prepare` edits only local files on a new branch (see above).
`bin/release-notes` prints the GitHub release notes for an existing tag from its
changelog section and the gemspecs, and is read-only.

## Build and approve a release

Standard Bundler tasks build the core and MCP artifacts respectively:

```sh
bundle exec rake build
bundle exec rake -f mcp/Rakefile build
bundle exec rake
bundle exec rubocop --cache false
bin/package-mcp
```

The packaging checks inspect the actual installed artifacts. CI repeats validation
on Ruby 3.2, 3.3, 3.4 and 4.0. Release builds set `SOURCE_DATE_EPOCH` to the approved
commit timestamp. Neither build task publishes.

Before dispatch, merge the `bin/release-prepare` pull request and complete the
offline checks above. Both gem versions must match. Live reports are optional
historical evidence. Preparing a release does not authorize publication.

After merging the workflow, open Actions → **Release gems** → **Run workflow** on
`master`. Enter the explicitly approved stable version without `v` and its full
40-character accepted commit SHA. The read-only preflight rejects an unaccepted
commit, a dirty checkout, an undated changelog, mismatched versions or a conflicting tag.
Tag pushes never start publication. The only release entry point is manual dispatch
from `master`; dispatch from any other branch or tag is rejected. Version and full
commit inputs must identify the explicitly approved candidate.

Approve the protected tag job only after inspecting the candidate summary and
verification jobs. It creates `vVERSION` only if absent and verifies its exact target;
it never moves an existing tag. Approve each protected publication job for that same
candidate. Publishing has OIDC permission and read-only repository contents; only
the separate tag job can write repository contents. Bundler's source-control push
action is disabled. Local publishing tasks refuse to run outside this workflow.

The pinned `rubygems/release-gem` action invokes `bundle exec rake release` for the
core gem, waits for RubyGems availability, then does the same in `mcp/`. The MCP
package depends on the matching core version. After both gems are published and
byte-verified, a final Contents-write job without publishing rights creates the
`vVERSION` GitHub release from the changelog, unless that release already exists. No workflow should be dispatched merely to test the connection: a successful
run publishes both gems.

If core publication succeeds and MCP fails, inspect the published core version and
provenance, fix the cause, and rerun only the failed jobs against the same approved
candidate. Do not rerun an already-successful publish job, move the tag, overwrite a
published version or automatically yank it. Code changes require a new reviewed
candidate and fresh evidence; arrange a new version when the core is already published.


—
Stan Carver II
Made in Texas 🤠
https://stancarver.com
