<!-- docs/release-preparation/manual-first-publication.md -->
# Completed first publication: 0.1.0

Both gems were published on 2026-10-30 using the owner's existing RubyGems
credentials and security-key approvals. The core gem was published first, its
public bytes verified, and then the MCP adapter was published and verified.

| Package | Published version |
| --- | --- |
| Core SDK | [5pm 0.1.0](https://rubygems.org/gems/5pm/versions/0.1.0) |
| MCP adapter | [5pm-mcp 0.1.0](https://rubygems.org/gems/5pm-mcp/versions/0.1.0) |

Source commit: `0a48bcd297a28e0ee7c22be8bc594daad4a88511`.
Tag: [`v0.1.0`](https://github.com/scarver2/5pm-ruby/releases/tag/v0.1.0).
The GitHub release contains both gems and `SHA256SUMS`.

## Installation

```sh
mise exec -- gem install 5pm --version 0.1.0
# For the MCP server, this also installs the core SDK:
mise exec -- gem install 5pm-mcp --version 0.1.0
```

For a Bundler application, add the package you need:

```ruby
gem "5pm", "~> 0.1.0"
# Or for MCP applications:
# gem "5pm-mcp", "~> 0.1.0"
```

Run `mise exec -- bundle install`. Require `five_pm` for the SDK or `five_pm/mcp`
for the adapter. The standalone executable is `mise exec -- five-pm-mcp`.
Both gems support Ruby 3.2+.

## Final artifact verification

| Artifact | SHA-256 |
| --- | --- |
| `5pm-0.1.0.gem` | `eb2398a8f1c47744a64c0cc1966239af8102970c938165286103019914d30388` |
| `5pm-mcp-0.1.0.gem` | `db8bd3b842fb1f74337a3037623944e82ed8d0ac3963344297517fe68d703592` |

Both downloaded RubyGems artifacts matched these final builds byte for byte. A fresh
isolated install of `5pm-mcp` resolved both public packages and their dependencies;
requiring each package loaded version 0.1.0 from that isolated installation.
Validation passed 149 specs, 98.19% coverage, RuboCop, RBS, isolated package checks
and hosted CI on Ruby 3.2, 3.3, 3.4 and 4.0.

## Historical preparation and future releases

The [original provisional manifest](0.1.0-manual-artifacts.json) records an earlier
source commit and different hashes. It is preserved as historical preparation
evidence, not the manifest for the published bytes. Its old live-test blockers were
superseded by the owner's policy decision. Stan confirmed the test User was deleted.
No new live check was claimed or needed for publication.

Live API refreshes are optional and owner-controlled. An active trial/subscription,
credentials, or fresh live evidence are not release requirements. See
[cached validation](../cached-validation.md).

Do not push 0.1.0 again or move its tag. For a future version, follow the
[current release guide](../releasing.md), rebuild from its accepted source, and
verify the exact artifact hashes before and after publication. Future protected
workflow publishing requires separate configuration of the GitHub environment and
trusted publishers on both existing RubyGems packages.

—
Stan Carver II
Made in Texas 🤠
https://stancarver.com
