# Release preparation

`bin/package` builds the gem, checks its exact file inventory and MIT license, then
loads the installed artifact in a subprocess outside Bundler's source checkout.
It does not publish. `bin/release-check VERSION FULL_COMMIT_SHA` is also read-only.

Before a release:

For **0.1.0 only**, the maintainer has selected the recorded baseline rather than
requiring a fresh live run of the exact candidate. This is a release qualification
policy decision, not authorization to publish. Live testing remains opt-in.

`docs/recorded-release-baseline.json` pins the SHA-256 of the existing sanitized
`docs/live-validation-report.json`. The read-only gate requires the report's successful
read, mutation, attachment/user and cleanup results, complete coverage of the
candidate operation inventory, and an ancestral historical commit. It rejects
changed report bytes, missing operations or unsuccessful cleanup. The historical
report remains unchanged: its dirty-worktree provenance and `release_evidence: false`
are retained. No fresh live testing of the candidate is claimed. Synthetic fixtures
and WSDL/XSD snapshots support repeatable offline regression tests; they are not a
VCR cassette or a guarantee about the service's present state.

1. Merge reviewed source and policy changes through PRs with passing four-version CI.
2. Keep both gem versions aligned and prepare a dated changelog before publication.
3. Run `bin/spec`, `bin/lint`, and `bin/package-mcp` for the candidate. Review differences
   from the historical baseline, including packaging and response-contract changes.
4. Fetch origin/master and tags; from a clean checkout run
   `bin/release-check VERSION FULL_COMMIT_SHA`. Accepted-master, dated changelog,
   matching gem versions and immutable-tag checks still apply.
5. Verify the protected release environment and both RubyGems trusted publishers.
   Request separate approval of the specific version and exact commit before dispatch.

For versions **other than 0.1.0**, the existing exact-commit live-evidence policy
remains: `docs/live-validation.json` must record version, full `evidence_commit`,
`disposable_tenant: true`, `result: "passed"`, and verified contract/read/mutation
booleans. Its tested commit must be ancestral and the candidate tree may differ only
in that evidence file. Do not fabricate this evidence or relabel the historical report.
A future recorded-baseline decision requires another reviewed policy change.

Optional live validation: see [disposable-account validation](live-validation.md).
Verify an isolated disposable tenant and standard User privileges, run the read-only
sandbox preflight first, and enable mutations only with explicit authorization and
`FIVE_PM_ALLOW_MUTATIONS=1`. Verify cleanup and keep credentials, identifiers and
account payloads out of reports. Live checks are never run by CI or publication.

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
or inaccessible environment metadata stops the run. The current GitHub connection
cannot create this environment: GitHub returned HTTP 403, administrator rights required.

Sign into RubyGems.org and create two
[pending trusted publishers](https://rubygems.org/profile/oidc/pending_trusted_publishers)
for the first publication:

| Gem name | GitHub owner | Repository | Workflow filename | Environment |
| --- | --- | --- | --- | --- |
| `5pm` | `scarver2` | `5pm-ruby` | `release.yml` | `release` |
| `5pm-mcp` | `scarver2` | `5pm-ruby` | `release.yml` | `release` |

These are separate gem registrations using the same workflow identity. For an
already-owned gem, configure its trusted publisher instead of a pending publisher.
Recheck both names for availability before publication. Account setup must
be completed by the authenticated RubyGems owner; repository configuration alone
does not establish that connection.

## Shared bin-script conventions

Like abbu and printavo, Bash entrypoints source `bin/_lib.sh`, change to the
repository root, and select Ruby through mise when available. Run them directly:

```sh
bin/spec
bin/lint
bin/package
bin/package-mcp
bin/release-check VERSION FULL_COMMIT_SHA
```

`bin/package` writes `pkg/5pm-VERSION.gem`; `bin/package-mcp` also writes
`mcp/pkg/5pm-mcp-VERSION.gem`. Inventory checks live in `bin/verify-package.rb`;
package installation, smoke checks, and release logic live in Ruby helpers under
`bin/support/`, following printavo's layout. Temporary installs are removed on exit.
Dependencies come from the verified bundle, as in abbu, without network installation.

`bin/verify-release-tag` reads `RELEASE_TAG_REF` (or `GITHUB_REF` on tag events), requires `refs/tags/vVERSION`, and
verifies that the tag matches HEAD and passes the accepted-commit preflight.
It is read-only. Publication remains the protected workflow's `rake release`.

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

Before dispatch, complete the version-specific baseline/evidence and dated changelog
gates above. Both gem versions must match. Preparing this workflow does not
advance the version, date the changelog or authorize publication.

After merging the workflow, open Actions → **Release gems** → **Run workflow** on
`master`. Enter the explicitly approved stable version without `v` and its full
40-character accepted commit SHA. The read-only preflight rejects an unaccepted
commit, untested changes, incomplete evidence, mismatched versions or a conflicting tag.
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
package depends on the matching core version. The workflow does not create a GitHub
Release. No workflow should be dispatched merely to test the connection: a successful
run publishes both gems.

If core publication succeeds and MCP fails, inspect the published core version and
provenance, fix the cause, and rerun only the failed jobs against the same approved
candidate. Do not rerun an already-successful publish job, move the tag, overwrite a
published version or automatically yank it. Code changes require a new reviewed
candidate and its version-specific validation; arrange a new version when the core is already published.
