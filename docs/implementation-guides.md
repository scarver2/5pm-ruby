# Implementation guideposts

Reviewed these user-owned repositories as design guides, without importing their
service-specific behavior or adding their dependencies to the SDK:

- [printavo-ruby client](https://github.com/scarver2/printavo-ruby/blob/464ae6f29b8ff7627cf829c02351d1b9eadea37d/lib/printavo/client.rb): independent clients, resource helpers, explicit configuration.
- [printavo-ruby connection](https://github.com/scarver2/printavo-ruby/blob/464ae6f29b8ff7627cf829c02351d1b9eadea37d/lib/printavo/connection.rb): configurable retry controls; FivePM restricts retries further to an explicit read-operation allowlist.
- [abbu packaging](https://github.com/scarver2/abbu/blob/4c64d0eb0ccdbc0a8c04b2e50da92594faf75d09/bin/package): verify the built artifact independently of its source checkout.
- [abbu release preflight](https://github.com/scarver2/abbu/blob/4c64d0eb0ccdbc0a8c04b2e50da92594faf75d09/bin/release-check): inspect accepted commits without executing candidate code; separate preparation from publication authorization.
- [abbu MCP adapter](https://github.com/scarver2/abbu/blob/4c64d0eb0ccdbc0a8c04b2e50da92594faf75d09/lib/abbu/mcp/server.rb): use the official SDK for protocol handling, allowlist tools and redact errors.

The public 5pm WSDL/XSD remains the source for 5pm-specific operations and types.
