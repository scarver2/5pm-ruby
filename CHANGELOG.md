# Changelog

## 0.1.0 — unreleased

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
