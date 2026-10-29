import pathlib
import unittest


REPO = pathlib.Path(__file__).resolve().parents[2]
ADAPTER = (
    REPO / "Sources/AutomaatkorrektorMacOS/KeyboardShortcutsAdapter.swift"
)


def declaration_body(source: str, declaration: str) -> str:
    """Return one narrowly named Swift declaration's balanced-brace body."""
    declaration_start = source.index(declaration)
    body_start = source.index("{", declaration_start)
    depth = 0
    for index in range(body_start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[body_start + 1 : index]
    raise AssertionError(f"unclosed Swift declaration: {declaration}")


class ShortcutPolicyContractTests(unittest.TestCase):
    def test_production_recorder_applies_the_required_conflict_policy(self):
        source = ADAPTER.read_text()
        recorder = declaration_body(source, "struct GlobalShortcutRecorder")
        policy_modifier = declaration_body(
            source, "func requiredKeyboardShortcutConflictPolicy()"
        )

        self.assertIn(".requiredKeyboardShortcutConflictPolicy()", recorder)
        self.assertIn(
            "keyboardShortcutsConflictPolicy(KeyboardShortcutConflictPolicy.required)",
            policy_modifier,
        )


if __name__ == "__main__":
    unittest.main()
