# Results

## Decision

The user selected **A · Kohe nähtav** and refined it as the macOS v0.1
Accessibility permission flow.

Retain these choices in the specification:

- there is no separate first-launch state or screen;
- when access is unavailable, show **Accessibility-luba puudub** in the compact
  menu and do not offer the language-check action;
- initial denial and permission removal while the app is running use the same
  missing-permission presentation;
- provide **Ava Accessibility seaded** and **Kontrolli luba uuesti** recovery
  rows;
- after opening settings, show explicit numbered instructions: open Privacy &
  Security → Accessibility, find Automaatkorrektor, enable it, return, and
  recheck;
- when access is available, use a green `checkmark.circle.fill`, the heading
  **Programm on tööks valmis**, and the instruction **Vali tekst ja käivita
  eesti keele kontroll**;
- recheck permission when the app becomes active, when the popover opens, and
  immediately before selection capture; keep the manual recheck as a fallback;
- if permission disappears during an active check, cancel the check, discard
  any ephemeral selected text, and return to the ordinary missing-permission
  presentation.

The prototype uses synthetic permission state. Production must query the real
macOS Accessibility trust API through the separate permission adapter decided
in the module-boundary work.
