# Release preparation

`bin/package` builds the gem, checks its exact file inventory and MIT license, then
loads the extracted artifact in a subprocess outside Bundler's source checkout.
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
   publish only after that approval. There is no automated publishing workflow.

On 2026-10-29, RubyGems' `GET /api/v1/gems/five_pm.json` returned 404. This check
neither reserves the name nor guarantees future availability.
