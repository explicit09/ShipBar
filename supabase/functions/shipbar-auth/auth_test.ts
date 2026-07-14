import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { handleAuthRequest } from "./auth.ts";

const options = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "sb_publishable_test",
  publicBaseUrl: "https://example.supabase.co/functions/v1/shipbar-auth",
};

Deno.test("auth root redirects to the canonical consent path", async () => {
  const response = await handleAuthRequest(
    new Request("https://example.supabase.co/functions/v1/shipbar-auth"),
    options,
  );
  assertEquals(response.status, 302);
  assertEquals(
    response.headers.get("Location"),
    "https://example.supabase.co/functions/v1/shipbar-auth/oauth/consent",
  );
});

Deno.test("auth root preserves the public HTTPS function path behind the edge proxy", async () => {
  const response = await handleAuthRequest(
    new Request("http://example.supabase.co/shipbar-auth"),
    options,
  );
  assertEquals(response.status, 302);
  assertEquals(
    response.headers.get("Location"),
    "https://example.supabase.co/functions/v1/shipbar-auth/oauth/consent",
  );
});

Deno.test("consent page is mobile ready and never permits self-registration", async () => {
  const response = await handleAuthRequest(
    new Request(
      "https://example.supabase.co/functions/v1/shipbar-auth/oauth/consent?authorization_id=auth-1",
    ),
    options,
  );
  assertEquals(response.status, 200);
  const html = await response.text();
  assertStringIncludes(html, "width=device-width");
  assertStringIncludes(html, "shouldCreateUser: false");
  assertStringIncludes(html, "getAuthorizationDetails");
  assertStringIncludes(html, "approveAuthorization");
  assertStringIncludes(html, "denyAuthorization");
  assertStringIncludes(html, "sb_publishable_test");
  assertEquals(html.includes("service_role"), false);
});

Deno.test("unknown paths fail closed", async () => {
  const response = await handleAuthRequest(
    new Request(
      "https://example.supabase.co/functions/v1/shipbar-auth/not-real",
    ),
    options,
  );
  assertEquals(response.status, 404);
});
