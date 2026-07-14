import "jsr:@supabase/functions-js@2.4.6/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.110.3";
import { handleMcpRequest } from "./mcp.ts";
import { SupabaseRelayRepository } from "../shipbar-relay/repository.ts";

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is not configured.`);
  return value;
}

const supabaseUrl = requiredEnvironment("SUPABASE_URL");
const secretKey = Deno.env.get("SUPABASE_SECRET_KEY") ??
  requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
const ownerId = requiredEnvironment("SHIPBAR_OWNER_ID");
const authorizedUserId = requiredEnvironment("SHIPBAR_AUTH_USER_ID");
const resourceUrl = `${supabaseUrl}/functions/v1/shipbar-mcp`;
const authorizationServer = `${supabaseUrl}/auth/v1`;
const client = createClient(supabaseUrl, secretKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const repository = new SupabaseRelayRepository(client);

Deno.serve((request) =>
  handleMcpRequest(request, {
    ownerId,
    resourceUrl,
    authorizationServer,
    repository,
    authorize: async (token) => {
      if (!token) return false;
      const { data, error } = await client.auth.getUser(token);
      return !error && data.user?.id === authorizedUserId;
    },
  })
);
