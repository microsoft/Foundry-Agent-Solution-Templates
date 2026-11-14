"use client";
import { useEffect, useState } from "react";
import { CopilotChat, CopilotKitProvider } from "@copilotkit/react-core/v2";
import "@copilotkit/react-core/v2/styles.css";
import { AGENT_ID } from "@/lib/agent";
import { ApprovalUI } from "./approval";
import { ToolCalls } from "./tools";

export default function Page() {
  const [threadId, setThreadId] = useState<string>();
  const [error, setError] = useState<string>();

  useEffect(() => {
    fetch("/api/thread", { method: "POST" })
      .then(async (r) => {
        const body = await r.json().catch(() => ({}));
        if (!r.ok || typeof body.threadId !== "string" || !body.threadId.startsWith("conv_")) {
          throw new Error(body.error ?? `Could not start a conversation (HTTP ${r.status}).`);
        }
        setThreadId(body.threadId);
      })
      .catch((e: unknown) => setError(e instanceof Error ? e.message : String(e)));
  }, []);

  return (
    <main>
      <header>
        <h1>Claims triage</h1>
        <p>Synthetic data. Escalations need your approval.</p>
      </header>
      {error && <p role="alert">{error}</p>}
      {!error && !threadId && <p>Starting conversation…</p>}
      {threadId && (
        <CopilotKitProvider runtimeUrl="/api/copilotkit">
          <ToolCalls />
          <ApprovalUI />
          <CopilotChat agentId={AGENT_ID} threadId={threadId} />
        </CopilotKitProvider>
      )}
    </main>
  );
}
