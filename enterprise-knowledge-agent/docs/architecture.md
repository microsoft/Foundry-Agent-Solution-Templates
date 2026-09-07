# Architecture

The default deployment routes the Microsoft Foundry Hosted Agent through one Foundry Toolbox. The Toolbox exposes the Foundry IQ Knowledge Base and Web IQ.

The dashed connections show optional extensions. A knowledge-only agent can connect directly to the Foundry IQ Knowledge Base without a Toolbox. Some capabilities can be integrated either as Knowledge Sources or as Toolbox peer tools, depending on the retrieval, action, identity, and operational requirements. The diagram shows template defaults and supported extension points; it does not recommend connecting the same capability through both paths. See [Data source and tool placement](data-sources.md) for the selection criteria and maintained template paths.

```mermaid
flowchart LR
    User[User or application] --> Foundry[Microsoft Foundry<br/>Hosted Knowledge Agent]
    Foundry -->|Default| Toolbox[Foundry Toolbox]
    Toolbox -->|Default| IQ[Foundry IQ<br/>Knowledge Base]

    Foundry -.->|Optional direct connection<br/>without Toolbox| IQ

    IQ -->|Default knowledge source| Search[Azure AI Search<br/>enterprise index]
    IQ -->|Default knowledge source| Learn[Microsoft Learn<br/>MCP server]

    IQ -.->|Optional knowledge source| CustomerSearch[Customer-owned<br/>Search indexes]
    IQ -.->|Optional knowledge source| MCP[Read-only MCP servers]
    IQ -.->|Optional knowledge source| Fabric[Fabric IQ<br/>ontology]
    IQ -.->|Optional knowledge source| WorkIQ[Work IQ]
    IQ -.->|Optional knowledge source| WebIQ[Web IQ]

    Toolbox -->|Default tool| WebIQ
    Toolbox -.->|Optional source-native tool| WorkIQ
    Toolbox -.->|Optional tool| API[Business APIs<br/>OpenAPI]
    Toolbox -.->|Optional tool| A2A[Remote agents<br/>A2A]

    classDef core fill:#e8f2ff,stroke:#2878c8,color:#111
    classDef default fill:#eaf7ed,stroke:#3b8f50,color:#111
    classDef extension fill:#fff4dd,stroke:#c88719,color:#111

    class Foundry,Toolbox core
    class IQ,Search,Learn default
    class CustomerSearch,MCP,Fabric,WorkIQ,WebIQ,API,A2A extension
```

Solid lines represent the default template. Dashed lines represent optional connections or sources that require adopter-specific configuration and validation.
