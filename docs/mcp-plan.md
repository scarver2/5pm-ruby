# Follow-up: standalone MCP adapter

Implement in a separate package after SDK sandbox verification.

- Read-only tools by default: find/list projects, tasks, groups, users and activity.
- Separate explicit enablement for mutation tools; require user confirmation per mutation.
- Allowlisted tenant and operations; least-privilege 5pm test/service user.
- Audit operation, outcome, timestamp and request identifier without credentials or payload secrets.
- Obtain secrets by process environment or an injected secret provider; no persistence.
- Treat account content as untrusted data, never agent instructions.
- Confirm pagination and error contracts before tool schemas are frozen.
- Evaluate Rodeo/A1Web as optional integrations without dependencies in the Ruby SDK.

Acceptance: adapter tests prove default mutation denial, secret redaction, and confirmations.
Create the remote follow-up issue when repository issue-writing is authorized.
