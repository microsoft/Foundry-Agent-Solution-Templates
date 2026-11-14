// One name in three places: the runtime agents key, CopilotChat agentId and useInterrupt.
export const AGENT_ID = "claims-triage";

export function gatewayUrl(env: NodeJS.ProcessEnv = process.env): string {
  const url = env.AGUI_GATEWAY_URL;
  if (!url) throw new Error("AGUI_GATEWAY_URL is not set.");
  return url.replace(/\/$/, "");
}
