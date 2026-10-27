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

## Offline stub language API

`tools/language_api_stub.py` is test-only infrastructure. It uses only the
Python standard library, binds exclusively to `127.0.0.1`, and accepts exactly
`POST /detect` with `{"text":"..."}`. It never stores or prints request bodies.
Its event output contains only request count, body byte count, field names, and
the optional canary-match boolean.

Start one deterministic verdict at the client's default API address:

```sh
AUTOMAATKORREKTOR_STUB_PORT=8000 \
AUTOMAATKORREKTOR_STUB_VERDICT=jah \
python3 tools/language_api_stub.py
```

Restart with `ei` or `ebakindel` for the other verdicts. The following response
and delay modes exercise recovery behavior:

```sh
# Client's three-second timeout; cancelled connections are expected.
AUTOMAATKORREKTOR_STUB_PORT=8000 \
AUTOMAATKORREKTOR_STUB_DELAY_SECONDS=4 \
python3 tools/language_api_stub.py

# Unknown verdict / incompatible service.
AUTOMAATKORREKTOR_STUB_PORT=8000 \
AUTOMAATKORREKTOR_STUB_RESPONSE=incompatible \
python3 tools/language_api_stub.py

# HTTP 503 / unavailable server behavior.
AUTOMAATKORREKTOR_STUB_PORT=8000 \
AUTOMAATKORREKTOR_STUB_RESPONSE=server-error \
python3 tools/language_api_stub.py
```

While it runs, inspect privacy-safe volatile state with:

```sh
curl --fail --silent http://127.0.0.1:8000/_test/status
```

The response contains `request_count` and allowlisted metadata, never selected
text. Stop the fixture with Control-C. Do not redirect fixture output to a file.

## Test-only native Accessibility harness

The production Automaatkorrektor allowlist remains exactly TextEdit, Safari,
and Chrome. It must reject `NativeTextControlHost`; the host is admitted only
by the separately compiled test harness policy. Neither test app performs a
network request or displays, logs, or stores selected text.

Build and open both properly bundled test apps with the exact operator command:

```sh
scripts/run-native-ax-harness.sh
```

1. Grant **AX Integration Harness** Accessibility access in System Settings.
   Do not use an environment variable or modify production Automaatkorrektor.
2. For each harness row, click **Arm**, then within five seconds click the
   matching **Prepare** button in **Native Text Control Host**. The host focuses
   the control and selects only its synthetic fixture text.
3. Require metadata-only `PASS` for editable `NSTextField`, `NSSearchField`,
   and `NSTextView`.
4. Require metadata-only `PASS` for rejection of read-only, disabled, and
   secure fields. No language API or stub is involved.
5. Launch the production Automaatkorrektor separately, select synthetic host
   text, and confirm the production client rejects the host before any stub
   request.

The `integration-native-host` evidence remains `PENDING` until all seven
outcomes above have been run on the release candidate. Record only app versions,
the six harness PASS states, production rejection, OS version, and date—never
fixture text.

## TextEdit

1. Grant production Automaatkorrektor Accessibility access in System Settings.
2. In TextEdit, verify an explicit synthetic selection produces each of `jah`,
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

1. Type a unique value beginning `AUTOMAATKORREKTOR-PRIVACY-CANARY-` into an
   eligible synthetic field, but do not invoke the check yet. Do not use the
   clipboard.
2. Enter the same value without terminal echo and derive only its hash in a
   volatile environment variable:

   ```sh
   IFS= read -r -s canary_value
   export AUTOMAATKORREKTOR_STUB_CANARY_SHA256="$(printf %s "$canary_value" | shasum -a 256 | awk '{print $1}')"
   unset canary_value
   AUTOMAATKORREKTOR_STUB_PORT=8000 python3 tools/language_api_stub.py
   ```

3. Perform exactly one check. Query `/_test/status` and require
   `request_count: 1` and `canary_match: true`. The fixture compares SHA-256
   digests and never retains or emits the complete value.
4. Confirm the complete value appears nowhere in the request URL, headers, app
   UI, settings, unified log, files, caches, crash reports, history, or
   generated release report.
5. Stop the fixture, unset `AUTOMAATKORREKTOR_STUB_CANARY_SHA256`, and record
   only pass/fail plus a neutral evidence note. Never copy the value or its hash
   into the TSV or report.

## OS and API boundaries

1. Run the core manual matrix on macOS 14 and on the current development macOS.
2. Record both OS versions and Safari/Chrome versions in neutral notes.
3. Run against a named language API commit. Confirm exactly `POST /detect`, a
   JSON request with only `text`, and response verdicts `jah`, `ei`, and
   `ebakindel`. Record the API commit, never request or response content.
4. Confirm release notes claim only TextEdit and standard Safari/Chrome fields;
   do not claim Mail, rich editors, correction, passive monitoring, Windows,
   launch-at-login, or production distribution.
