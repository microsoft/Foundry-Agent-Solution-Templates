import ast
import json
import sys
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from template_config import load_fragments


class ContractTests(unittest.TestCase):
    def test_agent_has_exactly_one_toolbox_and_no_direct_search_client(self):
        tree = ast.parse((ROOT / "src/main.py").read_text(encoding="utf-8"))
        calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
        toolbox_calls = [node for node in calls if getattr(node.func, "id", None) == "FoundryToolbox"]
        self.assertEqual(len(toolbox_calls), 1)
        self.assertNotIn("SearchClient", (ROOT / "src/main.py").read_text(encoding="utf-8"))

    def test_default_sources_and_tools(self):
        sources = load_fragments(ROOT / "config/knowledge-sources")
        tools = load_fragments(ROOT / "config/toolbox-tools", {"KB_MCP_ENDPOINT": "https://example.test/kb/mcp", "KB_CONNECTION_NAME": "kb"})
        self.assertEqual([x["kind"] for x in sources], ["searchIndex", "mcpServer"])
        self.assertEqual([x["type"] for x in tools], ["mcp", "web_search"])

    def test_examples_are_inert_and_resolve_with_documented_values(self):
        self.assertEqual(len(load_fragments(ROOT / "config/knowledge-sources")), 2)
        examples = ROOT / "config/knowledge-sources/examples"
        environment = {
            "CUSTOMER_SEARCH_INDEX_NAME": "customer-index",
            "CUSTOMER_SEARCH_SEMANTIC_CONFIG": "semantic",
            "CUSTOMER_MCP_ENDPOINT": "https://example.test/mcp",
            "CUSTOMER_MCP_TOOL_NAME": "retrieve",
            "FABRIC_WORKSPACE_ID": "00000000-0000-0000-0000-000000000001",
            "FABRIC_ONTOLOGY_ID": "00000000-0000-0000-0000-000000000002",
        }
        self.assertEqual(len(load_fragments(examples, environment)), 3)
        tool_environment = {
            "WORKIQ_CALENDAR_CONNECTION_NAME": "calendar",
            "WORKIQ_MAIL_CONNECTION_NAME": "mail",
            "CUSTOMER_OPENAPI_SERVER_URL": "https://api.example.test",
            "CUSTOMER_A2A_CONNECTION_NAME": "agent",
            "CUSTOMER_A2A_AGENT_CARD_PATH": "agentCard/v1.0",
        }
        self.assertEqual(len(load_fragments(ROOT / "config/toolbox-tools/examples", tool_environment)), 4)

    def test_documents_contain_known_fact_and_citations(self):
        documents = json.loads((ROOT / "data/enterprise-documents.json").read_text(encoding="utf-8"))
        self.assertTrue(any("NS-4827" in item["content"] for item in documents))
        self.assertTrue(all(item["source_url"].startswith("https://") for item in documents))

    def test_manifest_uses_single_hosted_agent_and_pinned_model(self):
        manifest = yaml.safe_load((ROOT / "azure.yaml").read_text(encoding="utf-8"))
        agents = [v for v in manifest["services"].values() if v.get("host") == "azure.ai.agent"]
        self.assertEqual(len(agents), 1)
        deployment = manifest["services"]["ai-project"]["deployments"][0]
        self.assertEqual(deployment["name"], "gpt-5.4-mini")
        self.assertEqual(agents[0]["codeConfiguration"]["runtime"], "python_3_13")
        self.assertEqual(manifest["name"], "enterprise-knowledge-agent-terraform")
        self.assertEqual(manifest["metadata"]["template"], "enterprise-knowledge-agent-terraform@v1")


if __name__ == "__main__":
    unittest.main()
