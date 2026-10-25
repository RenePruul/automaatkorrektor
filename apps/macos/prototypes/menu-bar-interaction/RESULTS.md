# Results

## Decision

The user selected **D · Minimaalne 2** as the interaction baseline for macOS
v0.1 after comparing all four variants in the running native menu bar app.

Retain these choices in the specification:

- a menu bar utility with no persistent main window and no Dock icon;
- a compact, native-menu-like popover rather than a dashboard or large card;
- the neutral waiting state **Ootan valikut** with the
  `text.magnifyingglass` symbol, not a generic “ready” icon;
- one explicit **Kontrolli valitud teksti** action with its configured shortcut
  displayed on the same row;
- the current progress, verdict, permission problem, or API problem at the top;
- a contextual recovery row for missing Accessibility permission or API error;
- shortcut configuration and quit as secondary rows.

The prototype uses synthetic state only. It does not register a real global
shortcut, read selected text, persist settings, or call the language API. Those
belong to later decisions and production implementation.
