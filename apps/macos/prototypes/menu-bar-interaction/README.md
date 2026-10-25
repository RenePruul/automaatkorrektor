# Menu bar interaction prototype

Throwaway native macOS prototype for the Wayfinder decision **Prove the menu
bar interaction**.

It compares three structurally different menu bar popovers plus a refined
compact iteration. Use the A/B/C/D
switcher at the bottom and the state picker to inspect ready, checking, verdict,
permission, and API-error states. The prototype uses synthetic state only: it
does not read selected text or call the language API.

## Run

```bash
cd apps/macos/prototypes/menu-bar-interaction
swift run MenuBarInteractionPrototype
```

Click the `ET` item in the macOS menu bar. The app intentionally has no main
window and no Dock icon. Stop it from the popover with **Sulge prototüüp** or
press `Ctrl+C` in the launching terminal.

## Variants

- **A · Tegevus ees** — primary action dominates; result appears underneath.
- **B · Olek ees** — progress, permission, verdict, or error is the main object.
- **C · Minimaalne** — compact native-menu-like rows for repeat keyboard use.
- **D · Minimaalne 2** — the preferred C structure with a calmer waiting state
  and a language-check icon instead of the misleading ready icon.

Question to answer: which structure makes the explicit check, shortcut,
permission state, progress, verdict, and API failure clearest without creating
a main window?
