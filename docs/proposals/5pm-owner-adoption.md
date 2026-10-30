# Read-only adoption plan: owner-aware RubyGems publishing

Status: blocked implementation proposal for Deputy, not publishing authorization.
See the [upstream contribution proposal](rubygems-owner-upstream.md).

## Owner configuration observed

Sheriff's screenshot shows both pending publishers correctly bound to:

| Gem | GitHub repository | Workflow | Environment | RubyGems owner ID |
| --- | --- | --- | --- | --- |
| `5pm` | `scarver2/5pm-ruby` | `release.yml` | `release` | `239830` |
| `5pm-mcp` | `scarver2/5pm-ruby` | `release.yml` | `release` | `239830` |

The immutable owner ID is public configuration, not a secret. The screenshot says
valid for about 12 hours; it does not establish an absolute deadline. Leave entries
alone now. Refresh expired pending publishers only when gates are ready and owner
authorization permits; do not publish merely to beat expiration.

## Adoption prerequisites and exact future change

1. Obtain an upstream-accepted official implementation supporting the owner input.
   Inspect its action definition, caller, HTTP request body and shipped runtime.
2. Verify `release-gem` forwards owner to an owner-capable pinned credential action.
   Record both immutable SHAs and upstream releases/review evidence. Neither current
   pin qualifies; an invented input or unreviewed fork is not an alternative.
3. Prepare a separate focused executable-workflow PR. In BOTH publication jobs,
   replace only the action pin with the verified official revision and pass the
   string owner input. Preserve MCP's existing `working-directory: mcp` setting.
   The intended inputs are `owner: "239830"` for core and the same owner plus
   `working-directory: mcp` for MCP. There is intentionally no placeholder `uses`
   command here that could be copied into an executable workflow.
4. Update the reviewed action-input snapshot and add regression assertions that BOTH
   jobs pass the exact owner string to the supported pin. Verify forwarding in the
   official bundled implementation; a YAML-only assertion is insufficient.
5. Run the normal four-version PR CI (tests, RBS, lint and isolated packaging).
   Request exact-head review before merging. CI must not exchange real tokens or
   dispatch the publishing workflow as a connection test.

## Protections that must remain

- Manual dispatch only from master for explicitly approved version/full commit.
- Required approval in protected `release` environment; no administrator bypass.
- Separate contents-write tag job and contents-read/id-token-write publishing jobs.
- Exact-source qualification, matching package versions, dated changelog, immutable tags.
- No permanent credentials, local exchanger, token logs, publisher changes or publication.

## Separate unresolved release gates

PR #13 records failed standard-User qualification against source
`9322e03f75604d7279775dc88c9192add840e76e`: User update returned API code 8, one
labelled test User remains, and attachments were not qualified. Owner cleanup and
independent read-only absence verification remain required; do not repeat that User
mutation. Issue #14 owns deferred investigation. This owner proposal does not resolve
those facts, accept a release candidate, or relax the exact-source evidence gate.
Protected GitHub environment verification, dated changelog, actual successful
candidate evidence and separate publication authorization also remain outstanding.
