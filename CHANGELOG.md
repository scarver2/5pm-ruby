# Changelog

## 0.1.0 — unreleased

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

- Separate five_pm-mcp package with official MCP SDK protocol handling, default read-only
  tools, per-request operator approval for embedded mutations and redacted audit events.
- Real synthetic stdio/executable tests and isolated installation checks for both artifacts.

- Review fixes: retain typed-list serialization in the base layer, include DNS lookup
  in timeout handling, reject stale live-validation evidence after code changes, and
  emit successful MCP audit outcomes only after result serialization succeeds.
