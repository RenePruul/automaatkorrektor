import pathlib
import unittest


REPO = pathlib.Path(__file__).resolve().parents[2]
PRODUCTION_BUNDLE = "ee.elle.Automaatkorrektor"
HOST_BUNDLE = "ee.elle.Automaatkorrektor.NativeTextControlHost"
HARNESS_BUNDLE = "ee.elle.Automaatkorrektor.AXIntegrationHarness"


class NativeHarnessContractTests(unittest.TestCase):
    def test_swift_package_does_not_publish_an_unbundled_host(self):
        package = (REPO / "Package.swift").read_text()
        self.assertNotIn('.executable(name: "NativeTextControlHost"', package)
        self.assertNotIn('.executableTarget(name: "NativeTextControlHost"', package)

    def test_harness_policy_is_compiled_only_for_harness_target(self):
        reader = (
            REPO
            / "Sources/AutomaatkorrektorMacOS/AccessibilitySelectedTextReader.swift"
        ).read_text()
        harness = (
            REPO / "Sources/AXIntegrationHarness/AXIntegrationHarnessApp.swift"
        ).read_text()
        project = (
            REPO / "apps/macos/Automaatkorrektor.xcodeproj/project.pbxproj"
        ).read_text()

        self.assertIn("#if AX_INTEGRATION_HARNESS", reader)
        self.assertIn("static func nativeTextControlTestHarness(", reader)
        self.assertIn("applicationPolicy: .nativeTextControlHost", reader)
        self.assertNotIn("testHostBundleIdentifier", reader)
        self.assertNotIn("precondition(", reader)
        self.assertEqual(reader.count(HOST_BUNDLE), 1)
        self.assertNotIn(HOST_BUNDLE, harness)
        self.assertIn(
            "AccessibilitySelectedTextReader.nativeTextControlTestHarness()",
            harness,
        )
        self.assertIn(
            "allowedApplications: [.textEdit, .safari, .chrome]", reader
        )
        self.assertIn("static let nativeTextControlHost = AXApplicationPolicy(", reader)
        self.assertIn(HOST_BUNDLE, project)
        self.assertIn(HARNESS_BUNDLE, project)
        self.assertGreaterEqual(
            project.count("SWIFT_ACTIVE_COMPILATION_CONDITIONS = AX_INTEGRATION_HARNESS"),
            2,
        )
        production_lines = [
            line
            for line in project.splitlines()
            if f"PRODUCT_BUNDLE_IDENTIFIER = {PRODUCTION_BUNDLE};" in line
        ]
        self.assertEqual(len(production_lines), 2)
        self.assertTrue(
            all("AX_INTEGRATION_HARNESS" not in line for line in production_lines)
        )

    def test_test_harness_is_metadata_only_and_offline(self):
        harness = (
            REPO / "Sources/AXIntegrationHarness/AXIntegrationHarnessApp.swift"
        ).read_text()
        forbidden = ["URLSession", "LanguageAPI", "http://", "https://", "print("]
        for value in forbidden:
            self.assertNotIn(value, harness)
        self.assertNotIn("ProcessInfo", harness)
        self.assertIn("Metaandmetega tulemus", harness)
        self.assertIn("Käivita kontroll", harness)
        self.assertNotIn("Metadata-only result", harness)
        self.assertNotIn("selectedText.value", harness)

    def test_operator_checklist_separates_production_and_test_policies(self):
        checklist = (REPO / "release/MANUAL-CHECKLIST.md").read_text()
        normalized_checklist = " ".join(checklist.split())
        self.assertIn("scripts/run-native-ax-harness.sh", checklist)
        self.assertIn("Tootmisrakenduse Automaatkorrektor", checklist)
        self.assertIn(
            "peab `NativeTextControlHost` hosti tagasi lükkama",
            normalized_checklist,
        )
        self.assertIn("jääb olekusse `PENDING`, kuni", normalized_checklist)


if __name__ == "__main__":
    unittest.main()
