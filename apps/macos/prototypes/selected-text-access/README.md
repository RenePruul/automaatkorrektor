# Selected-text access prototype

Throwaway native macOS probe for the Wayfinder decision **Prove selected-text
access in target apps**. It answers one question: can the public Accessibility
API read only an explicit selection from the focused control while refusing
protected, read-only, unknown, and ambiguous controls before reading content?

The probe never uses the clipboard, never sends a network request, and never
prints or persists selected text. A successful result reports only metadata and
the selection length.

## Run

```bash
cd apps/macos/prototypes/selected-text-access
swift run SelectedTextAccessPrototype --delay 8
```

When the countdown starts, switch to the target application, focus an editable
field, select known text, and wait. On first use macOS may request Accessibility
permission. If permission is still missing, enable the invoking terminal or the
built executable in **System Settings → Privacy & Security → Accessibility** and
run the command again.

Repeat with:

- TextEdit editable text;
- Safari text input, search input, textarea, password, and contenteditable;
- Chrome text input, search input, textarea, password, and contenteditable.

Apple Mail was removed from the v0.1 compatibility target at the user's
request. See [RESULTS.md](RESULTS.md) for the captured observations and decision.

Expected privacy boundary:

- standard focused editable text fields return `selected` plus lengths;
- password/protected controls return `protected`;
- web areas, contenteditable surfaces exposed through non-standard roles,
  read-only controls, missing permission, focus changes, and AX failures return
  a non-success result without printing text.
