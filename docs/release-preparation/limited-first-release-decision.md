# Historical limited-release proposal — NOT APPROVED

This proposal predates Stan's owner-controlled live-validation policy. It does not
impose a current live qualification gate. No API exclusions below are implemented.
See [current release policy](../releasing.md). The original proposal follows.

Default recommendation: HOLD until current qualification gates pass. If Sheriff and
Deputy instead want an intentionally limited first release, review this as a separate
scope/policy proposal before code or gate changes:

- Exclude User mutations (`users.add`, `users.update`, `users.remove`) and unqualified
  attachment transfers/removal (`activity.attachFiles`, `activity.downloadFile`,
  `activity.removeFile`) from the supported first-release surface. User reads and
  attachment metadata reads can remain only where already verified.
- Require explicit consumer warnings in README, API support matrix and changelog,
  plus enforcement preventing excluded calls from being presented as supported.
  Current provisional artifacts expose the existing full API; they are NOT artifacts
  of this hypothetical limited release.
- Precisely revise the release evidence policy to a reviewed, version-specific
  supported-operation inventory, with unsupported operations recorded as excluded,
  not PASS. Continue requiring clean actual-source contract/read/supported-write
  evidence and complete cleanup. Do not simply set three verification flags true.
- Rationale: release verified core project/task/activity functionality while deferring
  unqualified User/attachment capabilities. Risk: a narrower SDK/support contract and
  future compatibility changes. This does not resolve or erase issue #14.
- Approval requires explicit Sheriff policy authorization and independent Deputy
  review of a separate PR. Rebuild/requalify that actual new source and accept new
  hashes. No such policy/source changes are included here.
