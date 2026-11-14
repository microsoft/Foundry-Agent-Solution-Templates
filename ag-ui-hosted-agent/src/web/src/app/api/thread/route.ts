import { gatewayUrl } from "@/lib/agent";
import { signedInUser, unauthorized } from "@/lib/user";

// Creates a Foundry conversation owned by the signed-in user; its conv_ ID is the AG-UI thread ID.
export async function POST(request: Request): Promise<Response> {
  const user = signedInUser(request.headers);
  if (!user) return unauthorized();
  const response = await fetch(`${gatewayUrl()}/threads`, { method: "POST", headers: { "x-user-id": user } });
  if (!response.ok) return Response.json({ error: `Gateway returned ${response.status}.` }, { status: 502 });
  return Response.json(await response.json());
}
