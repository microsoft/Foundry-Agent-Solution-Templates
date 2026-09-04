# Foundry Agent Solution Templates

Reference solution templates for building and deploying Microsoft Foundry
agents. Each template is self-contained in its own subfolder.

## Solution templates

| Template | Description |
|---|---|
| 1. [Private-network Hosted Agent](private-network-hosted-agent/) | Demonstrates security and data-protection controls for a Hosted Agent solution, including VNet isolation, private endpoints, restricted egress, managed identity, and customer-managed keys. |
| 2. [APIM-hosted Foundry Agent](apim-hosted-agent/) | Demonstrates governed agent, model, and tool traffic through API Management. |
| 3. Enterprise Knowledge Agent *(coming soon)* | Demonstrates grounding custom data from Fabric, databases, org APIs, and IQs, and how typical RAG is set up with a hosted agent, including connection and authentication best practices. |
| 4. Multi-agent *(coming soon)* | Demonstrates multi-agent patterns with A2A orchestration, agent registry, endpoints, A2A/MCP routing, shared observability, cross-agent auth, and governance policies. |
| 5. Regulated/Sovereign Agent *(coming soon)* | Demonstrates an agent setup for strict data residency and private deployments in regulated environments. |
| 6. M365/Teams + Hosted Agent *(coming soon)* | Demonstrates a hosted agent backend surfaced via Teams/M365, with recommended auth and protocol setup. |
| 7. Auditable self-managed agent with observability *(coming soon)* | Demonstrates integrating a hosted agent with self-managed observability for operations and FinOps, including exporting telemetry to popular third-party analytics stores. |
| 8. Self-improving Agent *(coming soon)* | Demonstrates a secure flow using real-world data to perform RL/FT on deployed agents and models in production. |
| 9. Dev/test/prod environments with CI/CD *(coming soon)* | Demonstrates isolated dev/test/prod environments for Foundry Agents and how to link them via CI/CD. |
| 10. Multiple clients for a Foundry hosted agent *(coming soon)* | Demonstrates a Foundry hosted agent backend with recommended patterns for serving UX from popular client frontends. |
