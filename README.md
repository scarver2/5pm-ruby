# five_pm

Ruby SDK for 5pm API v2. MIT licensed; Ruby 3.2+.

Early development: public demo WSDLs are inventoried, but account-specific contracts,
JSON response envelopes, and sandbox behavior still require verification. Do not deploy
this version to production. Gem name availability has not been checked for publication.

## Development

```sh
bundle install
bundle exec rake
bundle exec rubocop
gem build five_pm.gemspec --strict
```

## Configuration and initial API

Install from this checkout with Bundler (`gem "five_pm", path: "/path/to/sdk"`).
Provide `FIVE_PM_HOST`, `FIVE_PM_LOGIN`, and `FIVE_PM_PASSWORD` through your environment
or a secret manager such as Infisical; no dotenv file is needed.

```ruby
require "five_pm"
client = FivePM::Client.new(
  host: ENV.fetch("FIVE_PM_HOST"), # account.5pmweb.com, without scheme or path
  login: ENV.fetch("FIVE_PM_LOGIN"),
  password: ENV.fetch("FIVE_PM_PASSWORD"),
  open_timeout: 5, read_timeout: 30, write_timeout: 30
)
response = client.tasks.list(filter: { projectId: 123 }, offset: 0, count: 20)
# Explicit mutations, for a disposable account only:
# client.tasks.create(name: "Example task", projectId: 123)
# client.tasks.update(id: 456, name: "Updated task")
# client.tasks.get(456)
# client.tasks.delete(456)
# Exact wire operations are also available:
# client.users.call("getByEmail", email: "person@example.com")
client.sign_out
```

Services: `authentication`, `projects`, `project_groups`, `tasks`, `activity`, `users`.
CRUD resources expose `create`, `update`, `get`, `delete`, and `list`. For users and
project groups, `list` uses `getAll` and rejects unsupported filtering/pagination options.
Filters and other wire options retain their documented camelCase names.

Responses retain their full JSON structure and unknown fields. The initial sign-in parser
expects `auth.sessionId` from the WSDL; that JSON envelope is provisional pending sandbox
observation. There is no automatic pagination, retry, or date/time conversion. Caller-supplied
parameters retain wire names and values. Authentication refresh is synchronized with a
30-minute TTL and 30-second margin. Authentication HTTP failures are reported without replay.
All calls use form-encoded HTTPS POST; redirects and environment proxies are disabled.

See [API inventory](docs/api-support.md), [security policy](SECURITY.md),
[contributing](CONTRIBUTING.md), and [MCP follow-up plan](docs/mcp-plan.md).

## Remaining release gates

- Compare all contracts with a disposable account's WSDL and schema.
- Record sanitized success and error JSON responses and verify authentication parsing.
- Add typed response models and safe automatic pagination from observed contracts.
- Verify attachments, timezone behavior and rate-limit errors before exposing helpers.
- Run opt-in sandbox tests and supported Ruby matrix in CI.
- Verify RubyGems name availability and obtain explicit publication approval.

Official sources: [developer guide](https://www.5pmweb.com/5pm_api.php),
[API reference](https://www.5pmweb.com/help/api_docs.php).
