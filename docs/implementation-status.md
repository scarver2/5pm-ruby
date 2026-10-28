# Issue #1 implementation status

Initial implementation, 2026-10-28. Worktree: `sdk`, branch: `feat/api-v2-sdk`.

## Implemented

- MIT gem scaffold with Ruby 3.2 minimum, explicit runtime dependencies and checksum lockfile.
- Snapshots of all six public demo service WSDLs and schema; 37 callable POST operations.
- Complete request/response part inventory with source discrepancies documented.
- Six services, five resource CRUD/list helpers, generic calls limited to verified POST bindings.
- HTTPS form POST, public IPv4 pinning, fixed account domains, timeouts, no redirects/proxies/retries.
- In-memory synchronized sessions with 30-minute TTL and conservative refresh margin.
- Error classes that omit remote bodies, network details and chained secret-bearing exceptions.
- RSpec synthetic tests, WSDL contract checks, SimpleCov 90% minimum, RuboCop, CI and Dependabot.
- Packaging validation, quickstart, contribution/security policies and separate MCP adapter plan.

## Verified locally

- Ruby 4.0.9: 39 passing examples, 100% line coverage.
- RuboCop: no offenses.
- Strict gem build: successful; package file inventory and MIT license verified.
- Plain Ruby can load the SDK without development dependencies.

## Deferred at user request

Use synthetic tests for now; a disposable test account will be provided later.
No authenticated API calls or account mutations have been made.

## Remaining acceptance gates

- Validate contracts against that test account; confirm JSON envelopes and error shapes.
- Add sanitized observed fixtures alongside synthetic ones and opt-in sandbox tests.
- Implement lossless typed response mapping after envelope verification.
- Verify pagination behavior, date/timezone semantics, attachments and rate-limit handling.
- Run the Ruby 3.2/3.3/3.4/4.0 matrix in hosted CI.
- Create the standalone MCP tracking issue from docs/mcp-plan.md when adapter work begins.
- Check RubyGems name availability before release; obtain explicit approval before publishing.

The proposed change does not close issue #1; this is a reviewable initial milestone.
