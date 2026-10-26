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

The command exits with status `2` while any required real-app or OS check is
pending. Follow [the manual checklist](release/MANUAL-CHECKLIST.md), keep the
filled evidence TSV in `.release-evidence/`, and pass it back with
`--manual-evidence`. Selected text and privacy-canary values must never be put
in the evidence TSV or report.
