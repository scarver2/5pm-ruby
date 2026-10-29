# Release preparation

`bin/package` builds the gem, checks its exact file inventory and MIT license, then
loads the extracted artifact in a subprocess outside Bundler's source checkout.
It does not publish. `bin/release-check VERSION FULL_COMMIT_SHA` is also read-only.

Before a release:

1. Merge reviewed changes through PRs with passing CI; do not change master directly.
2. Obtain a disposable account and compare its six WSDLs and schema with the public snapshots.
3. Inject credentials via the process environment. Designate the test tenant explicitly
   with `FIVE_PM_SANDBOX=1` and `FIVE_PM_SANDBOX_HOST=$FIVE_PM_HOST`.
   Run `bundle exec ruby bin/sandbox-check`. It checks authentication and resource list
   envelopes without changing account data; it creates and closes a temporary session.
   Its redacted report is only `read_only_passed`, not full release evidence.
4. Record sanitized real success/error fixtures, including HTTP-200 errors if observed.
   Verify offsets, totals, dates, bool encoding, and attachments. Perform destructive
   create/update/delete checks only in that disposable account, explicitly enabled by
   the operator. Do not run these checks in CI or point them at production.
5. Commit reviewed evidence in `docs/live-validation.json` with the tested `version`,
   full `evidence_commit`, `disposable_tenant: true`, `result: "passed"`, and separately
   verified `contract_verified`, `read_operations_verified`, `mutation_operations_verified`
   booleans. Never include a tenant hostname, login, password, session token or account payload.
   No success evidence is supplied in this repository until those checks actually happen.
6. Add a dated changelog entry and version, pass CI and `bin/package`, and merge the
   release preparation through review. Fetch origin/master and tags, then run
   `bin/release-check VERSION FULL_COMMIT_SHA` from a clean checkout. The command
   requires the candidate to be accepted on origin/master and rejects conflicting tags.
7. Recheck the RubyGems name and request explicit maintainer publication approval.
   Publication must target the approved version and exact reviewed commit. Tag and
   publish only after that approval. There is no automated publishing workflow.

On 2026-10-29, RubyGems' `GET /api/v1/gems/five_pm.json` returned 404. This check
neither reserves the name nor guarantees future availability.
