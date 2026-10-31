# 5pm

Ruby SDK for 5pm API v2. MIT licensed; Ruby 3.2+.

Unreleased. Disposable-account verification covers account-specific contracts, JSON
envelopes, resource CRUD, pagination, attachments and the standalone MCP adapter.
See [live validation](docs/live-validation.md) for scope and reproducible checks.
Publication still requires review and explicit approval.

## Development

```sh
bundle install
bin/spec
bin/lint
bin/package-mcp
```

For repeatable macOS Keychain setup and cached contract/read checks, see
[cached validation](docs/cached-validation.md) (`bin/validate --help`).

## Configuration and initial API

Install from this checkout with Bundler (`gem "5pm", path: "/path/to/sdk"`).
The gem name is `5pm`; load it with `require "five_pm"` and use the `FivePM` namespace.
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
accepts `data.sessionId`, observed in the disposable test account, and the original
WSDL-shaped `auth.sessionId` envelope. Ambiguous envelopes are rejected; resource
response mapping is exercised by the live suite. Pagination and read retries are explicit opt-ins;
there is no date/time conversion. Caller-supplied
parameters retain wire names and values. Authentication refresh is synchronized with a
30-minute TTL and 30-second margin. Authentication HTTP failures invalidate the rejected session for the next explicit call without replay.
All calls use form-encoded HTTPS POST; redirects and environment proxies are disabled.
Response bodies stream into a bounded buffer (5 MiB by default, configurable with `max_response_bytes`).

See [API inventory](docs/api-support.md), [security policy](SECURITY.md),
[contributing](CONTRIBUTING.md), and [MCP follow-up plan](docs/mcp-plan.md).

## Typed responses (opt-in)

Both gems ship RBS signatures in `sig/`. Core signatures cover the client, resources,
models, pagination, downloads and errors; adapter signatures cover configuration,
approval proposals and audit events. Raw/typed configuration is selected at runtime,
so client/resource result types are unions; narrow a result to `FivePM::Response`
before using model readers. Unknown JSON fields remain recursive JSON values.
The MCP SDK boundary is a structural interface because that dependency has no RBS.
`bundle exec rake signatures` validates both sets, and package checks validate the
signatures extracted from the built artifacts. RBS is a development-only dependency.

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
Exception: `User.canViewProfiles` accepts both WSDL-declared strings and JSON booleans
observed in the test account; its reader preserves either representation unchanged.
Missing readers return nil; `key?` distinguishes missing fields from explicit null.
For responses with a `data` wrapper, `key?` recognizes mapped reader parts as well
as original keys; `raw.key?` checks only the wire envelope.
Malformed known types raise `FivePM::ProtocolError` without including field values;
these errors never trigger a replay of the request. Unknown fields are not validated.

Models and their JSON snapshots are immutable and do not freeze or mutate the caller's
input. `to_h`/`raw` return a frozen snapshot with original scalar values; typed readers
may return normalized values. Inspection omits all payloads, including unknown fields.
Serialization deliberately includes the complete payload, which can contain secrets.

Typed readers support both WSDL response part names and JSON `data` wrappers.
For example, `{"data":{"id":"7"}}` for getAuthorizedUser maps to `response.user`,
and a list operation's `data` maps to `response.list`. Scalar results, including false,
map to the operation's declared part. `to_h`/`raw`/`to_json` retain the original wire
envelope; raw client mode also stays unchanged. Ambiguous wrappers and error-marked
data wrappers raise `ProtocolError`. Users' optional top-level `sessionId` remains
separate from the list data. Pagination and MCP use the same envelope mapping.

The `data` wrapper is covered by synthetic regressions and live operation checks. List models continue to
require the XSD `items`/`count`/`total` structure; no singleton or flat-array conversion
is inferred.

## Bounded pagination, retries and attachments

`tasks`, `projects` and `activity` expose lazy `each_page` and `each_item` enumerators:

```ruby
client.tasks.each_item(filter: { projectId: 123 }, count: 100, max_pages: 20).take(150)
```

Enumerators request pages only as consumed, advance offset by received item count,
and stop on empty or short pages. They reject oversized/repeated pages, incompatible
`list.items` shapes and exhausted `max_pages` bounds rather than silently truncating.
They do not rely on totals, assume a stable dataset, or guarantee a consistent snapshot
while account data changes. Bounded offset pagination is exercised in live checks.

`read_retries: 0` (default) disables application retries. Set 1–3 to enable retries only
for the explicit read allowlist in `FivePM::RetryPolicy::READS`. Authentication sign-in,
all mutations and unknown operations are excluded, even after timeouts. Transient HTTP
429/500/502/503/504 and network errors use bounded jittered exponential backoff.
`max_retry_delay: 30` bounds each pause. Numeric Retry-After is honored; longer than
allowed delays, malformed values and HTTP-date headers are surfaced without retry.
There is no automatic replay after authentication or JSON/protocol failures.

HTTP errors expose numeric `status`; `RateLimitError` also exposes `retry_after` and
`retryable?`. `NotFoundError` and `ServerError` specialize `HTTPError`. Remote error
bodies are never included in exceptions. HTTP-200 numeric `code`/`message` error
envelopes raise `APIError` with numeric `code`, including code 0 validation failures.
Remote messages are discarded. These API errors never cause automatic retries.
Deletion `status` readers preserve nonnegative integer markers as well as booleans;
live project/task deletes return integer markers, whose meaning is not inferred.

`authentication.authorized_user`, `users.find_by_email(email)`, and activity's `files`,
`attach_files(activity_id:, files:)`, `delete_file(id)` and `download_file(id)` wrap
verified POST bindings. Attachments preserve the WSDL FileList representation.
Live upload verification uses `files: { "items" => [{ "name" => "example.txt",
"type" => "file", "content" => [bytes].pack("m0"), "size" => bytes.bytesize }] }`:
the caller supplies base64 content explicitly. Downloads return a `FivePM::Download`
in both response modes, with immutable binary `bytes`, optional `content_type`, and
redacted inspection. They use the authenticated POST endpoint, share the HTTP response
size limit, and never follow returned URLs. The live endpoint returns bytes despite
the JSON option. Missing-file API error envelopes are raised rather than returned as files.

User creation requires a symbolic `securityLevel` such as `"user"` in the tested
account, even though returned records use numeric strings and the help reference
lists numeric role codes. Request values are not silently translated.

Request validation rejects missing required operation parameters, unsafe nested field
names, arbitrary Ruby objects, cycles, invalid identifiers and invalid pagination bounds
before authentication or I/O. Typed records can be passed to create/update helpers using
their original JSON fields. Model list `to_h` retains the JSON view despite Enumerable.
Clients copy configuration strings and refuse Marshal serialization of credentials.

Run `bin/package` to verify the actual built artifact. See
[release preparation](docs/releasing.md) and [implementation guideposts](docs/implementation-guides.md).

## Remaining release gates

- Review and merge the offline-tested source; live API refreshes are optional and owner-controlled.
- Keep the supported Ruby matrix passing in hosted CI. Live checks remain opt-in and outside CI.
- Date/time strings remain opaque; no timezone conversion or consistent-snapshot guarantee is offered.
- Rate-limit and transient-network behavior is tested synthetically, without stressing the live account.
- Configure the protected `release` environment and both RubyGems trusted publishers
  using [release preparation](docs/releasing.md); verify name availability and obtain
  explicit approval for the version and exact commit before dispatching publication.

Official sources: [developer guide](https://www.5pmweb.com/5pm_api.php),
[API reference](https://www.5pmweb.com/help/api_docs.php).

## Standalone MCP adapter

The separate [5pm-mcp package](mcp/README.md) provides ten read tools over the
SDK using the official MCP Ruby SDK. Its executable is read-only; optional embedded
project/task mutation tools require trusted per-call operator approval. MCP is a
runtime dependency only of that separate gem. Run `bundle exec five-pm-mcp` with
the same injected environment variables, or see its README for host configuration.

`bin/package-mcp` verifies both installed artifacts and the adapter
protocol in an isolated temporary GEM_HOME. `bin/live-check` adds opt-in disposable
account verification; no gem publication is automated.
