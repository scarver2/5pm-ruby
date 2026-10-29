# Standalone MCP adapter status

Tracks [issue #4](https://github.com/scarver2/5pm-ruby/issues/4).
The separately packaged implementation lives in `mcp/`; see its README for setup,
security boundaries, supported tools and test commands.

Implemented offline using synthetic fixtures:

- Official MCP Ruby SDK for protocol handling; no MCP dependency in the core gem.
- Read-only stdio executable and allowlisted resource tools.
- Optional embedded task/project mutations require explicit enablement and a trusted
  per-request approval callback over immutable exact arguments.
- Redacted responses/errors and audit events, bounded frames/pages, and no URL fetching.
- Real stdio integration tests, executable tests, and isolated installed-package checks.
- Generic host setup usable by Rodeo/A1Web without integration-specific dependencies.

Remaining: live disposable-account verification and explicit approval before any publication.
