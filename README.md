# Automaatkorrektor

## macOS v0.1 compatibility

The client supports explicit selections in TextEdit and in standard Safari or
Chrome text, search, and textarea fields when macOS exposes the focused control
as a standard editable Accessibility text field. It does not claim support for
other applications or arbitrary browser editors.

Password fields, web-area or document selections, `contenteditable` surfaces,
custom controls, and fields that do not pass the closed Accessibility
eligibility policy are rejected before selected text is read. The client does
not use the clipboard, traverse application content trees, or fall back to
private text-marker APIs.

## Release evidence

The v0.1 release gate has exactly 29 required checks. Run the automated checks
and create a metadata-only report with:

```sh
scripts/release-gate.sh
```

The gate bounds format and Git checks at 2 minutes, fixture tests at 5 minutes,
Swift tests at 10 minutes, and each Xcode build at 15 minutes. A timeout fails
the automated gate and terminates the command's child processes. Maintainers
may set `RELEASE_GATE_TIMEOUT_SECONDS` to a positive number only when testing
the watchdog itself; release runs use the documented per-check limits.

The command exits with status `2` while any required real-app or OS check is
pending. Follow [the manual checklist](release/MANUAL-CHECKLIST.md), keep the
filled evidence TSV in `.release-evidence/`, and pass it back with
`--manual-evidence`. Selected text and privacy-canary values must never be put
in the evidence TSV or report.

Native AppKit control coverage uses two separately bundled, test-only apps.
Run `scripts/run-native-ax-harness.sh` and follow the checklist. Its harness
uses the real Accessibility reader with an exact test-host policy, performs no
networking, and reports metadata-only PASS/FAIL. The production app continues
to reject that host and supports only its documented three-app allowlist.

The manual matrix uses the dependency-free, loopback-only
[`tools/language_api_stub.py`](tools/language_api_stub.py) fixture. It provides
controlled verdict, delay, incompatible-response, server-error, request-count,
and privacy-canary metadata without storing or logging selected text. It is
test infrastructure and is not a language detector.
