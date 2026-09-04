# Foundry Agent Solution Templates

Reference solution templates for building and deploying Microsoft Foundry
agents. Each template is self-contained in its own subfolder.

## Solution templates

| Template | Description |
|---|---|
| 1. [Private-network Hosted Agent](private-network-hosted-agent/) | Demonstrates security and data-protection controls for a Hosted Agent solution, including VNet isolation, private endpoints, restricted egress, managed identity, and customer-managed keys. |
| 2. [APIM-hosted Foundry Agent](apim-hosted-agent/) | Demonstrates governed agent, model, and tool traffic through API Management. |
| 3. Enterprise Knowledge Agent | Demonstrates grounding custom data from Fabric, DB, org API, IQs, and how typical RAG is setup with hosted agent. Connection and auth best practice. |
| 4. Multi-Agent | Demonstrates multi-agent with a2a orchestration on a typical setup and management with agent registry, endpoints, A2A/MCP routing, shared observability, cross-agent auth and governing policy. |
| 5. Regulated/Sovereign Agent | Demonstrates a setup for agent scenario with strict data residency, private deployment, regulated environments. |
| 6. M365/Teams + Hosted Agent | Demonstrates hosted agent as backend, surfacing UI via Teams/M365 for client experience with proper auth and protocol setup. |
| 7. Auditable self managed agent w/ observability | Demonstrates reference integration on connecting hosted agent with custom managed observability for agent operation and FinOps, and how to exporting all observability data to popular 3P data analytics store.	 |
| 8. Self improving Agent | Demonstrates a working and secure environment and flow to use real-world data to do RL/FT of deployed agent and model in production. |
| 9. Dev, test, production environments with CI/CD | Demonstrates setup of isolated environments for dev/test/prod around Foundry Agents and how to link these together via CI/CD. |
| 10. Multiple clients for Foundry hosted agent | Demonstrates Foundry hosted agent as backend, offer recommended pattern to serve UX on popular clients as agent frontend. |
