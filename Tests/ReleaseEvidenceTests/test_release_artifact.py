import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CANDIDATE_SCRIPT = REPOSITORY_ROOT / "scripts" / "build-release-candidate.sh"
FINALIZE_SCRIPT = REPOSITORY_ROOT / "scripts" / "finalize-release-dmg.sh"
COMMIT = "0123456789abcdef0123456789abcdef01234567"


class ReleaseArtifactContractTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.repository = self.root / "repository"
        self.fake_bin = self.root / "bin"
        self.command_log = self.root / "commands.log"
        self.candidate_output = self.root / "candidates"
        self.output = self.root / "releases"
        (self.repository / "scripts").mkdir(parents=True)
        self.fake_bin.mkdir()
        shutil.copy2(CANDIDATE_SCRIPT, self.repository / "scripts" / CANDIDATE_SCRIPT.name)
        shutil.copy2(FINALIZE_SCRIPT, self.repository / "scripts" / FINALIZE_SCRIPT.name)
        self._write_executable(
            self.repository / "scripts" / "release-gate.sh",
            """#!/bin/sh
set -eu
printf '%s\n' gate >> "$RELEASE_TEST_COMMAND_LOG"
report=''; manual=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --report) report=$2; shift 2 ;;
    --manual-evidence) manual=$2; shift 2 ;;
    *) exit 64 ;;
  esac
done
if [ -n "$manual" ]; then
  decision=${RELEASE_TEST_FINAL_DECISION:-READY}
  printf '# Tõendid\n\n**Väljalaskeotsus:** %s\n\n- Commit: `%s`\n- Tulemus: 35 läbitud, 0 ebaõnnestunud, 0 ootel\n' \
    "$decision" "${RELEASE_TEST_REPORT_COMMIT:-0123456789abcdef0123456789abcdef01234567}" > "$report"
  [ "$decision" = READY ]
else
  failed=${RELEASE_TEST_CANDIDATE_FAILED:-0}
  printf '# Tõendid\n\n**Väljalaskeotsus:** BLOCKED\n\n- Commit: `%s`\n- Tulemus: 24 läbitud, %s ebaõnnestunud, 11 ootel\n' \
    "0123456789abcdef0123456789abcdef01234567" "$failed" > "$report"
  exit 2
fi
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
    printf candidate-dmg > "$output"
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

    def test_candidate_allows_only_manual_rows_pending(self):
        result = self._build_candidate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.candidate.is_file())
        self.assertTrue(self.candidate_metadata.is_file())
        self.assertFalse((self.output / "Automaatkorrektor-v0.1.0.release-metadata.txt").exists())
        metadata = self.candidate_metadata.read_text()
        self.assertIn("Format-Version: 1", metadata)
        self.assertIn("Tag: v0.1.0", metadata)
        self.assertIn(f"Commit: {COMMIT}", metadata)
        self.assertNotIn("SHA256", metadata)

    def test_candidate_rejects_failed_automation(self):
        result = self._build_candidate(RELEASE_TEST_CANDIDATE_FAILED="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("automaatkontrollid peavad läbima", result.stderr)
        self.assertNotIn("xcodebuild", self._command_log())

    def test_finalization_promotes_the_exact_candidate_bytes(self):
        self.assertEqual(self._build_candidate().returncode, 0)
        before = self.candidate.read_bytes()
        evidence = self._write_bound_evidence()
        self.command_log.write_text("")
        result = self._finalize(evidence)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.candidate.read_bytes(), before)
        final_dmg = self.output / self.candidate.name
        metadata = self.output / "Automaatkorrektor-v0.1.0.release-metadata.txt"
        ready_report = self.output / "Automaatkorrektor-v0.1.0.release-evidence.md"
        self.assertEqual(final_dmg.read_bytes(), before)
        self.assertFalse((self.output / f"{final_dmg.name}.sha256").exists())
        self.assertIn("Tag: v0.1.0", metadata.read_text())
        self.assertIn(f"Commit: {COMMIT}", metadata.read_text())
        self.assertNotIn("SHA-256", ready_report.read_text())
        commands = self._command_log()
        self.assertIn("gate", commands)
        self.assertNotIn("xcodebuild", commands)
        self.assertNotIn("hdiutil", commands)
        self.assertNotIn("codesign", commands)

    def test_evidence_must_bind_exact_candidate(self):
        self.assertEqual(self._build_candidate().returncode, 0)
        evidence = self._write_bound_evidence(commit="f" * 40)
        self.command_log.write_text("")
        result = self._finalize(evidence)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ei tuvasta täpselt seda kandidaati", result.stderr)
        self.assertNotIn("gate", self._command_log())

    def test_dirty_tree_and_mismatched_tag_are_rejected_before_candidate_gate(self):
        dirty = self._build_candidate(RELEASE_TEST_DIRTY="1")
        self.assertIn("tööpuu peab olema puhas", dirty.stderr)
        self.assertNotIn("gate", self._command_log())
        self.command_log.write_text("")
        mismatch = self._build_candidate(RELEASE_TEST_TAG_COMMIT="f" * 40)
        self.assertIn("ei osuta HEAD-ile", mismatch.stderr)
        self.assertNotIn("gate", self._command_log())

    def test_generated_release_outputs_are_ignored_by_git(self):
        for generated_path in [
            ".release-evidence/candidates/Automaatkorrektor-v0.1.0.dmg",
            ".release-evidence/candidates/Automaatkorrektor-v0.1.0.candidate-metadata.txt",
            ".release-evidence/candidates/Automaatkorrektor-v0.1.0.release-metadata.txt",
            ".release-evidence/releases/Automaatkorrektor-v0.1.0.dmg",
            ".release-evidence/manual.tsv",
        ]:
            with self.subTest(path=generated_path):
                result = subprocess.run(
                    ["git", "check-ignore", "--quiet", generated_path],
                    cwd=REPOSITORY_ROOT,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

    @property
    def candidate(self):
        return self.candidate_output / "Automaatkorrektor-v0.1.0.dmg"

    @property
    def candidate_metadata(self):
        return self.candidate_output / "Automaatkorrektor-v0.1.0.candidate-metadata.txt"

    def _build_candidate(self, **overrides):
        return self._run(
            [str(self.repository / "scripts" / CANDIDATE_SCRIPT.name), "--tag", "v0.1.0", "--output-dir", str(self.candidate_output)],
            overrides,
        )

    def _write_bound_evidence(self, commit=COMMIT):
        evidence = self.root / "manual.tsv"
        evidence.write_text(
            f"# Candidate-Tag\tv0.1.0\n"
            f"# Candidate-Commit\t{commit}\n"
            "manual-textedit\tPASS\tSynthetic metadata-only evidence.\n"
        )
        return evidence

    def _finalize(self, evidence, **overrides):
        return self._run(
            [str(self.repository / "scripts" / FINALIZE_SCRIPT.name), "--candidate", str(self.candidate), "--manual-evidence", str(evidence), "--output-dir", str(self.output)],
            overrides,
        )

    def _run(self, command, overrides):
        environment = os.environ.copy()
        environment.update(overrides)
        environment["PATH"] = f"{self.fake_bin}:{environment['PATH']}"
        environment["RELEASE_TEST_COMMAND_LOG"] = str(self.command_log)
        environment["RELEASE_TEST_DMG_SOURCE_FILE"] = str(self.root / "dmg-source")
        return subprocess.run(command, cwd=self.repository, env=environment, capture_output=True, text=True, check=False)

    def _command_log(self):
        return self.command_log.read_text() if self.command_log.exists() else ""

    @staticmethod
    def _write_executable(path, contents):
        path.write_text(contents)
        path.chmod(0o755)


if __name__ == "__main__":
    unittest.main()
