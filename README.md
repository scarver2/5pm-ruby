# five_pm

Ruby SDK for 5pm API v2. MIT licensed; Ruby 3.2+.

Early development: public demo WSDLs are inventoried, but account-specific contracts,
JSON response envelopes, and sandbox behavior still require verification. Do not deploy
this version to production. The gem name was absent from RubyGems on 2026-10-29; availability must be rechecked before publication.

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
observation. Pagination and read retries are explicit opt-ins; there is no date/time conversion. Caller-supplied
parameters retain wire names and values. Authentication refresh is synchronized with a
30-minute TTL and 30-second margin. Authentication HTTP failures invalidate the rejected session for the next explicit call without replay.
All calls use form-encoded HTTPS POST; redirects and environment proxies are disabled.
Response bodies stream into a bounded buffer (5 MiB by default, configurable with `max_response_bytes`).

See [API inventory](docs/api-support.md), [security policy](SECURITY.md),
[contributing](CONTRIBUTING.md), and [MCP follow-up plan](docs/mcp-plan.md).

## Typed responses (opt-in)

Pass `response_mode: :typed` to `FivePM::Client.new` to receive a `FivePM::Response`.
The default `:raw` mode keeps the original Hash/Array behavior. Both resource helpers
and generic calls honor the selected mode; `sign_in` still returns the client.

```ruby
client = FivePM::Client.new(
  host: ENV.fetch("FIVE_PM_HOST"), login: ENV.fetch("FIVE_PM_LOGIN"),
  password: ENV.fetch("FIVE_PM_PASSWORD"), response_mode: :typed
)
response = client.tasks.list(filter: { projectId: 123 }, count: 20)
response.list.each do |task| # FivePM::Models::TaskList is Enumerable
  puts [task.id, task.name, task.hours_done].inspect
end
response.list.count # server-provided page count, when present
response.list.total # server-provided total, when present
response.to_h       # original JSON envelope with original wire keys and values
response.to_json    # serializes the original JSON, including unknown fields
```

Models cover every complex response type in the public demo schema: projects, tasks,
users, project groups, activity, files, image metadata, authentication tokens, and lists.
Readers use snake_case (`project_id`, `first_name`); `[]` uses original wire keys
(`task["projectId"]`). Unknown fields remain available through `[]` and `to_h`.
Nested lists map their `items` to the appropriate model. `count` and `total` are
metadata, not automatic pagination or a guarantee of complete results.

Schema integers and finite floats accept JSON numbers or decimal strings. Schema
booleans accept JSON booleans, integer 0/1, and strings `false`/`true`/`0`/`1`.
String fields remain strings even if they look numeric or boolean. All date/time
fields remain exact strings; no zone is inferred and no date parsing is attempted.
Missing readers return nil; `key?` distinguishes missing fields from explicit null.
Malformed known types raise `FivePM::ProtocolError` without including field values;
these errors never trigger a replay of the request. Unknown fields are not validated.

Models and their JSON snapshots are immutable and do not freeze or mutate the caller's
input. `to_h`/`raw` return a frozen snapshot with original scalar values; typed readers
may return normalized values. Inspection omits all payloads, including unknown fields.
Serialization deliberately includes the complete payload, which can contain secrets.

The synthetic fixtures assume WSDL response part names form a JSON envelope and XSD
lists use `items`/`count`/`total`. This is provisional until live validation. Typed mode
rejects incompatible shapes rather than guessing envelope or singleton-list variants.

## Bounded pagination, retries and attachments

`tasks`, `projects` and `activity` expose lazy `each_page` and `each_item` enumerators:

```ruby
client.tasks.each_item(filter: { projectId: 123 }, count: 100, max_pages: 20).take(150)
```

Enumerators request pages only as consumed, advance offset by received item count,
and stop on empty or short pages. They reject oversized/repeated pages, incompatible
`list.items` shapes and exhausted `max_pages` bounds rather than silently truncating.
They do not rely on totals, assume a stable dataset, or guarantee a consistent snapshot
while account data changes. Offset semantics still need live validation.

`read_retries: 0` (default) disables application retries. Set 1–3 to enable retries only
for the explicit read allowlist in `FivePM::RetryPolicy::READS`. Authentication sign-in,
all mutations and unknown operations are excluded, even after timeouts. Transient HTTP
429/500/502/503/504 and network errors use bounded jittered exponential backoff.
`max_retry_delay: 30` bounds each pause. Numeric Retry-After is honored; longer than
allowed delays, malformed values and HTTP-date headers are surfaced without retry.
There is no automatic replay after authentication or JSON/protocol failures.

HTTP errors expose numeric `status`; `RateLimitError` also exposes `retry_after` and
`retryable?`. `NotFoundError` and `ServerError` specialize `HTTPError`. Remote error
bodies are never included in exceptions. HTTP-200 API error envelopes remain unverified.

`authentication.authorized_user`, `users.find_by_email(email)`, and activity's `files`,
`attach_files(activity_id:, files:)`, `delete_file(id)` and `download_file(id)` wrap
verified POST bindings. Attachments preserve the WSDL FileList object representation;
no binary encoding is inferred and returned URLs are never followed. Downloads request
JSON (`stream: false`). Confirm upload/download content semantics in the test tenant.

Request validation rejects missing required operation parameters, unsafe nested field
names, arbitrary Ruby objects, cycles, invalid identifiers and invalid pagination bounds
before authentication or I/O. Typed records can be passed to create/update helpers using
their original JSON fields. Model list `to_h` retains the JSON view despite Enumerable.
Clients copy configuration strings and refuse Marshal serialization of credentials.

Run `bundle exec ruby bin/package` to verify the actual built artifact. See
[release preparation](docs/releasing.md) and [implementation guideposts](docs/implementation-guides.md).

## Remaining release gates

- Compare all contracts with a disposable account's WSDL and schema.
- Record sanitized success and error JSON responses and verify authentication parsing.
- Confirm typed response envelopes and safe automatic pagination against observed contracts.
- Verify attachments, timezone behavior and rate-limit errors before exposing helpers.
- Run opt-in sandbox tests and supported Ruby matrix in CI.
- Verify RubyGems name availability and obtain explicit publication approval.

Official sources: [developer guide](https://www.5pmweb.com/5pm_api.php),
[API reference](https://www.5pmweb.com/help/api_docs.php).
