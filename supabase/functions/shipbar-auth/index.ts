import "jsr:@supabase/functions-js@2.4.6/edge-runtime.d.ts";
import { handleAuthRequest } from "./auth.ts";

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is not configured.`);
  return value;
}

const options = {
  supabaseUrl: requiredEnvironment("SUPABASE_URL"),
  publishableKey: requiredEnvironment("SUPABASE_PUBLISHABLE_KEY"),
};

Deno.serve((request) => handleAuthRequest(request, options));
