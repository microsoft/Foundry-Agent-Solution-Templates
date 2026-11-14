"use client";
import { useState } from "react";
import { useInterrupt } from "@copilotkit/react-core/v2";
import { AGENT_ID } from "@/lib/agent";

type Call = { name?: string; arguments?: Record<string, unknown> };
type Pending = { id: string; message?: string; metadata?: unknown };
type Resolve = (payload?: unknown, interruptId?: string) => Promise<unknown>;

function ApprovalCard({ interrupt, resolve }: { interrupt: Pending; resolve: Resolve }) {
  const [decision, setDecision] = useState<boolean>();
  const call = (interrupt.metadata as { agent_framework?: { function_call?: Call } })?.agent_framework?.function_call;
  // The payload contract is {approved: boolean}. Reject with approved=false, not cancel().
  const decide = (approved: boolean) => {
    setDecision(approved);
    void resolve({ approved }, interrupt.id);
  };
  return (
    <div className="card approval" data-testid="approval-card">
      <strong>Approval required: {call?.name ?? "action"}</strong>
      <pre>{JSON.stringify(call?.arguments ?? {}, null, 2)}</pre>
      {decision === undefined ? (
        <div className="actions">
          <button onClick={() => decide(true)}>Approve</button>
          <button className="secondary" onClick={() => decide(false)}>Reject</button>
        </div>
      ) : (
        <p>{decision ? "Approved" : "Rejected"}</p>
      )}
    </div>
  );
}

export function ApprovalUI() {
  useInterrupt({
    agentId: AGENT_ID,
    render: ({ interrupts, resolve }) => (
      <>{interrupts.map((i) => <ApprovalCard key={i.id} interrupt={i as Pending} resolve={resolve} />)}</>
    ),
  });
  return null;
}
