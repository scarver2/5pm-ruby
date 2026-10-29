# five_pm-mcp

Separate MIT-licensed MCP adapter for `five_pm`, using the official MCP Ruby SDK.
Ruby 3.2+. The core SDK does not depend on MCP. This package is not yet published;
live API validation is deferred until a disposable account is available.

## Run from the checkout

From the repository root, run `bundle install`, inject `FIVE_PM_HOST`, `FIVE_PM_LOGIN`
and `FIVE_PM_PASSWORD`, then run `bundle exec five-pm-mcp`. A secret provider such as
Infisical may inject those variables into the process; the adapter has no dependency
on a specific secret manager. Do not put passwords into command-line arguments.

The executable uses stdio only. Stdout contains JSON-RPC messages; stderr contains
redacted JSON audit events. It closes the API session on normal exit. It performs no
API request just to list tools or negotiate the protocol. Tool calls create a session
as needed, so even read-only data access has temporary authentication-session effects.

For a host that supports the common `mcpServers` configuration structure:

```json
{
  "mcpServers": {
    "five-pm": {
      "command": "bundle",
      "args": ["exec", "five-pm-mcp"],
      "env": {"BUNDLE_GEMFILE": "/absolute/path/to/5pm-ruby/sdk/Gemfile"}
    }
  }
}
```

Start that host with the three 5pm variables already injected. Use its actual
configuration format if it differs. Rodeo/A1Web integrations can launch this standard
stdio server; no special integration or permission override is built into the SDK.

## Tools and limits

By default there are ten read tools: `five_pm_list_` and `five_pm_get_` followed by
each of `projects`, `tasks`, `activity`, `project_groups`, or `users`. Get tools accept
an integer `id`. List tools accept `offset` (default 0) and `limit` (default 20, max 100).
Tasks/projects/activity accept an allowlisted `filter` object using 5pm wire field
names. Unknown arguments, hostnames, credentials, session overrides and arbitrary
operation names are rejected before SDK dispatch.

List results contain `data.items` and `data.next_offset`. A non-null offset is a
candidate continuation; a subsequent request can return an empty page. Users and
project groups use upstream getAll, then slice the result locally. Those calls can
fetch more records than returned but remain subject to the SDK response-size limit.
Results do not guarantee a stable snapshot while account data changes.

Credential-like field names (password/session/token/secret/credential/API key/
authorization) and attachment `content` are removed recursively from tool results.
Account text, including links or apparent agent instructions, remains untrusted data.
No returned link is followed and no attachment is decoded or downloaded by the adapter.
Normal names, descriptions and user contact details are still sensitive account data;
configure a 5pm user with only the access that this host needs.

The stdio adapter caps incoming frames at 128 KiB; the core SDK caps decoded HTTP
response bodies at 5 MiB by default. Read retries stay disabled in the executable.

## Optional embedded mutation tools

The executable always remains read-only. A trusted embedding host may explicitly
construct `FivePM::MCPAdapter::Server` with `allow_mutations: true` and an `approver`
callback. This adds six tools: create/update/delete for projects and tasks. No user,
authentication, activity or attachment mutation tools are exposed.

```ruby
require "five_pm/mcp"
adapter = FivePM::MCPAdapter::Server.new(
  client: configured_client,
  allow_mutations: true,
  approver: lambda do |proposal|
    # Present proposal["tool"], proposal["arguments"] and proposal["request_id"]
    # to the human operator. Return true ONLY for that exact approved request.
    operator_ui.confirm(proposal)
  end,
  audit: ->(event) { audit_sink.write(event) }
)
adapter.open
```

The approval proposal and arguments are immutable snapshots. The executed arguments
are exactly that snapshot. Callback failure or any result other than true denies the
mutation; an agent cannot approve itself with an input boolean. There are no mutation
retries or cached approvals. The host owns UI presentation, operator authentication,
approval timeouts, and any stricter tenant/operation restrictions.

Audit events contain only timestamp, request ID, allowlisted tool name and outcome.
Rejected protocol/schema calls are audited without copying raw tool names or arguments.
Failures after mutation dispatch have outcome `uncertain`, since a response failure
cannot prove the server did not write data. A failed audit sink does not change a
completed API result or trigger replay; the embedding host must monitor its audit sink.

## Development and release

From the root: `bundle exec rake`, `bundle exec rubocop`, and
`bundle exec ruby bin/package-mcp`. The package check installs both built artifacts
into an isolated temporary GEM_HOME, then exercises the installed adapter protocol.
Tests include real stdio subprocesses backed by an explicitly synthetic transport,
mutation denial/approval, immutable proposals, error redaction and audit-sink failure.

Tracks [issue #4](https://github.com/scarver2/5pm-ruby/issues/4). Both packages remain
subject to account-specific WSDL/JSON verification and explicit publication approval.
