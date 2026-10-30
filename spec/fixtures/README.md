# Fixture provenance

`wsdl/` contains unmodified public demo WSDL/XSD documents fetched on 2026-10-28.
See docs/api-support.md for source URLs, hashes and inconsistencies.

Synthetic JSON payloads, emails, passwords and session tokens are constructed from
contracts. The original WSDL-shaped envelopes remain compatibility fixtures.

`observed/` contains sanitized minimal reconstructions of response shapes observed
in a disposable account on 2026-10-30. IDs and names are replaced with synthetic values,
all token values are replaced, error messages are discarded, and unrelated account
fields are omitted. Integer deletion markers are replaced with a synthetic positive
integer without assigning meaning to that value. These fixtures reproduce contract
differences without retaining raw account payloads or credentials.

`synthetic/` contains constructed response envelopes using the WSDL response part names
and XSD object/list fields. Lists use objects with `items`, `count`, and `total`.
These envelopes, scalar lexical forms and optional-field behavior are test assumptions,
not evidence of live server behavior. Unknown fields are included to test lossless mapping.
