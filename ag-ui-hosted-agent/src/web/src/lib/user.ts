// Container Apps built-in authentication signs the user in and injects this header;
// it replaces any value a client sends. Local `next dev` has no sign-in, so it uses a fixed user.
export const PRINCIPAL_HEADER = "x-ms-client-principal-id";

export function signedInUser(headers: Headers, env: NodeJS.ProcessEnv = process.env): string | undefined {
  const principal = headers.get(PRINCIPAL_HEADER)?.trim();
  if (principal) return principal;
  return env.NODE_ENV === "production" ? undefined : (env.LOCAL_USER_ID ?? "local-user");
}

export const unauthorized = () => Response.json({ error: "Sign-in required." }, { status: 401 });
