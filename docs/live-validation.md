# Disposable-account validation

Live validation is optional and runs only when Stan requests it. It is not a release
or CI prerequisite and requires no ongoing subscription. Historical results remain
valid records of their original runs. See [release policy](releasing.md) and
[cached validation](cached-validation.md) for owner-controlled refreshes.

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

Earlier on 2026-10-30 qualification stopped before the sandbox/contract/mutation suite:
the supplied test credential was Admin, the saved browser session was signed out,
and independent isolation/record inventory could not be completed. Read-only
role-verification sessions were closed. No new qualification success is claimed.
That access blocker was later resolved through secure standard User provisioning;
the newer run below records a separate User-operation and cleanup failure. The
earlier historical report remains development evidence.

## Reproduce

Inject `FIVE_PM_HOST`, `FIVE_PM_LOGIN` and `FIVE_PM_PASSWORD` from an environment or
secret manager. Set `FIVE_PM_SANDBOX=1` and `FIVE_PM_SANDBOX_HOST` to the same host.
Run `bundle exec ruby bin/live-check` for read-only validation. Authentication creates
temporary API sessions, which the suite closes.

For explicitly authorized disposable CRUD checks, also set
`FIVE_PM_ALLOW_MUTATIONS=1` and run `bundle exec ruby bin/live-check --mutations`.
This creates labelled temporary records and a tiny synthetic text attachment. It
deletes those records, checks the attachment's exact bytes, verifies missing-record
errors and confirms no labelled records remain. Never enable this against a
production tenant. Live tests are not part of CI.

Suites run in this order: reads, core/MCP mutations, attachments, User management
(only when enabled, see below), then a read-only scan for leftover labelled records.
After the first failed suite, later write suites are skipped and reported with
`skipped_after`; the leftover scan still runs. Attachment qualification has its own
suite, so a User-management failure no longer hides attachment coverage.

### User-management permission boundary

5PM's [role reference](https://www.5pmweb.com/help/using_5pm.php) says a standard
User can add other users but cannot modify existing profiles other than their own;
only Administrators have unlimited rights. The API reference documents no
permissions or error codes for `users.add`, `users.update` or `users.remove`.
This matches the 2026-10-30 run below: `users.add` succeeded, then `users.update`
returned API code 8 and cleanup of the new User failed. Code 8 is undocumented,
so it is recorded as consistent with a role restriction, not as a confirmed meaning.

User administration is therefore excluded from standard-User qualification. The
User suite runs only with `FIVE_PM_LIVE_USER_ADMIN=1`, using an Administrator
account on a disposable tenant. It first confirms the authorized user's
`securityLevel` is `0` (admin) and stops before creating anything otherwise.
Without the flag, the report lists `users.add`, `users.update` and `users.remove`
under `api_operations_excluded` instead of failing them as missing. The SDK sends
these calls as given and does not check roles itself.

### Cleanup ledger

The attachment and User suites record every created record in a local cleanup
ledger before doing anything else with it, and remove the entry only after deletion
and absence are confirmed. The ledger defaults to
`~/.local/state/five-pm-ruby/live-cleanup-ledger.json` (override with
`FIVE_PM_LIVE_LEDGER`). It holds record IDs, so it is never copied into reports; the
tenant host is stored only as a SHA-256 digest.

The ledger fails closed rather than repairing unsafe state:

- Its path, after resolving symlinks, must be outside the repository.
- Its directory must be a real directory owned by you with mode `0700`. An existing
  directory with group or other access is refused, not tightened.
- The path may pass only through root-owned system symlinks (such as `/var` on
  macOS), and every parent must be owned by root or you and not writable by others
  unless sticky.
- The ledger and its lock are opened without following symlinks and must be regular
  files readable only by you.
- Writes go to a fresh, exclusively created temporary file that is renamed into
  place, so a leftover file is never reused.

Each suite first retries cleanup of its own earlier entries for the same tenant,
and stops before creating new records if any still cannot be removed. Entries from
other suites are left alone, so a User only an Administrator can delete does not
block attachment checks.

The ledger covers the attachment and User suites only. The core/MCP mutation suite
still keeps its created records in a per-process temporary file, which supports
cleanup within a run but not recovery after a crash.

The single JSON report identifies the base commit, dirty-worktree status and a
SHA-256 digest of the tested source. The digest covers the sorted Git tracked and
untracked, non-ignored files as `path`, NUL, byte length, NUL, then file bytes;
`docs/live-validation-report.json` itself is excluded. It is development evidence,
not a fresh validation of a different source commit. `bin/release-check` does not require live evidence.

The harness records successful transport operation names only, including calls made
by the actual stdio process. With `--mutations`, it fails unless every one of the
37 inventoried SDK operations was exercised, apart from the three User write
operations listed in `api_operations_excluded` when the User suite is not enabled. The report lists both verified and
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

## Standard User qualification — 2026-10-30

The [sanitized qualification receipts](live-qualification-2026-10-30.json) record a
new run against clean source `9322e03f75604d7279775dc88c9192add840e76e`.
Standard User identity, demo-record inventory, sandbox preflight, six WSDL inventories,
XSD parity, read checks and core mutations passed. All 16 MCP tools were exercised
successfully. The historical development report above remains unchanged.

The User/attachment suite stopped after creating a labelled test User: `users.update`
returned API code 8 and User cleanup failed. Independent inventory found one extra
labelled User; project/task/activity/group counts returned to baseline and no test
attachments remained. Attachment qualification was not reached. Further writes
stopped; no Administrator credentials or privilege changes were used. Sessions from
the independent identity/inventory checks closed successfully.

The run's recorded outcome is **blocked**, with cleanup **not verified** at the time
of the run. The receipts preserve that outcome unchanged; this is a historical failure
record, not `docs/live-validation.json` or passing evidence. Credentials, record IDs and
payloads are excluded.

Disposition: Stan later deleted the leftover labelled test User; no independent
post-deletion inventory is recorded here. Live qualification is no longer a release
prerequisite (see [release policy](releasing.md)), and 0.1.0 and 0.2.0 were published
on offline tests and package verification. The `users.update` API code 8
is undocumented but consistent with the standard-User restriction described under
User-management permission boundary above; any further live check, including the separated attachment and
Administrator-only User suites, runs only when Stan requests it.
