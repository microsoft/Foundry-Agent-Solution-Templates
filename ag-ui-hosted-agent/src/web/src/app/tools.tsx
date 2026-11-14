"use client";
import { useDefaultRenderTool } from "@copilotkit/react-core/v2";

// Tools run on the hosted agent; without a renderer their calls and results are invisible in the chat.
export function ToolCalls() {
  useDefaultRenderTool({
    render: ({ name, status, result }) =>
      name === "confirm_changes" ? null : (
        <div className="card tool" data-testid="tool-call">
          <strong>{name}</strong> <span className="status">{status}</span>
          {result !== undefined && <pre>{typeof result === "string" ? result : JSON.stringify(result, null, 2)}</pre>}
        </div>
      ),
  });
  return null;
}
