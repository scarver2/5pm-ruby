# Sheriff-only manual first-publication preparation

**Preparation only. Publication requires Stan's approval of the final source and
exact artifact hashes.** Live API checks are optional at Stan's discretion. No
active 5PM trial or subscription is required. The [release policy](../releasing.md)
supersedes the historical live-test blockers recorded in the frozen manifest.

## Frozen proposed source and artifacts

Proposed version: **0.1.0** for both gems. Frozen source baseline:
`9322e03f75604d7279775dc88c9192add840e76e` (accepted master, not an accepted release).
Changelog: **0.1.0 — unreleased**. Current artifacts are provisional and blocked.
A dated changelog/source change requires rebuilding, offline verification and new hashes;
do not publish these bytes after substituting a different candidate SHA.

[Machine-readable provenance/inventories](0.1.0-manual-artifacts.json) records:

| Artifact | SHA-256 |
| --- | --- |
| `5pm-0.1.0.gem` | `160b09db75dd1cf0aebac21e64f0f6a1216ea437c3155816481a1c7f0faff0e6` |
| `5pm-mcp-0.1.0.gem` | `8ac7c8a5dc175b7ecd4d934b3c720ee3d4b0f019deacd3c5e94d249a3e22d601` |

Build environment: Ruby 4.0.9, RubyGems 4.0.23, Bundler 4.0.23,
`SOURCE_DATE_EPOCH=1793399403` (source commit timestamp). Two independent builds
produced identical bytes. Core inventory: 28 files; MCP: eight. MIT licenses, RBS,
installed load paths and both exact versions passed isolated verification.

Both gems require Ruby >=3.2. Supported/tested versions: 3.2, 3.3, 3.4, 4.0.
[Source CI run 41138526407](https://github.com/scarver2/5pm-ruby/actions/runs/41138526407)
passed all four jobs (143 examples, RBS/runtime, lint and package verification).
Core depends on json >=2.6,<4 and net-http >=0.3,<1; MCP depends on 5pm ~>0.1.0
and mcp ~>1.6.1. The locked dependency set is tested, not every possible version
within these ranges. MCP is not a core runtime dependency.

## Offline build, inspect and install (no publishing credentials)

Use a clean worktree of the exact candidate with locked dependencies installed.
The prepared local worktree is `/private/tmp/5pm-maiden-voyage-0.1.0/source`.
The public source can be reproduced as follows; do not overwrite an existing worktree:

```sh
set -eu
cd /Users/cora/Projects/OSS/5pm-ruby/sdk
candidate_sha=9322e03f75604d7279775dc88c9192add840e76e
source_dir=/private/tmp/5pm-maiden-voyage-0.1.0/source
# Already executed for the prepared worktree; only create if absent:
# git worktree add --detach "$source_dir" "$candidate_sha"
cd "$source_dir"
test "$(git rev-parse HEAD)" = "$candidate_sha"
test -z "$(git status --porcelain)"
export PATH=/Users/cora/.local/share/mise/installs/ruby/4.0.9/bin:$PATH
export BUNDLE_PATH=/Users/cora/Projects/OSS/5pm-ruby/sdk/vendor/bundle
export BUNDLE_FROZEN=true
export SOURCE_DATE_EPOCH=1793399403
bundle check
bin/spec
bin/lint --cache false
bin/package-mcp
# bin/package-mcp builds/inspects both gems and verifies disposable installs/RBS.
ruby bin/verify-package.rb pkg/5pm-0.1.0.gem
shasum -a 256 pkg/5pm-0.1.0.gem mcp/pkg/5pm-mcp-0.1.0.gem
```

Explicit standalone isolated-install/load commands, using only bundled dependencies:

```sh
set -eu
qualification_home="$(mktemp -d /private/tmp/5pm-install.XXXXXX)"
trap 'rm -rf -- "$qualification_home"' EXIT
dependency_path="$(bundle exec ruby -rbundler -e 'puts Bundler.load.specs.map(&:base_dir).uniq.join(File::PATH_SEPARATOR)')"
for artifact in pkg/5pm-0.1.0.gem mcp/pkg/5pm-mcp-0.1.0.gem; do
  GEM_HOME="$qualification_home" GEM_PATH="$dependency_path" ruby -rrubygems/installer -e \
    'Gem::Installer.at(ARGV.fetch(0), install_dir: ARGV.fetch(1), ignore_dependencies: true, document: []).install' \
    "$artifact" "$qualification_home"
done
GEM_HOME="$qualification_home" GEM_PATH="$dependency_path" ruby -rrubygems -e '
  gem "5pm", "0.1.0"; require "five_pm"
  gem "5pm-mcp", "0.1.0"; require "five_pm/mcp"
  abort "core version mismatch" unless FivePM::VERSION == "0.1.0"
  abort "MCP version mismatch" unless FivePM::MCPAdapter::VERSION == "0.1.0"
  %w[5pm 5pm-mcp].each do |name|
    actual = File.realpath(Gem.loaded_specs.fetch(name).full_gem_path)
    abort "loaded outside disposable GEM_HOME" unless actual.start_with?(File.realpath(ENV.fetch("GEM_HOME")) + File::SEPARATOR)
  end
  puts "Both exact versions loaded from disposable GEM_HOME"
'
```

No dependency downloads occur during these installs. The prepared artifact directory
is `/private/tmp/5pm-maiden-voyage-0.1.0/artifacts`, with the two gems, `SHA256SUMS`
and `provenance.json`. It is outside Git and outside the frozen source tree.
Verify it with `cd` to that directory, then `shasum -a 256 -c SHA256SUMS`.

## Preconditions before any push

- Preserve historical API observations and failed receipts, including issue #14.
  Cleanup of trial records can be handled separately by the owner; another live
  session or qualification run is not a publication prerequisite.
- Review a dated changelog and final exact source. Pass offline specs, lint, package
  checks, hosted CI and the read-only `bin/release-check VERSION SHA`.
- Deputy accepts exact artifacts/source; Sheriff separately authorizes the final push.
- Sheriff verifies his own existing local RubyGems authentication belongs to the
  intended account (immutable ID 239830), permits `push_rubygem`/first publication of
  both names and meets MFA requirements. Cora neither accesses nor uses it.
- If existing authentication is missing/insufficient, STOP for owner action. Do not
  run signin, generate credentials automatically, add repository secrets, print keys,
  or pass credentials/MFA codes as command-line arguments. No new permanent key is
  part of this procedure. An authenticated browser alone is not CLI authentication.

Read-only public gem and owner API requests returned 404 for both names on 2026-10-30.
No published ownership was observed; this neither reserves names nor proves manual
push permission. Recheck immediately before publication. Any newly existing gem,
version conflict, different owner or policy denial means STOP; do not overwrite/yank.

Manual `gem push` uses Sheriff's own authenticated account, not OIDC token exchange.
Thus owner-input action support is a later automation prerequisite, not a reason to
alter this manual route. Leave the protected OIDC workflow and pending publishers
unchanged. This distinction does not waive source/evidence/publication approval.

## Sheriff-only stage — DO NOT EXECUTE NOW

The following is a reviewed command specification, not a runnable automation added
to the repository. Execute only after every precondition above and exact artifact
acceptance. The frozen candidate has an undated changelog and is not a final release candidate.
If candidate bytes/SHA change, replace the reviewed manifest/hashes only through new
acceptance; do not edit these values to force an existing approval to match.

Run personally in Sheriff's local terminal with shell tracing/recording disabled.
Use existing local CLI credentials; no API keys, passwords or MFA codes go in chat,
logs, repository configuration, or agent input. Consult [RubyGems CLI](https://guides.rubygems.org/command-reference/#gem-push),
[scopes](https://guides.rubygems.org/api-key-scopes/) and
[MFA](https://guides.rubygems.org/using-mfa-in-command-line/).

```sh
bash <<'SHERIFF_ONLY'
set -euo pipefail
unset GEM_HOST_API_KEY RUBYGEMS_API_KEY BUNDLE_GEM__PUSH_KEY GEM_HOST_OTP_CODE
# Set these in your terminal from the final reviewed acceptance packet.
: "${SOURCE_DIR:?Set SOURCE_DIR to your clean local source worktree}"
: "${ARTIFACT_DIR:?Set ARTIFACT_DIR to the final accepted artifact directory}"
: "${CANDIDATE_SHA:?Set CANDIDATE_SHA to the final accepted full commit}"
: "${CORE_SHA256:?Set CORE_SHA256 to the independently accepted core digest}"
: "${MCP_SHA256:?Set MCP_SHA256 to the independently accepted MCP digest}"
source_dir="$(cd "$SOURCE_DIR" && pwd -P)"
artifact_dir="$(cd "$ARTIFACT_DIR" && pwd -P)"
candidate_sha="$CANDIDATE_SHA"
[[ "$CORE_SHA256" =~ ^[0-9a-f]{64}$ && "$MCP_SHA256" =~ ^[0-9a-f]{64}$ ]]
cd "$source_dir"
test "$(git rev-parse HEAD)" = "$candidate_sha"
mise exec -- bin/release-check 0.1.0 "$candidate_sha"  # Never bypass.
# Guard against automatic credential issuance when local authentication is absent.
# This reads only inside Sheriff's local process and prints no key.
mise exec -- ruby -rrubygems/config_file -e 'abort "STOP: existing local RubyGems authentication required" if Gem.configuration.rubygems_api_key.to_s.empty?'
cd "$artifact_dir"
# Digests must come from the independent acceptance packet, not this directory.
printf '%s  %s\n' "$CORE_SHA256" '5pm-0.1.0.gem' \
  "$MCP_SHA256" '5pm-mcp-0.1.0.gem' | shasum -a 256 -c -
# Core first. These commands are not authorized until final acceptance/push approval.
mise exec -- gem push --host https://rubygems.org "$artifact_dir/5pm-0.1.0.gem" </dev/tty
verification_dir="$(mktemp -d)"
trap 'rm -rf -- "$verification_dir"' EXIT
cd "$verification_dir"
mise exec -- gem fetch 5pm --version 0.1.0 --clear-sources --source https://rubygems.org
cmp "$artifact_dir/5pm-0.1.0.gem" 5pm-0.1.0.gem
# Only after the exact core artifact is publicly available:
mise exec -- gem push --host https://rubygems.org "$artifact_dir/5pm-mcp-0.1.0.gem" </dev/tty
mise exec -- gem fetch 5pm-mcp --version 0.1.0 --clear-sources --source https://rubygems.org
cmp "$artifact_dir/5pm-mcp-0.1.0.gem" 5pm-mcp-0.1.0.gem
SHERIFF_ONLY
```

If propagation delays a fetch, STOP and retry only the read-only fetch/compare once
availability is confirmed; do not repeat an already successful push. Verify account
ownership on RubyGems after publication. No automatic retries, yanks, tags or GitHub
release dispatches are included. No push commands above were executed by Cora.

## Historical proposals and current preparation

The [limited-release proposal](limited-first-release-decision.md) and the frozen
manifest are historical records, not current live-test requirements. Stan has
removed the live API release gate; no fresh success report is required or fabricated.
API observations remain documented without changing the supported API implicitly.

The historical hashes above remain provisional. After the final source is dated,
reviewed and offline-tested, rebuild both gems, independently accept their new
hashes, and provide those values through exported environment variables to the
owner-only procedure. Keep credentials outside these variables and the repository.

—
Stan Carver II
Made in Texas 🤠
https://stancarver.com
