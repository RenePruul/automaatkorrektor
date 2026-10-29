import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
README = (REPOSITORY_ROOT / "README.md").read_text()
NORMALIZED_README = " ".join(README.split())
CHECKLIST = (REPOSITORY_ROOT / "release" / "MANUAL-CHECKLIST.md").read_text()
PUBLIC_INSTRUCTIONS = README + CHECKLIST


class ReleasePathDocumentationTests(unittest.TestCase):
    def test_user_path_explains_local_and_remote_privacy_boundaries(self):
        self.assertIn("http://127.0.0.1:8000", README)
        self.assertIn("ei lahku valitud tekst sellest Macist", NORMALIZED_README)
        self.assertIn("enda valitud HTTPS-kaugteenust", README)
        self.assertIn("iseseisev operaator", README)
        self.assertIn("keelekontrolli nõusolekut", README)

    def test_installation_uses_only_safe_gatekeeper_recovery(self):
        self.assertIn(
            "Versioon ei ole Developer ID-ga allkirjastatud ega Apple'i notariseeritud, mistõttu võib macOS esmakordsel avamisel kinnitust küsida.",
            NORMALIZED_README,
        )
        self.assertIn("Control-klõps", README)
        self.assertIn("Open Anyway", README)
        self.assertNotIn("spctl --master-disable", PUBLIC_INSTRUCTIONS)
        self.assertNotIn("xattr -d com.apple.quarantine", PUBLIC_INSTRUCTIONS)

    def test_simple_release_path_is_documented(self):
        self.assertIn("scripts/release-gate.sh", README)
        self.assertIn("scripts/build-release-dmg.sh --tag v0.1.0", README)
        self.assertIn(
            ".release-evidence/releases/Automaatkorrektor-v0.1.0.dmg", README
        )
        self.assertIn("release/MANUAL-CHECKLIST.md", README)
        self.assertIn("GitHub", README)
        self.assertIn("versioonisildile", README)

    def test_formal_evidence_flow_is_not_documented(self):
        forbidden = [
            "manual.tsv",
            "manual-evidence",
            "candidate-metadata",
            "build-release-candidate",
            "finalize-release-dmg",
            "release-metadata",
            "`READY`",
            "`BLOCKED`",
            "`PENDING`",
        ]
        for value in forbidden:
            self.assertNotIn(value, PUBLIC_INSTRUCTIONS)

    def test_manual_checklist_covers_supported_paths(self):
        for value in [
            "TextEdit",
            "Safari",
            "Chrome",
            "Accessibility",
            "Menüüriba",
            "kiirklahv",
            "Proovi uuesti",
            "DMG",
            "Käivita kontroll",
            "Valmista ette",
            "Loobu",
            "Luba ja kontrolli",
        ]:
            self.assertIn(value, CHECKLIST)

    def test_scope_remains_explicit_and_does_not_claim_correction(self):
        self.assertIn("TextEdit", README)
        self.assertIn("Safari", README)
        self.assertIn("Chrome", README)
        self.assertIn("ei jälgi teksti taustal", README)
        self.assertIn(
            "ei jälgi teksti taustal ega paranda ega asenda teksti",
            NORMALIZED_README,
        )

    def test_public_instruction_headings_are_estonian(self):
        self.assertIn("## Minimaalse DMG paigaldamine", README)
        self.assertIn("## Väljalaske loomine", README)
        self.assertIn("# macOS-i väljalaske käsikontroll", CHECKLIST)
        self.assertNotIn("## Install the minimal DMG", PUBLIC_INSTRUCTIONS)
        self.assertNotIn("## Release evidence", PUBLIC_INSTRUCTIONS)


if __name__ == "__main__":
    unittest.main()
