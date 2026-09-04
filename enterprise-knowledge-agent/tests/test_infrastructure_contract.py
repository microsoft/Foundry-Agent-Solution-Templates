import re
import shutil
import subprocess
import unittest
from copy import deepcopy
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
TERRAFORM = ROOT / "infra-terraform"
BICEP = ROOT / "infra-bicep"


class InfrastructureContractTests(unittest.TestCase):
    def manifests(self):
        return (
            yaml.safe_load((ROOT / "azure.yaml").read_text(encoding="utf-8")),
            yaml.safe_load((ROOT / "azure-bicep.yaml").read_text(encoding="utf-8")),
        )

    def test_terraform_is_default_and_bicep_is_explicit(self):
        default, bicep = self.manifests()

        self.assertEqual(default["name"], "enterprise-knowledge-agent-terraform")
        self.assertEqual(bicep["name"], "enterprise-knowledge-agent-bicep")
        self.assertEqual(default["metadata"]["template"], "enterprise-knowledge-agent-terraform@v1")
        self.assertEqual(bicep["metadata"]["template"], "enterprise-knowledge-agent-bicep@v1")
        self.assertEqual([layer["provider"] for layer in default["infra"]["layers"]], ["microsoft.foundry", "terraform"])
        self.assertEqual([layer["provider"] for layer in bicep["infra"]["layers"]], ["microsoft.foundry", "bicep"])
        self.assertEqual(default["infra"]["layers"][1]["path"], "infra-terraform")
        self.assertEqual(bicep["infra"]["layers"][1]["path"], "infra-bicep")
        self.assertEqual(default["infra"]["layers"][0]["path"], "infra-foundry")
        self.assertEqual(bicep["infra"]["layers"][0]["path"], "infra-foundry")
        self.assertEqual(bicep["services"]["enterprise-knowledge-agent"]["project"], "src")
        self.assertEqual(bicep["services"]["enterprise-knowledge-agent"]["hooks"]["postdeploy"]["run"], "../scripts/postdeploy.ps1")

    def test_provider_manifests_do_not_drift(self):
        default, bicep = self.manifests()
        common = []
        for source in (default, bicep):
            manifest = deepcopy(source)
            manifest.pop("name")
            manifest.pop("metadata")
            manifest.pop("infra")
            common.append(manifest)
        self.assertEqual(common[0], common[1])

    def test_documented_manifest_swap_matches_files(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        for command in (
            "Rename-Item azure.yaml azure-terraform.yaml",
            "Rename-Item azure-bicep.yaml azure.yaml",
            "Rename-Item azure.yaml azure-bicep.yaml",
            "Rename-Item azure-terraform.yaml azure.yaml",
        ):
            self.assertIn(command, readme)
        self.assertNotIn("scenarios/bicep", readme)

    def test_terraform_lock_file_is_committed_with_compatible_provider(self):
        lock_file = (TERRAFORM / ".terraform.lock.hcl").read_text(encoding="utf-8")
        self.assertIn('provider "registry.terraform.io/hashicorp/azurerm"', lock_file)
        self.assertIn('constraints = "~> 4.0"', lock_file)

    def test_bicep_and_terraform_publish_the_same_outputs(self):
        terraform = (TERRAFORM / "outputs.tf").read_text(encoding="utf-8")
        bicep = (BICEP / "search-service.bicep").read_text(encoding="utf-8")
        terraform_outputs = set(re.findall(r'output "([^"]+)"', terraform))
        bicep_outputs = set(re.findall(r'^output (\w+)', bicep, re.MULTILINE))
        self.assertEqual(terraform_outputs, bicep_outputs)
        self.assertEqual(terraform_outputs, {
            "AZURE_SEARCH_ENDPOINT", "AZURE_SEARCH_SERVICE_NAME",
            "AZURE_SEARCH_SERVICE_ID", "AZURE_SEARCH_PRINCIPAL_ID",
        })

    def test_both_implementations_preserve_search_security_and_rbac(self):
        terraform = "\n".join(path.read_text(encoding="utf-8") for path in TERRAFORM.glob("*.tf"))
        bicep = (BICEP / "search-service.bicep").read_text(encoding="utf-8")
        for value in ("Search Service Contributor", "Search Index Data Contributor"):
            self.assertIn(value, terraform)
        for role_id in ("7ca78c08-252a-4471-8644-bb5ff32d4ba0", "8ebe5a00-799e-43f5-93ac-243d3dce84a7"):
            self.assertIn(role_id, bicep)
        self.assertIn("local_authentication_enabled  = false", terraform)
        self.assertIn("disableLocalAuth: true", bicep)
        self.assertIn('contains(["demo", "byo"]', terraform)
        self.assertIn("@allowed(['demo', 'byo'])", bicep)

    def test_postprovision_consumes_layer_outputs_without_deploying_iac(self):
        hook = (ROOT / "scripts/postprovision.ps1").read_text(encoding="utf-8")
        self.assertIn("AZURE_SEARCH_ENDPOINT -Required", hook)
        self.assertIn("AZURE_SEARCH_SERVICE_ID -Required", hook)
        self.assertIn("Get-AzdEnvironmentValue -Name AZURE_FOUNDRY_RESOURCE_GROUP", hook)
        self.assertNotIn("$resourceGroup = Get-AzdEnvironmentValue -Name AZURE_RESOURCE_GROUP -Required", hook)
        self.assertNotIn("az deployment group create", hook)
        self.assertNotIn("./infra/search.bicep", hook)

    def test_byo_contract_is_fail_closed(self):
        outputs = (TERRAFORM / "outputs.tf").read_text(encoding="utf-8")
        self.assertEqual(outputs.count("precondition {"), 3)
        self.assertNotIn('check "byo_search_contract"', (TERRAFORM / "main.tf").read_text(encoding="utf-8"))
        self.assertIn("existingSearchEndpoint and existingSearchServiceId are required", outputs)

    def test_search_layer_consumes_foundry_resource_group_output(self):
        tfvars = (TERRAFORM / "main.tfvars.json").read_text(encoding="utf-8")
        parameters = (BICEP / "search.parameters.json").read_text(encoding="utf-8")
        wrapper = (BICEP / "search.bicep").read_text(encoding="utf-8")
        self.assertIn('${AZURE_FOUNDRY_RESOURCE_GROUP}', tfvars)
        self.assertNotIn('${AZURE_RESOURCE_GROUP}', tfvars)
        self.assertIn('${AZURE_FOUNDRY_RESOURCE_GROUP}', parameters)
        self.assertIn('scope: resourceGroup(resourceGroupName)', wrapper)

    @unittest.skipUnless(shutil.which("terraform"), "Terraform CLI is not installed")
    def test_terraform_formats_and_validates(self):
        for command in (
            ["terraform", "fmt", "-check", "-recursive"],
            ["terraform", "init", "-backend=false", "-input=false"],
            ["terraform", "validate", "-no-color"],
            ["terraform", "test", "-no-color"],
        ):
            result = subprocess.run(command, cwd=TERRAFORM, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
