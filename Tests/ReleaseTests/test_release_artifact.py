import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BUILD_SCRIPT = REPOSITORY_ROOT / "scripts" / "build-release-dmg.sh"
COMMIT = "0123456789abcdef0123456789abcdef01234567"


class ReleaseArtifactContractTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.repository = self.root / "repository"
        self.fake_bin = self.root / "bin"
        self.command_log = self.root / "commands.log"
        self.output = self.root / "releases"
        (self.repository / "scripts").mkdir(parents=True)
        self.fake_bin.mkdir()
        shutil.copy2(BUILD_SCRIPT, self.repository / "scripts" / BUILD_SCRIPT.name)
        self._write_executable(
            self.repository / "scripts" / "release-gate.sh",
            """#!/bin/sh
set -eu
printf '%s\n' gate >> "$RELEASE_TEST_COMMAND_LOG"
exit "${RELEASE_TEST_GATE_EXIT:-0}"
""",
        )
        self._write_executable(
            self.fake_bin / "git",
            f"""#!/bin/sh
set -eu
printf 'git %s\n' "$*" >> "$RELEASE_TEST_COMMAND_LOG"
case "$*" in
  'status --porcelain --untracked-files=normal')
    [ "${{RELEASE_TEST_DIRTY:-0}}" = 0 ] || printf '%s\n' ' M README.md'
    ;;
  'rev-parse HEAD') printf '%s\n' '{COMMIT}' ;;
  'rev-parse -q --verify refs/tags/v0.1.0^{{commit}}')
    printf '%s\n' "${{RELEASE_TEST_TAG_COMMIT:-{COMMIT}}}"
    ;;
  *) exit 64 ;;
esac
""",
        )
        self._write_executable(
            self.fake_bin / "xcodebuild",
            """#!/bin/sh
set -eu
printf 'xcodebuild %s\n' "$*" >> "$RELEASE_TEST_COMMAND_LOG"
derived_data=''; previous=''
for argument in "$@"; do
  [ "$previous" != '-derivedDataPath' ] || derived_data=$argument
  previous=$argument
done
app="$derived_data/Build/Products/Release/Automaatkorrektor.app"
mkdir -p "$app/Contents/MacOS"
printf executable > "$app/Contents/MacOS/Automaatkorrektor"
chmod +x "$app/Contents/MacOS/Automaatkorrektor"
cat > "$app/Contents/Info.plist" <<'PLIST'
<plist version="1.0"><dict><key>LSMinimumSystemVersion</key><string>15.0</string></dict></plist>
PLIST
""",
        )
        self._write_executable(
            self.fake_bin / "codesign",
            """#!/bin/sh
set -eu
printf 'codesign %s\n' "$*" >> "$RELEASE_TEST_COMMAND_LOG"
case "$*" in *'-dv'*) printf '%s\n' 'Signature=adhoc' 'TeamIdentifier=not set' >&2 ;; esac
""",
        )
        self._write_executable(
            self.fake_bin / "hdiutil",
            """#!/bin/sh
set -eu
printf 'hdiutil %s\n' "$*" >> "$RELEASE_TEST_COMMAND_LOG"
operation=$1; shift
case "$operation" in
  create)
    previous=''; source_directory=''
    for argument in "$@"; do
      [ "$previous" != '-srcfolder' ] || source_directory=$argument
      previous=$argument; output=$argument
    done
    printf '%s\n' "$source_directory" > "$RELEASE_TEST_DMG_SOURCE_FILE"
    printf release-dmg > "$output"
    ;;
  verify) test -f "$1" ;;
  attach)
    previous=''; mount_point=''
    for argument in "$@"; do
      [ "$previous" != '-mountpoint' ] || mount_point=$argument
      previous=$argument
    done
    mkdir -p "$mount_point"
    cp -R "$(cat "$RELEASE_TEST_DMG_SOURCE_FILE")"/. "$mount_point"/
    ;;
  detach) test -d "$1" ;;
  *) exit 64 ;;
esac
""",
        )

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_build_produces_only_verified_dmg(self):
        result = self._build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([path.name for path in self.output.iterdir()], [self.dmg.name])
        self.assertEqual(self.dmg.read_bytes(), b"release-dmg")
        commands = self._command_log()
        self.assertIn("gate", commands)
        self.assertIn("xcodebuild", commands)
        self.assertIn("codesign", commands)
        self.assertIn("hdiutil verify", commands)
        self.assertIn("hdiutil attach", commands)
        self.assertIn("hdiutil detach", commands)

    def test_failed_automatic_gate_stops_before_build(self):
        result = self._build(RELEASE_TEST_GATE_EXIT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("xcodebuild", self._command_log())

    def test_dirty_tree_and_mismatched_tag_are_rejected_before_gate(self):
        dirty = self._build(RELEASE_TEST_DIRTY="1")
        self.assertIn("tööpuu peab olema puhas", dirty.stderr)
        self.assertNotIn("gate", self._command_log())
        self.command_log.write_text("")
        mismatch = self._build(RELEASE_TEST_TAG_COMMIT="f" * 40)
        self.assertIn("ei osuta HEAD-ile", mismatch.stderr)
        self.assertNotIn("gate", self._command_log())

    def test_existing_dmg_is_not_overwritten(self):
        self.output.mkdir()
        self.dmg.write_bytes(b"existing")
        result = self._build()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.dmg.read_bytes(), b"existing")
        self.assertNotIn("gate", self._command_log())

    def test_generated_release_dmg_is_ignored_by_git(self):
        result = subprocess.run(
            ["git", "check-ignore", "--quiet", ".release-evidence/releases/Automaatkorrektor-v0.1.0.dmg"],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    @property
    def dmg(self):
        return self.output / "Automaatkorrektor-v0.1.0.dmg"

    def _build(self, **overrides):
        environment = os.environ.copy()
        environment.update(overrides)
        environment["PATH"] = f"{self.fake_bin}:{environment['PATH']}"
        environment["RELEASE_TEST_COMMAND_LOG"] = str(self.command_log)
        environment["RELEASE_TEST_DMG_SOURCE_FILE"] = str(self.root / "dmg-source")
        return subprocess.run(
            [
                str(self.repository / "scripts" / BUILD_SCRIPT.name),
                "--tag",
                "v0.1.0",
                "--output-dir",
                str(self.output),
            ],
            cwd=self.repository,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def _command_log(self):
        return self.command_log.read_text() if self.command_log.exists() else ""

    @staticmethod
    def _write_executable(path, contents):
        path.write_text(contents)
        path.chmod(0o755)


if __name__ == "__main__":
    unittest.main()
