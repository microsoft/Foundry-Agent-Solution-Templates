import { HttpAgent } from "@ag-ui/client";
import { CopilotRuntime, createCopilotRuntimeHandler } from "@copilotkit/runtime/v2";
import { AGENT_ID, gatewayUrl } from "@/lib/agent";
import { signedInUser, unauthorized } from "@/lib/user";

const runtime = new CopilotRuntime({
  // Built per request so the gateway learns who is calling; it checks that user owns the thread.
  agents: ({ request }) => ({
    [AGENT_ID]: new HttpAgent({
      url: `${gatewayUrl()}/`,
      headers: { "x-user-id": signedInUser(request.headers) ?? "" },
    }),
  }),
});
const handler = createCopilotRuntimeHandler({ runtime, basePath: "/api/copilotkit" });

async function guarded(request: Request): Promise<Response> {
  return signedInUser(request.headers) ? handler(request) : unauthorized();
}

export const GET = guarded;
export const POST = guarded;
