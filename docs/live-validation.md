# Disposable-account validation

Live validation on 2026-10-30 exercised both packages using a disposable tenant.
Reports and fixtures exclude its hostname, credentials, session tokens, record IDs,
account payloads and attachment contents.

## Qualification prerequisites

Before live qualification, independently verify the designated disposable tenant is
active, isolated from production, and contains no business records requiring
preservation. Verify the credential is Cora's standard User, not Admin. Owner
confirmation alone does not replace these read-only checks. Do not change roles,
create replacement users or elevate privileges without separate authorization.

Run the sandbox preflight first, then compare the tenant's six WSDL inventories and
XSD against the snapshots before running the documented bounded mutation suite.
Operate only on newly created labelled records; verify attachment removal, deletion
readbacks, zero labelled leftovers and session cleanup. Stop on unverified isolation,
permissions or cleanup. Record failures and the exact tested commit without secrets
or account payloads. Live testing remains opt-in and is never part of CI.

On 2026-10-30 qualification stopped before the sandbox/contract/mutation suite:
the supplied test credential was Admin, the saved browser session was signed out,
and independent isolation/record inventory could not be completed. Read-only
role-verification sessions were closed. No new qualification success is claimed.
A securely supplied standard User account and independent tenant verification are
required to resume. The earlier historical report remains development evidence.

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

The harness records successful transport operation names only, including calls made
by the actual stdio process. With `--mutations`, it fails unless every one of the
37 inventoried SDK operations was exercised. The report lists both verified and
missing operations. It also requires a successful live call to every one of the
16 tools advertised by the mutation-enabled MCP server (10 reads, six writes).
No arguments, record IDs, return payloads or credentials enter this operation audit.

The web UI normally shows only the original demo data after verification because
all labelled test records are deleted. Write verification includes read-after-update
assertions, post-delete failures and a final scan for leftover records; it does not
depend on retaining records in the UI.
Attachment removal requires a successful deletion result and a new attachment-list
request showing the target file is absent before parent-record cleanup begins.
Subprocess deadlines cover process exit and pipe draining; timed-out process groups
are killed and reaped rather than waiting indefinitely in Open3 cleanup.
Cleanup entries remain tracked until both a successful deletion result and absence
are verified. False results and failed readbacks preserve entries for recovery.
Users/groups use generic API errors for missing records, so their complete getAll
lists must independently confirm absence. Cleanup first checks whether an earlier
deletion already succeeded before sending another deletion request.

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
