<!-- docs/cached-validation.md -->
# Keychain and cached validation

Run these commands from the checkout on macOS. The setup prompts for the disposable
tenant's hostname (without scheme/path), standard User login, and password. Each is
stored in the login Keychain under `5pm-ruby.validation.host`, `.login`, or `.password`,
with account `5pm-ruby`. Keychain may ask for access permission. Values never appear
in command arguments, repository files, output, or the cached report.

```sh
bin/validate --setup
```

Commit the reviewed source changes before validating. On the first run, explicitly
designate the tenant as disposable. This runs the existing read-only live harness,
including WSDL/XSD contract checks and session cleanup. It does not run CRUD tests.

```sh
bin/validate --disposable
```

Later runs reuse the cached evidence without Keychain access or network requests.
There is no timer, polling, expiration, or automatic refresh:

```sh
bin/validate
```

After a known 5PM API update, deliberately replace the cache:

```sh
bin/validate --refresh --disposable
```

Changes to SDK code, adapter code, bin commands or validation helpers invalidate the
local fingerprint. The command refuses stale evidence until an explicit refresh;
it does not silently send another request. Failed refreshes preserve the previous
file, but stale files remain unusable. Updating credentials does not refresh evidence.
Use a distinct `--service NAME` per tenant; that also selects a separate default cache.

The default cache is `~/Library/Caches/5pm-ruby/<service-sha256>.json`, outside the
repository, with mode 0600. `--cache FILE` selects a different local destination.
It stores only the validation timestamp, tested commit, source fingerprint and scope.
It excludes remote responses, tenant details, tokens, credentials and record IDs.

Cached contract/read evidence has `release_evidence: false` and
`mutations_verified: false`. It is reusable development evidence, not fabricated
full release qualification. The existing exact-source release gate is unchanged;
changing that policy requires a separate explicit release-policy decision.

See [live validation](live-validation.md) and [release preparation](releasing.md).

—
Stan Carver II
Made in Texas 🤠
https://stancarver.com
