# Security

Report vulnerabilities privately through GitHub private vulnerability reporting when enabled.
Do not put credentials or private account data into public issues.

The client uses HTTPS POST bodies, peer certificate verification, fixed account hostnames,
public IPv4 resolution pinned per connection, bounded timeouts, and no proxies or redirects.
Read retries are disabled by default and bounded by an explicit read-operation allowlist
when enabled. Authentication, mutations, API errors and schema failures are never replayed.
Sessions are held only in memory. Attachment downloads use the same bounded authenticated
transport; their inspection and MCP audit events never include binary contents.
Client and transport inspection redact state; callers must also avoid logging request bodies
or returned user records. Ruby memory is not a secure secret vault.

No Rails application is present; Brakeman does not apply.
