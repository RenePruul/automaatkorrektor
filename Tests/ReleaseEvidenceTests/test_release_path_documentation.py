import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
README = (REPOSITORY_ROOT / "README.md").read_text()
NORMALIZED_README = " ".join(README.split())
CHECKLIST = (REPOSITORY_ROOT / "release" / "MANUAL-CHECKLIST.md").read_text()
EVIDENCE_TEMPLATE = (
    REPOSITORY_ROOT / "release" / "manual-evidence.example.tsv"
).read_text()


class ReleasePathDocumentationTests(unittest.TestCase):
    def test_user_path_explains_local_and_remote_privacy_boundaries(self):
        self.assertIn("http://127.0.0.1:8000", README)
        self.assertIn("does not leave this Mac", NORMALIZED_README)
        self.assertIn("custom remote HTTPS", README)
        self.assertIn("independently operated", README)
        self.assertIn("origin-specific language-check consent", README)

    def test_installation_uses_only_safe_gatekeeper_recovery(self):
        self.assertIn(
            "This version is not Developer ID signed or Apple notarized, so macOS may ask for confirmation on first launch.",
            README,
        )
        self.assertIn("Control-click", README)
        self.assertIn("Open Anyway", README)
        self.assertNotIn("spctl --master-disable", README + CHECKLIST)
        self.assertNotIn("xattr -d com.apple.quarantine", README + CHECKLIST)

    def test_update_and_integrity_steps_are_documented(self):
        self.assertIn("manual", README.lower())
        self.assertIn("Accessibility permission again", README)
        self.assertIn("shasum -a 256 -c", README)
        self.assertIn("release-metadata.txt", README)
        self.assertIn("git rev-parse", README)
        self.assertIn("build-release-candidate.sh", README)
        self.assertIn("finalize-release-dmg.sh", README)
        self.assertIn("without rebuilding or changing its bytes", NORMALIZED_README)
        self.assertIn(".release-evidence/releases/", README)

    def test_manual_evidence_covers_dmg_and_remote_privacy_paths(self):
        self.assertIn("manual-dmg-install", EVIDENCE_TEMPLATE)
        self.assertIn("manual-language-check-consent", EVIDENCE_TEMPLATE)
        self.assertIn("# Candidate-Tag", EVIDENCE_TEMPLATE)
        self.assertIn("# Candidate-Commit", EVIDENCE_TEMPLATE)
        self.assertIn("# Candidate-SHA256", EVIDENCE_TEMPLATE)
        self.assertIn("request count", CHECKLIST.lower())
        self.assertIn("Refuse", CHECKLIST)
        self.assertIn("Allow", CHECKLIST)
        self.assertIn("selected text", CHECKLIST)
        self.assertIn("displayed origin", CHECKLIST)

    def test_manual_install_verifies_candidate_before_final_release_outputs_exist(self):
        install_start = CHECKLIST.index("## Produced DMG installation path")
        final_start = CHECKLIST.index("## Finalized release verification")
        install_section = CHECKLIST[install_start:final_start]
        final_section = CHECKLIST[final_start:]

        self.assertIn(".candidate-metadata.txt", install_section)
        self.assertIn("Candidate-Tag", install_section)
        self.assertIn("Candidate-Commit", install_section)
        self.assertIn("Candidate-SHA256", install_section)
        self.assertNotIn(".dmg.sha256", install_section)
        self.assertNotIn(".release-metadata.txt", install_section)
        self.assertIn("finalize-release-dmg.sh", final_section)
        self.assertIn("byte-identical", final_section)
        self.assertIn(".dmg.sha256", final_section)
        self.assertIn(".release-metadata.txt", final_section)

    def test_readme_orders_candidate_evidence_before_final_output_verification(self):
        candidate = README.index("scripts/build-release-candidate.sh")
        evidence = README.index("perform every manual check on that exact DMG")
        finalize = README.index("scripts/finalize-release-dmg.sh")
        final_outputs = README.index("Verify the finalized outputs after promotion")

        self.assertLess(candidate, evidence)
        self.assertLess(evidence, finalize)
        self.assertLess(finalize, final_outputs)

    def test_scope_remains_explicit_and_does_not_claim_correction(self):
        self.assertIn("TextEdit", README)
        self.assertIn("Safari", README)
        self.assertIn("Chrome", README)
        self.assertIn("does not monitor text in the background", README)
        self.assertIn("does not correct or replace text", NORMALIZED_README)


if __name__ == "__main__":
    unittest.main()
