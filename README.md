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
