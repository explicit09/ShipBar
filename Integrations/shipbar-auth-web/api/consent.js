const upstreamBase =
  "https://uyutoheyrvodwcpufkda.supabase.co/functions/v1/shipbar-auth/oauth/consent";

export default async function handler(request, response) {
  if (request.method !== "GET") {
    response.status(405).send("Method not allowed");
    return;
  }

  const authorizationId = typeof request.query.authorization_id === "string"
    ? request.query.authorization_id
    : "";
  const upstream = new URL(upstreamBase);
  if (authorizationId) {
    upstream.searchParams.set("authorization_id", authorizationId);
  }

  const result = await fetch(upstream, {
    headers: { Accept: "text/html" },
  });
  if (!result.ok) {
    response.status(502).send("ShipBar authorization is temporarily unavailable.");
    return;
  }

  response.setHeader("Content-Type", "text/html; charset=utf-8");
  response.setHeader("Cache-Control", "no-store");
  response.setHeader("Referrer-Policy", "no-referrer");
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("X-Frame-Options", "DENY");
  response.setHeader(
    "Content-Security-Policy",
    "default-src 'none'; script-src 'unsafe-inline' https://esm.sh; " +
      "style-src 'unsafe-inline'; connect-src https://uyutoheyrvodwcpufkda.supabase.co; " +
      "img-src 'self' data:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
  );
  response.status(200).send(await result.text());
}
