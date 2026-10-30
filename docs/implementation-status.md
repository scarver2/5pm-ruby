# Issue #1 implementation status

Initial implementation, 2026-10-28. Worktree: `sdk`, branch: `feat/api-v2-sdk`.

## Implemented

- MIT gem scaffold with Ruby 3.2 minimum, explicit runtime dependencies and checksum lockfile.
- Snapshots of all six public demo service WSDLs and schema; 37 callable POST operations.
- Complete request/response part inventory with source discrepancies documented.
- Six services, five resource CRUD/list helpers, generic calls limited to verified POST bindings.
- HTTPS form POST, public IPv4 pinning, fixed account domains, timeouts, no redirects/proxies and read retries disabled by default.
- In-memory synchronized sessions with 30-minute TTL and conservative refresh margin.
- Error classes that omit remote bodies, network details and chained secret-bearing exceptions.
- RSpec synthetic tests, WSDL contract checks, SimpleCov 90% minimum, RuboCop, CI and Dependabot.
- Packaging validation, quickstart, contribution/security policies and separate MCP adapter plan.
- Opt-in typed response models for all 14 schema response types; unknown fields and raw JSON preserved.
- Nested typed lists, immutable snapshots, snake_case readers and redacted inspection.

- Bounded optional read retries/pagination, streamed body limits, request validation and explicit attachment helpers.
- Isolated package verification, read-only release gate and opt-in read-only sandbox preflight.
- Reviewed scarver2/abbu and scarver2/printavo-ruby patterns; see implementation-guides.md.

- Separate five_pm-mcp gem with official SDK, read-only stdio tools, opt-in host-confirmed mutations and redacted audit events.
- Real synthetic stdio/executable tests and isolated installation verification for both gem artifacts.

## Verification completed on 2026-10-30

- Offline schema, protocol, redaction, binary transport and mutation-safety regression tests.
- RuboCop, strict builds, core dependency isolation and installed-package checks.
- Live account-specific WSDL/schema comparison, all resource CRUD/read paths,
  pagination, user creation and synthetic-attachment byte round trips.
- Live MCP stdio reads and embedded project/task mutation approvals, denials and audits.
- Supported Ruby matrix: 3.2, 3.3, 3.4 and 4.0.

See [live validation](live-validation.md) for reproducible commands and API differences.
The development report identifies the tested working tree; it does not authorize a release.

## Remaining release gates

- Review and merge the tested source with passing hosted CI.
- Generate accepted-commit release evidence according to [releasing](releasing.md).
- Recheck RubyGems name availability and obtain explicit publication approval.

Date/time conversion is intentionally absent. Retry/rate-limit failure paths are
verified synthetically rather than by stressing the live account.
