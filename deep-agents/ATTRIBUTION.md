# Attribution

This template is inspired by LangChain's Deep Research example, particularly
planning, research delegation, search budgets, stopping conditions, citation
consolidation and the `think_tool` pattern. It is not an identical port: prompts
are tailored to a fictional sales-informed marketing scenario with local skills,
approved file writes/code execution, a session workspace and checkpoints.
Foundry Toolbox replaces Tavily; model access and hosting use langchain-azure
adapters. The upstream sources and notices are retained below.

- [Deep Agents deep_research](https://github.com/langchain-ai/deepagents/tree/c3a041e3d8f593e4e4c9bfc273d52264ceff165b/examples/deep_research),
  commit `c3a041e3d8f593e4e4c9bfc273d52264ceff165b`.
- [langchain-azure Responses hosting](https://github.com/langchain-ai/langchain-azure/tree/b99bb28adf948b55526b64994e49f7866f1d1cb3/samples/hosting/langgraph-hosted-agents/responses),
  commit `b99bb28adf948b55526b64994e49f7866f1d1cb3`.
- [langchain-azure Foundry Toolbox example](https://github.com/langchain-ai/langchain-azure/tree/e5b12a3e7fa639374375c07dd687450fa35f44d2/samples/hosting/langgraph-hosted-agents/responses/04_foundry_toolbox),
  commit `e5b12a3e7fa639374375c07dd687450fa35f44d2` (SDK tool loading).
- [Foundry Deep Agents sample](https://github.com/microsoft-foundry/foundry-samples/tree/e0f4042a0080158d4fe351dfe7c3fb47a9b75a5e/samples/python/hosted-agents/langgraph/responses/11-deep-agents),
  commit `e0f4042a0080158d4fe351dfe7c3fb47a9b75a5e` (hosting and native azd layout).

## MIT notices

Deep Agents: Copyright (c) LangChain, Inc.

langchain-azure: Copyright (c) 2024 LangChain

Foundry samples: Copyright (c) 2025 Microsoft Corporation

The following MIT license applies to each of the upstream sources above:

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
