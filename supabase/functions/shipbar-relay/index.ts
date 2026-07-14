import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.110.3";
import { SupabaseRelayRepository } from "./repository.ts";
import { handleRelayRequest } from "./router.ts";

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is not configured.`);
  return value;
}

const supabaseUrl = requiredEnvironment("SUPABASE_URL");
const secretKey = Deno.env.get("SUPABASE_SECRET_KEY") ?? requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
const repository = new SupabaseRelayRepository(createClient(supabaseUrl, secretKey, {
  auth: { persistSession: false, autoRefreshToken: false },
}));
const dependencies = {
  ownerId: requiredEnvironment("SHIPBAR_OWNER_ID"),
  keyHash: requiredEnvironment("SHIPBAR_RELAY_KEY_HASH"),
  repository,
};

Deno.serve((request) => handleRelayRequest(request, dependencies));
