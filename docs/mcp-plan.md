# Standalone MCP adapter status

Tracks [issue #4](https://github.com/scarver2/5pm-ruby/issues/4).
The separately packaged implementation lives in `mcp/`; see its README for setup,
security boundaries, supported tools and test commands.

Implemented with synthetic regression tests and disposable-account checks:

- Official MCP Ruby SDK for protocol handling; no MCP dependency in the core gem.
- Read-only stdio executable and allowlisted resource tools.
- Optional embedded task/project mutations require explicit enablement and a trusted
  per-request approval callback over immutable exact arguments.
- Redacted responses/errors and audit events, bounded frames/pages, and no URL fetching.
- Real stdio integration tests, executable tests, and isolated installed-package checks.
- Generic host setup usable by Rodeo/A1Web without integration-specific dependencies.

Live verification also covers the actual stdio executable and project/task mutation
tools, including fresh operator approval and denied calls. See [live validation](live-validation.md).
Remaining: source review, accepted-commit release evidence, and explicit approval before publication.
