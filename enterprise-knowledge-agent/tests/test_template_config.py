import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from template_config import canonical_digest, load_fragments, toolbox_document, validate_cross_path
from ownership import cleanup_targets, write_ownership


class TemplateConfigTests(unittest.TestCase):
    def write(self, folder: Path, name: str, content: str) -> None:
        (folder / name).write_text(content, encoding="utf-8")

    def test_fragments_are_deterministically_ordered_and_substituted(self):
        with tempfile.TemporaryDirectory() as value:
            folder = Path(value)
            self.write(folder, "20-b.yaml", "name: b\nkind: mcp\nserver_url: ${ENDPOINT}\n")
            self.write(folder, "10-a.yaml", "name: a\nkind: web_search\n")
            result = load_fragments(folder, {"ENDPOINT": "https://example.test/mcp"})
            self.assertEqual([item["name"] for item in result], ["a", "b"])
            self.assertEqual(result[1]["server_url"], "https://example.test/mcp")

    def test_unresolved_variable_is_rejected(self):
        with tempfile.TemporaryDirectory() as value:
            folder = Path(value)
            self.write(folder, "a.yaml", "name: a\nserver_url: ${MISSING}\n")
            with self.assertRaisesRegex(ValueError, "MISSING"):
                load_fragments(folder, {})

    def test_plaintext_secret_is_rejected(self):
        with tempfile.TemporaryDirectory() as value:
            folder = Path(value)
            sensitive_field = "api_" + "key"
            sensitive_value = "embedded-" + "sensitive-value"
            self.write(folder, "a.yaml", f"name: a\n{sensitive_field}: {sensitive_value}\n")
            with self.assertRaisesRegex(ValueError, "Plaintext secret"):
                load_fragments(folder, {})

    def test_duplicate_name_and_endpoint_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Duplicate identifier"):
            validate_cross_path([{"name": "same"}], [{"name": "SAME"}])
        with self.assertRaisesRegex(ValueError, "Duplicate endpoint"):
            validate_cross_path(
                [{"name": "a", "mcpServerParameters": {"serverURL": "https://example.test/mcp/"}}],
                [{"name": "b", "server_url": "https://example.test/mcp"}],
            )

    def test_digest_is_stable(self):
        first = toolbox_document([{"name": "web_search", "type": "web_search"}])
        second = {"tools": [{"type": "web_search", "name": "web_search"}], "description": first["description"]}
        self.assertEqual(canonical_digest(first), canonical_digest(second))

    def test_required_kind_and_type_are_validated(self):
        with tempfile.TemporaryDirectory() as value:
            root = Path(value)
            source_folder = root / "knowledge-sources"
            source_folder.mkdir()
            self.write(source_folder, "bad.yaml", "name: bad\n")
            with self.assertRaisesRegex(ValueError, "kind"):
                load_fragments(source_folder, {})
            tool_folder = root / "toolbox-tools"
            tool_folder.mkdir()
            self.write(tool_folder, "bad.yaml", "name: bad\n")
            with self.assertRaisesRegex(ValueError, "type"):
                load_fragments(tool_folder, {})

    def test_duplicate_connection_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Duplicate connection"):
            validate_cross_path([], [
                {"name": "a", "project_connection_id": "same"},
                {"name": "b", "connection": "SAME"},
            ])

    def test_ownership_cleanup_excludes_external_resources(self):
        with tempfile.TemporaryDirectory() as value:
            path = Path(value) / "ownership.json"
            write_ownership(path, "https://search.example", "kb", ["default-ks", "customer-ks"], "demo-index", ["customer-index"])
            targets = cleanup_targets(path, "https://search.example/")
            self.assertIn(("indexes", "demo-index"), targets)
            self.assertNotIn(("indexes", "customer-index"), targets)

    def test_ownership_endpoint_mismatch_fails_closed(self):
        with tempfile.TemporaryDirectory() as value:
            path = Path(value) / "ownership.json"
            write_ownership(path, "https://one.example", "kb", [], "demo-index", [])
            with self.assertRaisesRegex(RuntimeError, "does not match"):
                cleanup_targets(path, "https://two.example")

    def test_ownership_accumulates_removed_configuration_objects(self):
        with tempfile.TemporaryDirectory() as value:
            path = Path(value) / "ownership.json"
            write_ownership(path, "https://search.example", "kb", ["default-ks", "optional-ks"], "demo-index", [])
            write_ownership(path, "https://search.example", "kb", ["default-ks"], "demo-index", [])
            self.assertIn(("knowledgesources", "optional-ks"), cleanup_targets(path, "https://search.example"))


if __name__ == "__main__":
    unittest.main()
