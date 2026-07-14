import "jsr:@supabase/functions-js@2.4.6/edge-runtime.d.ts";
import { handleAuthRequest } from "./auth.ts";

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is not configured.`);
  return value;
}

const supabaseUrl = requiredEnvironment("SUPABASE_URL");
const options = {
  supabaseUrl,
  publishableKey: Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    requiredEnvironment("SUPABASE_ANON_KEY"),
  publicBaseUrl: `${supabaseUrl}/functions/v1/shipbar-auth`,
};

Deno.serve((request) => handleAuthRequest(request, options));
