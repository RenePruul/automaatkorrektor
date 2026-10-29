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
        self.assertNotIn("spctl --master-disable", README + CHECKLIST)
        self.assertNotIn("xattr -d com.apple.quarantine", README + CHECKLIST)

    def test_update_and_integrity_steps_are_documented(self):
        self.assertIn("käsitsi", README.lower())
        self.assertIn("Accessibility-luba uuesti", README)
        self.assertNotIn(".dmg.sha256", README)
        self.assertIn("release-metadata.txt", README)
        self.assertIn("git rev-parse", README)
        self.assertIn("build-release-candidate.sh", README)
        self.assertIn("finalize-release-dmg.sh", README)
        self.assertIn("ilma seda ehitamata või selle baite muutmata", NORMALIZED_README)
        self.assertIn(".release-evidence/releases/", README)

    def test_manual_evidence_covers_dmg_and_remote_privacy_paths(self):
        self.assertIn("manual-dmg-install", EVIDENCE_TEMPLATE)
        self.assertIn("manual-language-check-consent", EVIDENCE_TEMPLATE)
        self.assertIn("# Candidate-Tag", EVIDENCE_TEMPLATE)
        self.assertIn("# Candidate-Commit", EVIDENCE_TEMPLATE)
        self.assertNotIn("# Candidate-SHA256", EVIDENCE_TEMPLATE)
        self.assertIn("päringute arv", CHECKLIST.lower())
        self.assertIn("Loobu", CHECKLIST)
        self.assertIn("Luba ja kontrolli", CHECKLIST)
        self.assertIn("valitud teksti", CHECKLIST)
        self.assertIn("kuvatud origin", CHECKLIST)

    def test_manual_install_verifies_candidate_before_final_release_outputs_exist(self):
        install_start = CHECKLIST.index("## Loodud DMG paigaldustee")
        final_start = CHECKLIST.index("## Finaliseeritud väljalaske kontroll")
        install_section = CHECKLIST[install_start:final_start]
        final_section = CHECKLIST[final_start:]

        self.assertIn(".candidate-metadata.txt", install_section)
        self.assertIn("Candidate-Tag", install_section)
        self.assertIn("Candidate-Commit", install_section)
        self.assertNotIn("Candidate-SHA256", install_section)
        self.assertNotIn(".dmg.sha256", install_section)
        self.assertNotIn(".release-metadata.txt", install_section)
        self.assertIn("finalize-release-dmg.sh", final_section)
        self.assertIn("bait-baidilt identne", final_section)
        self.assertNotIn(".dmg.sha256", final_section)
        self.assertIn(".release-metadata.txt", final_section)

    def test_readme_orders_candidate_evidence_before_final_output_verification(self):
        candidate = README.index("scripts/build-release-candidate.sh")
        evidence = README.index("tee kõik käsikontrollid täpselt selle DMG-ga")
        finalize = README.index("scripts/finalize-release-dmg.sh")
        final_outputs = README.index("Kontrolli finaliseeritud väljundeid pärast edutamist")

        self.assertLess(candidate, evidence)
        self.assertLess(evidence, finalize)
        self.assertLess(finalize, final_outputs)

    def test_scope_remains_explicit_and_does_not_claim_correction(self):
        self.assertIn("TextEdit", README)
        self.assertIn("Safari", README)
        self.assertIn("Chrome", README)
        self.assertIn("ei jälgi teksti taustal", README)
        self.assertIn("ei jälgi teksti taustal ega paranda ega asenda teksti", NORMALIZED_README)

    def test_public_instruction_headings_are_estonian(self):
        public_instructions = README + CHECKLIST + EVIDENCE_TEMPLATE
        self.assertIn("## Minimaalse DMG paigaldamine", README)
        self.assertIn("## Väljalasketõendid", README)
        self.assertIn("# macOS v0.1 väljalaske käsikontroll", CHECKLIST)
        self.assertNotIn("## Install the minimal DMG", public_instructions)
        self.assertNotIn("## Release evidence", public_instructions)
        self.assertNotIn("# macOS v0.1 manual release checklist", public_instructions)


if __name__ == "__main__":
    unittest.main()
