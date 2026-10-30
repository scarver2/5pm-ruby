# Release preparation

`bin/package` builds the gem, checks its exact file inventory and MIT license, then
loads the installed artifact in a subprocess outside Bundler's source checkout.
It does not publish. `bin/release-check VERSION FULL_COMMIT_SHA` is also read-only.

Before a release:

Choose the release version and dated changelog before the final live-validation run.
The candidate must have the same tracked tree as its tested commit, except for the
`docs/live-validation.json` evidence file itself. Any other change requires validation
again, including changes to tests, packaging, the MCP adapter or release tooling.

1. Merge reviewed changes through PRs with passing CI; do not change master directly.
2. Obtain a disposable account and compare its six WSDLs and schema with the public snapshots.
3. Inject credentials via the process environment. Designate the test tenant explicitly
   with `FIVE_PM_SANDBOX=1` and `FIVE_PM_SANDBOX_HOST=$FIVE_PM_HOST`.
   Run `bundle exec ruby bin/sandbox-check`. It checks authentication and resource list
   envelopes without changing account data; it creates and closes a temporary session.
   Its redacted report is only `read_only_passed`, not full release evidence.
   On failure, stderr includes a JSON diagnostic with a fixed operation stage and
   error category (and numeric HTTP status when available). It never includes
   exception messages, credentials or response bodies. `authentication_rejected`
   indicates HTTP 401/403; `unexpected_response` indicates a JSON/contract mismatch,
   which does not establish that the password is wrong. A cleanup failure does not
   replace the diagnostic for an earlier failed operation.
   Sign-in failures also report whether parsed JSON was received and its shape:
   only fixed, known contract fields and JSON types are emitted, never arbitrary
   keys, scalar values, tokens or server error text. This distinguishes a missing
   authentication envelope from a transport JSON-decoding failure without dumping
   the response body.
   Typed validation failures include `schema_mismatch` with the declared field name,
   expected schema type and actual JSON type. No field values are retained in that
   error or printed. Nested errors identify the innermost invalid field.
4. Record sanitized real success/error fixtures, including HTTP-200 errors if observed.
   Verify offsets, totals, dates, bool encoding, and attachments. Perform destructive
   create/update/delete checks only in that disposable account, explicitly enabled by
   the operator. Do not run these checks in CI or point them at production.
   The reproducible `bin/live-check --mutations` suite requires both disposable-tenant
   designation and `FIVE_PM_ALLOW_MUTATIONS=1`. See [live validation](live-validation.md).
   Its dirty-worktree development report is not a substitute for accepted-commit evidence.
5. Commit reviewed evidence in `docs/live-validation.json` with the tested `version`,
   full `evidence_commit`, `disposable_tenant: true`, `result: "passed"`, and separately
   verified `contract_verified`, `read_operations_verified`, `mutation_operations_verified`
   booleans. Never include a tenant hostname, login, password, session token or account payload.
   No success evidence is supplied in this repository until those checks actually happen.
6. Pass CI and `bin/package` for the tested version and dated changelog, and merge the
   release preparation through review. Fetch origin/master and tags, then run
   `bin/release-check VERSION FULL_COMMIT_SHA` from a clean checkout. The command
   requires the candidate to be accepted on origin/master and rejects conflicting tags.
7. Recheck the RubyGems name and request explicit maintainer publication approval.
   Publication must target the approved version and exact reviewed commit. Tag and
   publish only after that approval using the protected workflow described below.

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

Before dispatch, complete the live evidence and dated changelog gates above. Both
gem versions must match. The development report `docs/live-validation-report.json`
does not satisfy `docs/live-validation.json`. Preparing this workflow does not
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
candidate and fresh evidence; arrange a new version when the core is already published.
