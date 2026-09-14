import ast
import json
import os
import sys
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from template_config import load_fragments
from provision import scope_knowledge_sources, scoped_name


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

    def test_microsoft_learn_preserves_mcp_results_without_reranker_filtering(self):
        sources = load_fragments(ROOT / "config/knowledge-sources")
        learn = next(source for source in sources if source["name"] == "microsoft-learn-ks")
        tool = learn["mcpServerParameters"]["tools"][0]
        self.assertEqual(tool["name"], "microsoft_docs_search")
        self.assertEqual(tool["resultsProcessing"], "none")

    def test_agent_and_knowledge_base_preserve_source_urls_and_page_metadata(self):
        agent = (ROOT / "src/main.py").read_text(encoding="utf-8")
        provisioning = (ROOT / "scripts/provision.py").read_text(encoding="utf-8")
        self.assertIn("exact HTTPS source URLs", agent)
        self.assertIn("page or section metadata", agent)
        self.assertIn('"answerInstructions":', provisioning)
        self.assertIn("exact source URLs and page or section metadata", provisioning)

    def test_byo_example_returns_document_content_as_grounding_not_only_metadata(self):
        example = yaml.safe_load(
            (ROOT / "config/knowledge-sources/examples/search-index.example.yaml").read_text(encoding="utf-8")
        )
        fields = {field["name"] for field in example["searchIndexParameters"]["sourceDataFields"]}
        self.assertTrue({"content", "source_url", "page_number"} <= fields)

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

    def test_readme_covers_cold_start_and_layered_preview(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("azd extension install microsoft.foundry", readme)
        self.assertIn("terraform version", readme)
        self.assertIn("azd provision --preview foundry --no-prompt", readme)
        self.assertIn("two-phase", readme)
        self.assertIn("pwsh --version", readme)
        self.assertIn("python -m pip --version", readme)
        self.assertGreater(
            readme.index("Rename-Item azure.yaml azure-bicep.yaml"),
            readme.index("azd down --purge --force"),
        )

    def test_byo_docs_query_customer_search_identity(self):
        onboarding = (ROOT / "docs/data-onboarding.md").read_text(encoding="utf-8")
        self.assertIn("az search service show --ids $searchId --query identity.principalId", onboarding)
        self.assertIn("Cognitive Services User", onboarding)

    def test_direct_kb_endpoint_is_exported_without_toolbox_setup(self):
        source = (ROOT / "scripts/provision.py").read_text(encoding="utf-8")
        create_search_objects = source.split("def create_search_objects", 1)[1].split("def preflight_external_sources", 1)[0]
        self.assertIn('azd_set("KB_MCP_ENDPOINT", knowledge_base_endpoint(client))', create_search_objects)

    def test_search_objects_are_isolated_by_environment(self):
        previous = os.environ.get("AZURE_ENV_NAME")
        try:
            os.environ["AZURE_ENV_NAME"] = "customer-dev"
            dev_name = scoped_name("enterprise-knowledge-kb")
            sources = scope_knowledge_sources(load_fragments(ROOT / "config/knowledge-sources"))
            self.assertTrue(all(name["name"].endswith(scoped_name("x").split("-")[-1]) for name in sources))
            self.assertNotEqual(sources[0]["searchIndexParameters"]["searchIndexName"], "enterprise-documents")
            os.environ["AZURE_ENV_NAME"] = "customer-prod"
            self.assertNotEqual(dev_name, scoped_name("enterprise-knowledge-kb"))
        finally:
            if previous is None:
                os.environ.pop("AZURE_ENV_NAME", None)
            else:
                os.environ["AZURE_ENV_NAME"] = previous


if __name__ == "__main__":
    unittest.main()
