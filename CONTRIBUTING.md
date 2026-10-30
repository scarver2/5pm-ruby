# Contributing

Use Ruby 3.2 or newer. Run `bundle install`, `bundle exec rake`, and `bundle exec rubocop`.
Build with `gem build 5pm.gemspec --strict`.

Fixtures contain public WSDL/XSD contracts, not production data. Never commit credentials,
session IDs or account payloads. New operation mappings need WSDL and reference evidence.
Network tests must use a disposable tenant, be explicitly enabled, and never run in CI.
Do not publish a gem without explicit maintainer approval.
