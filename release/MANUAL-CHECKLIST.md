# macOS v0.1 manual release checklist

Use only synthetic text and a stub language API. Never paste personal writing,
passwords, tokens, or the privacy-canary value into the evidence file or report.

Copy `release/manual-evidence.example.tsv` outside Git tracking, replace a row's
`PENDING` only after performing it, and run:

```sh
scripts/release-gate.sh \
  --manual-evidence .release-evidence/manual.tsv \
  --report .release-evidence/report.md
```

The command exits with status 2 until all 29 required rows pass.

## Native host and TextEdit

1. Build the release candidate and `NativeTextControlHost` with the full Xcode
   toolchain.
2. Grant Automaatkorrektor Accessibility access in System Settings.
3. In the native host, verify editable `NSTextField`, `NSSearchField`, and
   `NSTextView` selections each produce the stub verdict.
4. Verify read-only, disabled, and secure fields produce no stub request.
5. In TextEdit, verify an explicit synthetic selection produces each of `jah`,
   `ei`, and `ebakindel`; an empty selection and a focus change produce no
   request.

## Safari and Chrome

1. Open `Tests/AutomaatkorrektorMacOSTests/Fixtures/browser-fields.html` locally
   in each browser. Do not serve it from the internet.
2. Verify text, search, and textarea selections produce the stub verdict.
3. Verify password, read-only, disabled, and contenteditable cases produce no
   request. Do not count browser chrome such as the address bar as page-field
   evidence.

## Permission and interaction

1. With Accessibility denied, verify the blocked UI and numbered recovery
   instructions. Confirm no stub request occurs.
2. Grant access and recheck; verify the green ready state without restarting.
3. Start a delayed check, revoke access, and verify cancellation without a
   second request.
4. Compare the menu action and global shortcut: both must open the popover,
   show checking, and leave the same verdict or stable error visible.
5. Verify timeout, unavailable service, and incompatible response UI. Closing
   the popover during a delayed request must cancel silently.

## Privacy canary

1. Generate a unique value beginning with the documented canary prefix; keep
   the complete value only in volatile shell state.
2. Select it in one eligible synthetic field and perform exactly one check
   against the stub API.
3. Confirm the complete value occurs once in the stub request body and nowhere
   in the request URL, headers, app UI, settings, unified log, files, caches,
   crash reports, history, or generated release report.
4. Delete the stub request capture after recording only pass/fail and a neutral
   evidence note. Never copy the complete value into the TSV or report.

## OS and API boundaries

1. Run the core manual matrix on macOS 14 and on the current development macOS.
2. Record both OS versions and Safari/Chrome versions in neutral notes.
3. Run against a named language API commit. Confirm exactly `POST /detect`, a
   JSON request with only `text`, and response verdicts `jah`, `ei`, and
   `ebakindel`. Record the API commit, never request or response content.
4. Confirm release notes claim only TextEdit and standard Safari/Chrome fields;
   do not claim Mail, rich editors, correction, passive monitoring, Windows,
   launch-at-login, or production distribution.
