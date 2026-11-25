# Changelog

## 0.2.1 — 2026-11-25

- Allow `mcp` from 1.6.1 up to (not including) 1.12.0 in `5pm-mcp`, instead of
  `~> 1.6.1`, so installed adapters can use current `mcp` releases. CI now also runs
  the suite on Ruby 3.2 with `mcp` 1.6.1 to keep the lower bound tested. The core
  `5pm` gem has no code changes; it is released at the same version as the adapter.
- Split the opt-in live attachment checks from User management, and run the User
  suite only with `FIVE_PM_LIVE_USER_ADMIN=1` and a verified Administrator account.
  Without it, User write operations are reported as excluded, not missing.
- Skip later live write suites after the first failure while still scanning for
  leftover records.
- Track records created by the live attachment and User suites in a protected local
  cleanup ledger outside the repository. It refuses symlinks, loose permissions,
  untrusted parents and any malformed or ambiguous entry, and each suite finishes its
  own earlier cleanup before creating new records. Run one live check at a time.
- Document the standard-User restriction behind the 2026-10-30 `users.update`
  API code 8. These changes affect only the opt-in live harness, not the gems.

## 0.2.0 — 2026-11-24

- Add optional trusted `project_ids` scoping to the MCP adapter and
  `FIVE_PM_PROJECT_IDS` to its executable. Scoped adapters expose five read tools,
  require explicit project selection for multi-project task/activity lists, and
  reject out-of-scope results before returning account data. The unscoped default
  and its per-call mutation approval behavior remain supported.

## 0.1.0 — 2026-10-30

- Make live API validation optional and owner-controlled. Releases no longer require
  an active 5PM account or fresh live evidence; cached reports never expire or force
  a refresh after source changes. Offline tests and artifact checks remain required.

- Restrict releases to manual dispatch from master for an explicitly approved
  version and exact commit; retain protected environment approval for tag/publish jobs.

- Align packaging/release bin scripts with abbu and printavo: shared Bash runner,
  Ruby support helpers, pkg artifacts, isolated installs and read-only tag verification.

- Name the packages `5pm` and `5pm-mcp`, with matching dependencies, builds and
  release configuration; retain the `FivePM` Ruby namespace and require paths.

- Prepare protected GitHub OIDC publishing for both gems, with exact-commit release
  checks, separate tag permissions, and standard Bundler build/release tasks.

- Retain live cleanup ledger entries until deletion is confirmed; reject false/null/zero
  results and independently verify absence when lookup errors use a generic API code.

- Recognize mapped response parts in presence checks, verify attachment absence after
  deletion, and bound live subprocess exit and pipe draining with process-group cleanup.

- Validate UTF-8 JSON after streamed chunks are assembled; preserve arbitrary bytes
  when probing binary downloads for API error envelopes.

- Ship RBS for both gems, including all generated model readers and MCP callback
  contracts; validate source and installed-package signatures in the default checks.

- Live disposable-account contract, CRUD, pagination, MCP stdio and mutation-approval verification.
- Redacted numeric `APIError` for HTTP-200 errors, including code 0 validation errors.
- Preserve live integer deletion markers and add bounded binary `Download` results.
- Opt-in reproducible live suite with separate mutation enablement and cleanup checks.

- Accept live JSON booleans as well as WSDL strings for `User.canViewProfiles`,
  preserving both representations without relaxing other string fields.

- Accept the observed sign-in JSON envelope `data.sessionId`, retain the original
  WSDL-shaped envelope, and reject ambiguous authentication responses.
- Map operation-specific `data` envelopes in typed readers, pagination and MCP,
  preserving raw wire JSON and false scalar results without replaying mutations.

- Initial SDK scaffold, contract inventory, POST transport and synchronized sessions.
- Generic service calls validated against public demo WSDL POST bindings.
- CRUD/list helpers for all five resource services, synthetic RSpec contracts, CI and packaging.
- Opt-in immutable typed responses for all schema response types, with lossless raw JSON,
  snake_case readers, nested typed lists and strict scalar normalization.
- Synthetic JSON fixtures and schema parity tests; live envelope verification remains pending.

- Bounded opt-in read retries and pagination; streamed response-size limits and specific HTTP errors.
- Pre-I/O request validation, rejected-session invalidation and copied credentials.
- Explicit user/authentication/attachment helpers and typed-model request round trips.
- Fix Enumerable overriding typed list `to_h`.
- Isolated packaging, read-only release gates and opt-in sandbox preflight.

- Separate 5pm-mcp package with official MCP SDK protocol handling, default read-only
  tools, per-request operator approval for embedded mutations and redacted audit events.
- Real synthetic stdio/executable tests and isolated installation checks for both artifacts.
- Host-configurable MCP tool allowlists and stdio confirmation-enforcement regression tests.

- Review fixes: retain typed-list serialization in the base layer, include DNS lookup
  in timeout handling, reject stale live-validation evidence after code changes, and
  emit successful MCP audit outcomes only after result serialization succeeds.
