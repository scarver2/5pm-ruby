<!-- docs/proposals/rubygems-owner-oidc.md -->
# Owner-aware RubyGems trusted publishing: disposition

Status: closed proposal. No workflow change is needed or planned.

## Background

Before the first release, both gems had only *pending* trusted publishers. Pushing a
new gem through a pending publisher needs the RubyGems account `owner` in the OIDC
token exchange. The RubyGems server already accepted it, but the official actions
pinned here could not send it. A proposal (PR #16, October 2026) planned an upstream
contribution and a guarded adoption with owner `239830` for both gems.

## What happened instead

- Stan published 0.1.0 of both gems manually on 2026-10-30. Both names now exist,
  and each has a configured (not pending) trusted publisher bound to
  `scarver2/5pm-ruby`, workflow `release.yml`, environment `release`.
- 0.2.0 was published on 2026-11-24 by the protected release workflow through
  trusted publishing, using the pinned
  [`rubygems/release-gem@7f96501`](https://github.com/rubygems/release-gem/blob/7f9650160c1a4e7989fdc9855807bdbd421d8b6b/action.yml)
  (v1.4.1), without any owner input.
- Upstream added the input independently:
  [release-gem v1.5.0](https://github.com/rubygems/release-gem/releases/tag/v1.5.0)
  (commit `2654a0fe0dc39725c07fe84d7fe863a084f2424e`, via
  [rubygems/release-gem#51](https://github.com/rubygems/release-gem/pull/51)) forwards
  `owner` to
  [configure-rubygems-credentials v2.2.0](https://github.com/rubygems/configure-rubygems-credentials/releases/tag/v2.2.0).
  Upstream documents it as only required when pushing a new gem via a pending
  trusted publisher.

No upstream contribution was submitted from this repository.

## Guidance

- Do not add `owner` to either publication job; both gems use configured publishers.
- When the `release-gem` pin moves (for example to v1.5.0), update
  `spec/fixtures/release_action_inputs.json` from that exact revision's `action.yml`.
  The workflow spec fails if a job passes an input the pinned revision does not
  declare, or passes `owner`.
- A future *new* gem from this repository would need a pending publisher and the
  `owner` input, at release-gem v1.5.0 or newer.

—
Stan Carver II
Made in Texas 🤠
https://stancarver.com
