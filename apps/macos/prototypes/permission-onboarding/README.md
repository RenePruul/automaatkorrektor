# Permission onboarding prototype

Throwaway native macOS prototype for the Wayfinder decision **Design
permission onboarding and recovery**.

It keeps the selected compact menu bar structure and compares three permission
flows. All permission state is synthetic: this prototype does not request real
Accessibility access, open System Settings, read selected text, or call the
language API.

## Run

```bash
cd apps/macos/prototypes/permission-onboarding
swift run PermissionOnboardingPrototype
```

Click `ET` in the menu bar. Use the bottom state picker to simulate missing
permission, return from settings, a granted permission, and permission removal
while the app is running. Compare A/B/C with the segmented switcher.

## Variants

- **A · Kohe nähtav** — missing permission replaces the status and adds direct
  recovery rows inside the compact menu.
- **B · Juhendatud** — missing permission temporarily replaces the normal menu
  with a focused explanation and one primary next step.
- **C · Vajaduse hetkel** — the normal menu stays quiet until a check actually
  needs permission; revocation still appears immediately.
