# Disposable-account validation

Live validation on 2026-10-30 exercised both packages using a disposable tenant.
Reports and fixtures exclude its hostname, credentials, session tokens, record IDs,
account payloads and attachment contents.

## Reproduce

Inject `FIVE_PM_HOST`, `FIVE_PM_LOGIN` and `FIVE_PM_PASSWORD` from an environment or
secret manager. Set `FIVE_PM_SANDBOX=1` and `FIVE_PM_SANDBOX_HOST` to the same host.
Run `bundle exec ruby bin/live-check` for read-only validation. Authentication creates
temporary API sessions, which the suite closes.

For explicitly authorized disposable CRUD checks, also set
`FIVE_PM_ALLOW_MUTATIONS=1` and run `bundle exec ruby bin/live-check --mutations`.
This creates labelled temporary records, a reserved-domain test user, and a tiny
synthetic text attachment. It deletes those records, checks the attachment's exact
bytes, verifies missing-record errors and confirms no labelled records remain.
Never enable this against a production tenant. Live tests are not part of CI.

The single JSON report identifies the base commit, dirty-worktree status and a
SHA-256 digest of the tested source. The digest covers the sorted Git tracked and
untracked, non-ignored files as `path`, NUL, byte length, NUL, then file bytes;
`docs/live-validation-report.json` itself is excluded. It is development evidence,
not the accepted-commit release evidence required by `bin/release-check`.

## Verified scope

- Six account-specific WSDL POST operation inventories and the XSD model inventory
  match the public snapshots.
- Sign-in/out, authorized-user readers, SSL check, no-op, all resource lists and
  individual reads, email lookup, and bounded offset pagination.
- Create/update/get/delete of disposable projects, tasks, project groups, activity
  and a user; the test user uses a reserved `.invalid` email address.
- Attachment upload with explicit base64 content, metadata listing, bounded binary
  download with byte-for-byte verification, and deletion.
- Actual MCP stdio initialization, discovery, all five list tools and default write
  denial; embedded project/task creation, update, get and deletion with exact per-call
  approval, denied reuse, rejected agent booleans and redacted audit fields.
- Offline schema/protocol/security regressions, package installation checks and
  the supported Ruby 3.2/3.3/3.4/4.0 matrix.

## Observed differences from the WSDL

- JSON results use `data` instead of WSDL response-part names. Reader views map
  these to the operation's declared part; raw JSON is retained unchanged.
- `User.canViewProfiles` is a JSON boolean despite the XSD string declaration.
  Both strings and booleans are retained in their original representation.
- Project/task deletion returns an integer marker; group/activity deletion returns
  a boolean. Integer markers are preserved without assigning undocumented meaning.
- API errors can arrive with HTTP 200 and numeric `code` plus `message`, including
  code 0 for missing required parameters and code 441 for missing records. Only
  the numeric code is exposed; remote messages are discarded.
- User creation accepts symbolic role names (the suite uses `user`) and rejects
  the numeric role representations shown in the help reference.
- `nop` returns `data: null`. File downloads return binary bytes despite JSON options.

Dates remain exact strings; no timezone inference or conversion is performed.
Retries, rate limits, transport failures and malformed schemas are tested with
synthetic responses rather than inducing failures or load on the live account.
Publication, hosted-CI acceptance and accepted-commit release evidence remain separate gates.
