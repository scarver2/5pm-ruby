# Proposal: optional owner support in official RubyGems actions

Status: contribution proposal for Deputy review, not an implemented or submitted
upstream change. No token exchange or publication was executed.

## Verified implementation gap

The RubyGems server accepts an optional **string** `owner` in its existing
trusted-publisher exchange endpoint. All-digit strings resolve as immutable User
IDs; other strings resolve as handles. A missing ID must not fall back to a handle.
See the [pinned server controller](https://github.com/rubygems/rubygems.org/blob/5a641a1e1ac8bd37ba0b11d56b5d7ee379107f85/app/controllers/api/v1/oidc/trusted_publisher_controller.rb).

The inspected official credential action does not expose or transmit this input:

- [Released v2.1.0 action definition](https://github.com/rubygems/configure-rubygems-credentials/blob/dc5a8d8553e6ee01fc26761a49e99e733d17954a/action.yml).
- [Inspected main entrypoint](https://github.com/rubygems/configure-rubygems-credentials/blob/f5a32efa94076b80b28556b2d3b04cb3707b6df1/src/main.ts).
- [Inspected main exchange implementation](https://github.com/rubygems/configure-rubygems-credentials/blob/f5a32efa94076b80b28556b2d3b04cb3707b6df1/src/oidc/trustedPublisher.ts): request JSON is `{jwt: webIdentityToken}`.
- [Inspected upstream tests](https://github.com/rubygems/configure-rubygems-credentials/blob/f5a32efa94076b80b28556b2d3b04cb3707b6df1/__tests__/main.test.ts) mock the same JWT-only request with network disabled.

[release-gem v1.4.1/current v1](https://github.com/rubygems/release-gem/blob/7f9650160c1a4e7989fdc9855807bdbd421d8b6b/action.yml)
has no owner input and pins the released credential action above. No inspected
official released implementation supports the required path end to end. This is
not proof that every unpublished upstream branch has been examined.

## Minimal proposed upstream changes

For `rubygems/configure-rubygems-credentials`:

1. Add optional string input `owner`, with no default account. Explain immutable
   RubyGems account IDs for pending publishers; distinguish GitHub repository owner.
2. Read it with the action's normal input API. Before requesting credentials, reject
   nonempty owner with API-token mode, assume-role mode, or disabled trusted publishing.
3. Pass the optional string through the existing trusted-publishing function:

   ```typescript
   // Proposed changes to the existing upstream function, not a local exchanger.
   exchangeToken(audience, gemServer, owner || undefined)
   // Existing exchangeToken signature gains owner?: string.
   // Existing request body becomes:
   {jwt: webIdentityToken, ...(owner ? {owner} : {})}
   ```

4. Keep the value a string: no numeric conversion, default owner, handle fallback,
   extra endpoint, credential type or authentication flow. Let the server enforce
   ownership and publisher binding. Preserve the existing short-lived credential
   setup/masking behavior; do not add a permanent key or log JWTs/API keys.
5. Regenerate the shipped `dist/index.js` using upstream's prescribed build and
   include it in review. TypeScript-only changes do not update a runnable action.

For `rubygems/release-gem`, after credential-action support is merged/released:

1. Add optional string `owner` input, no default account.
2. Update its credential-action SHA to the verified owner-capable official revision.
3. Forward `owner: ${{ inputs.owner }}` to that existing official configure step.
4. Document the first-publication use and keep the existing release path intact.

## Required upstream offline tests

- Existing JWT-only request remains byte-for-byte compatible when owner is omitted.
- Owner `239830` produces JSON containing `owner: "239830"`, not a number.
- Owner passes from the action entrypoint through the existing exchange function.
- Incompatible modes fail before any ID-token request or credential configuration.
- HTTP failure is not treated as successful configuration; no credential is printed.
- Composite release action declares owner and forwards it to the verified configure pin.
- Run upstream tests with mocked OIDC/HTTP and network disabled; run its prescribed
  build/lint checks and verify bundled runtime parity. Never test by publishing.

## Review boundary

Deputy must approve before this proposal is submitted as an upstream contribution
or implemented. No fork, upstream PR/comment, runnable exchanger, authentication
experiment, token generation or publication was performed. Existing pending
publishers and 5PM release workflow remain unchanged.
