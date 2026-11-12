# X1Kit

Swift package that drives a Flextight X1: transport, protocol, preview
sequence and image decoding. No user interface. Design decisions:
[`docs/decisions.md`](../docs/decisions.md).

- `X1Transport`:
  - `SCSITransport`, the protocol both transports implement;
  - `IOKitTransport`, the real scanner, **read-only by default**;
  - `SimulatedX1`, a replay of `tests/fixtures` (accepts an early `DB`
    stop after SCAN);
  - `CommandPolicy`, the read-only guard.
- `X1Protocol`: `X1Command` (CDB builders) and response parsers
  (`InquiryResponse`, `ScanStatusPage`, `IdentityPage`, `UsageLog`,
  `ScannerState`).
- `X1Preview`: `PreviewScript.flexColor4813` (the captured sequence) and
  `PreviewRunner` (waits on 0xDF, stops at the first anomaly, stop sequence
  after SCAN; optional `PreviewEvent` progress reports).
- `X1Image`: `FlatFieldReference`, `LineGap`, `PreviewDecoding`,
  `IncrementalPreviewDecoder` (same result, block by block),
  `PreviewGeometry` (pixel aspect, display only), `TIFFWriter` (16-bit RGB,
  linear, no profile).

## Tests

    cd X1Kit
    swift test

The tests run against `SimulatedX1` and read `../tests/fixtures` in place.
They never open a real scanner.
