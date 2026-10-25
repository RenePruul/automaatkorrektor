# Results

Observed on 2026-10-25 with the prototype built by Swift 6 and run with
Accessibility permission enabled. The probe printed metadata and character
counts only; selected text was never printed, persisted, or sent.

| Target | Focused element | Result |
| --- | --- | --- |
| TextEdit editable document | `AXTextArea`, no subrole | Selected 178 characters. `AXEnabled` was absent, so absence cannot be treated as disabled. |
| Safari offline text input | `AXTextField`, no subrole | Selected 37 characters. |
| Chrome offline text input | `AXTextField`, no subrole | Selected 37 characters after metadata-only activation of Chrome's on-demand Accessibility tree. |
| Chrome offline password input | secure/protected signal | Returned `protected` before selection access. |
| Apple Mail composer | `AXWebArea`, no subrole | Returned `unsupported` before selection access. Further Mail work was stopped and Mail was removed from the v0.1 target set at the user's request. |

## Decision

The public Accessibility API is sufficient for the deliberately narrow v0.1
surface: TextEdit and standard Safari/Chrome form fields. The production
adapter must use the same metadata-first allowlist, never use the clipboard,
and never fall back to `AXValue` or tree walking.

Chrome's native accessibility tree is created on demand. Before retrying a
missing system-wide focused element, the adapter may query only the frontmost
application's AX role to activate its Accessibility interface, then reacquire
the focused element from the system-wide AX object. This activation is
metadata-only; the resulting element still has to pass every eligibility gate.
Chromium documents both on-demand activation and its macOS native API support:
[Accessibility overview](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/accessibility/overview.md),
[macOS application implementation](https://chromium.googlesource.com/chromium/src/+/HEAD/chrome/browser/chrome_browser_application_mac.mm).

Missing optional `AXEnabled` or `AXFocused` attributes are not affirmative
proof of ineligibility on otherwise standard native controls. Explicit `false`
still rejects the element. Focus is established by the system-wide focused
element and rechecked by element identity immediately before networking.
