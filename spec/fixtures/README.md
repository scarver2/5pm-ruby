# Fixture provenance

`wsdl/` contains unmodified public demo WSDL/XSD documents fetched on 2026-10-28.
See docs/api-support.md for source URLs, hashes and inconsistencies.

All test JSON payloads, emails, passwords and session tokens are synthetic. They are
constructed from the documented types and are not captured live responses. In particular,
the auth.sessionId JSON envelope remains provisional. No account credentials were used.

`synthetic/` contains constructed response envelopes using the WSDL response part names
and XSD object/list fields. Lists use objects with `items`, `count`, and `total`.
These envelopes, scalar lexical forms and optional-field behavior are test assumptions,
not evidence of live server behavior. Unknown fields are included to test lossless mapping.
