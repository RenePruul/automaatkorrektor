# Automaatkorrektor

Automaatkorrektor checks whether text that you explicitly select is Estonian.
It does not monitor text in the background and does not correct or replace
text. Every check starts from the menu-bar action or the configured shortcut.

## Language service

Automaatkorrektor is a client for a separately running compatible language
service. The default address is `http://127.0.0.1:8000`, so selected text does
not leave this Mac. Install the `keele_tuvastaja` project separately and start
it before using the client, for example:

```sh
cd /path/to/keele_tuvastaja
.venv/bin/keele-api
```

The client does not install or start Python or the language service. A local
service must remain bound to the loopback interface; check its availability
with `curl --fail http://127.0.0.1:8000/health`.

Settings also accepts a custom remote HTTPS service. A custom service is
independently operated and receives the selected text under its operator's
data-handling terms. Before any selected text is read, the client displays the
normalized destination and requires origin-specific language-check consent. Declining sends
nothing. Changing the scheme, host, or effective port requires new consent,
and saved consent can be revoked in Settings. Use only a service you trust and
do not select passwords, secrets, or sensitive personal data.

## Install the minimal DMG

This version requires macOS 15 or later. This version is not Developer ID signed or Apple notarized, so macOS may ask for confirmation on first launch.

1. Open the downloaded `.dmg` and drag `Automaatkorrektor.app` to
   `/Applications`.
2. Try to open the installed app. If macOS blocks it, Control-click the app,
   choose **Open**, then confirm **Open**. Alternatively, after the blocked
   launch, open **System Settings → Privacy & Security** and choose
   **Open Anyway** for Automaatkorrektor.
3. Grant Automaatkorrektor access in **System Settings → Privacy & Security →
   Accessibility** when asked.
4. Start the separate language service, select text in a supported field, and
   invoke **Kontrolli valitud teksti** from the menu bar or with the configured
   shortcut.

Do not disable Gatekeeper globally. The minimal release has no automatic
updater: quit the app and manually replace the old app in `/Applications` with
the new version. Because an ad-hoc build changes between releases, macOS may
ask you to grant Accessibility permission again. If checks remain blocked,
remove the old Automaatkorrektor entry from Accessibility, add the replacement
app, enable it, and reopen the app.

## Verify a download

Each finalized release contains a versioned DMG, its `.dmg.sha256` file, and a
`.release-metadata.txt` file. Download all three into one directory and run:

```sh
shasum -a 256 -c Automaatkorrektor-v0.1.0.dmg.sha256
cat Automaatkorrektor-v0.1.0.release-metadata.txt
git fetch --tags
git rev-parse 'v0.1.0^{commit}'
```

The checksum command must report `OK`. The metadata `Tag` must match the
release tag, its `Commit` must equal the commit printed by `git rev-parse`, and
its `DMG-SHA256` must equal the checksum. Replace `v0.1.0` with the version you
downloaded.

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

These compatibility claims do not include background monitoring, automatic
correction, arbitrary editors, or writing text back into another application.

## Release evidence

The v0.1 release gate has exactly 35 required checks. Run the automated checks
and create a metadata-only report with:

```sh
scripts/release-gate.sh
```

The gate bounds format and Git checks at 2 minutes, fixture tests at 5 minutes,
Swift tests at 10 minutes, and each Xcode build at 15 minutes. A timeout fails
the automated gate and terminates the command's child processes. Maintainers
may set `RELEASE_GATE_TIMEOUT_SECONDS` to a positive number only when testing
the watchdog itself; release runs use the documented per-check limits.

The command exits with status `2` while any required real-app or OS check is
pending. Follow [the manual checklist](release/MANUAL-CHECKLIST.md), keep the
filled evidence TSV in `.release-evidence/`, and pass it back with
`--manual-evidence`. Selected text and privacy-canary values must never be put
in the evidence TSV or report.

Native AppKit control coverage uses two separately bundled, test-only apps.
Run `scripts/run-native-ax-harness.sh` and follow the checklist. Its harness
uses the real Accessibility reader with an exact test-host policy, performs no
networking, and reports metadata-only PASS/FAIL. The production app continues
to reject that host and supports only its documented three-app allowlist.

The manual matrix uses the dependency-free, loopback-only
[`tools/language_api_stub.py`](tools/language_api_stub.py) fixture. It provides
controlled verdict, delay, incompatible-response, server-error, request-count,
and privacy-canary metadata without storing or logging selected text. It is
test infrastructure and is not a language detector.

Build a candidate from a clean worktree whose HEAD has the exact release tag.
Automated checks must pass; manual rows are expected to remain pending:

```sh
scripts/build-release-candidate.sh --tag v0.1.0
```

The command builds and verifies the ad-hoc-signed app and writes the candidate
DMG, candidate metadata, and pending evidence report under
`.release-evidence/candidates/`. It deliberately does not emit a final checksum.

Copy `release/manual-evidence.example.tsv` to `.release-evidence/manual.tsv`.
Replace its three `Candidate-*` header values from the candidate metadata, then
perform every manual check on that exact DMG. Finalize only after all rows pass:

```sh
scripts/finalize-release-dmg.sh \
  --candidate .release-evidence/candidates/Automaatkorrektor-v0.1.0.dmg \
  --manual-evidence .release-evidence/manual.tsv
```

Finalization requires READY evidence bound to the candidate tag, commit, and
SHA-256. It verifies the candidate again without rebuilding or changing its
bytes, then promotes a byte-identical final DMG, checksum, metadata, and READY
report into `.release-evidence/releases/`. Neither phase uploads a GitHub
Release, pushes a tag, or modifies an external service.
