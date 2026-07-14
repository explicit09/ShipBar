export type AuthPageOptions = {
  supabaseUrl: string;
  publishableKey: string;
  publicBaseUrl: string;
};

function safeJson(value: unknown): string {
  return JSON.stringify(value).replaceAll("<", "\\u003c");
}

function consentPage(options: AuthPageOptions): string {
  const config = safeJson(options);
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="color-scheme" content="dark">
  <title>Connect ShipBar</title>
  <style>
    :root { color-scheme: dark; --ink:#090a0d; --panel:#14161c; --line:#2c3039; --paper:#f2f3f5; --muted:#9da3af; --signal:#1677ff; --violet:#956bff; --good:#4ed3a1; }
    * { box-sizing:border-box; }
    html, body { min-height:100%; }
    body { margin:0; display:grid; place-items:center; padding:max(22px, env(safe-area-inset-top)) max(18px, env(safe-area-inset-right)) max(22px, env(safe-area-inset-bottom)) max(18px, env(safe-area-inset-left)); background:radial-gradient(circle at 15% 8%, #1c2230 0, transparent 32%), radial-gradient(circle at 90% 92%, #1b1530 0, transparent 34%), var(--ink); color:var(--paper); font-family:"Avenir Next", Avenir, ui-rounded, sans-serif; }
    main { width:min(100%, 460px); position:relative; overflow:hidden; border:1px solid var(--line); border-radius:28px; padding:clamp(24px, 6vw, 38px); background:linear-gradient(145deg, rgba(25,28,35,.98), rgba(14,16,21,.98)); box-shadow:0 34px 90px rgba(0,0,0,.48); }
    main::before { content:""; position:absolute; width:210px; height:210px; right:-110px; top:-110px; border:1px solid rgba(149,107,255,.46); border-radius:50%; box-shadow:inset 0 0 55px rgba(149,107,255,.12); }
    .mark { width:54px; height:54px; display:grid; place-items:center; border-radius:18px; background:linear-gradient(145deg, var(--signal), var(--violet)); box-shadow:0 12px 32px rgba(22,119,255,.26); font-size:25px; transform:rotate(-3deg); }
    .eyebrow { margin:24px 0 8px; color:#9abffc; font-size:12px; font-weight:750; letter-spacing:.16em; text-transform:uppercase; }
    h1 { margin:0; max-width:350px; font-family:Georgia, "Times New Roman", serif; font-size:clamp(36px, 10vw, 52px); font-weight:500; line-height:.98; letter-spacing:-.04em; }
    .lede { margin:18px 0 26px; color:var(--muted); font-size:16px; line-height:1.55; }
    .status { min-height:22px; margin:0 0 14px; color:#b8d3ff; font-size:14px; line-height:1.45; }
    .status.error { color:#ff9b9b; }
    label { display:block; margin:0 0 8px; color:#d7dae0; font-size:13px; font-weight:700; }
    input { width:100%; height:54px; border:1px solid #3a3f4b; border-radius:16px; padding:0 16px; background:#0c0e13; color:var(--paper); font:inherit; outline:none; transition:border-color .18s, box-shadow .18s; }
    input:focus { border-color:#438eff; box-shadow:0 0 0 4px rgba(22,119,255,.15); }
    button { width:100%; min-height:52px; border:0; border-radius:16px; padding:13px 18px; font:750 15px/1.2 "Avenir Next", Avenir, sans-serif; cursor:pointer; transition:transform .15s, filter .15s, opacity .15s; }
    button:hover { filter:brightness(1.08); transform:translateY(-1px); }
    button:active { transform:translateY(0); }
    button:disabled { cursor:wait; opacity:.55; transform:none; }
    .primary { margin-top:12px; background:linear-gradient(110deg, var(--signal), #745dff); color:white; }
    .secondary { background:#272b34; color:var(--paper); }
    .danger { background:transparent; border:1px solid #454a55; color:#bcc1ca; }
    .actions { display:grid; gap:10px; margin-top:22px; }
    .card { margin-top:20px; padding:16px; border:1px solid #303540; border-radius:18px; background:#0e1016; }
    .client { margin:0; font-weight:750; font-size:17px; }
    .scopes { display:flex; flex-wrap:wrap; gap:7px; margin:12px 0 0; padding:0; list-style:none; }
    .scopes li { padding:6px 9px; border:1px solid #343a47; border-radius:999px; color:#b9c0cb; font-size:12px; }
    .fine { margin:18px 0 0; color:#717986; font-size:12px; line-height:1.5; }
    [hidden] { display:none !important; }
    @media (max-width:520px) { body { place-items:end center; padding-left:0; padding-right:0; padding-bottom:0; } main { width:100%; border-radius:28px 28px 0 0; border-bottom:0; padding-bottom:max(28px, env(safe-area-inset-bottom)); } }
    @media (prefers-reduced-motion:no-preference) { main { animation:arrive .45s cubic-bezier(.2,.8,.2,1) both; } @keyframes arrive { from { opacity:0; transform:translateY(18px) scale(.985); } } }
  </style>
</head>
<body>
  <main>
    <div class="mark" aria-hidden="true">➤</div>
    <p class="eyebrow">Private connection</p>
    <h1>Bring ShipBar into ChatGPT.</h1>
    <p class="lede" id="lede">Sign in with the one email invited to your private ShipBar relay. New accounts cannot be created here.</p>
    <p class="status" id="status" role="status" aria-live="polite"></p>

    <form id="login">
      <label for="email">Your approved email</label>
      <input id="email" name="email" type="email" inputmode="email" autocomplete="email" required placeholder="you@example.com">
      <button class="primary" type="submit">Email me a secure link</button>
    </form>

    <section id="consent" hidden>
      <div class="card">
        <p class="client" id="client">ChatGPT wants to connect</p>
        <ul class="scopes" id="scopes"></ul>
      </div>
      <div class="actions">
        <button class="primary" id="approve" type="button">Connect ShipBar</button>
        <button class="danger" id="deny" type="button">Not now</button>
        <button class="secondary" id="signout" type="button">Use another email</button>
      </div>
    </section>
    <p class="fine">Read actions inspect your private queue. Write actions ask according to your ChatGPT app permissions. Queued never means running until ShipBar reports it.</p>
  </main>
  <script>window.__SHIPBAR_AUTH__=${config};</script>
  <script type="module">
    import { createClient } from "https://esm.sh/@supabase/supabase-js@2.110.3";
    const config = window.__SHIPBAR_AUTH__;
    const supabase = createClient(config.supabaseUrl, config.publishableKey, {
      auth: { detectSessionInUrl: true, persistSession: true, autoRefreshToken: true }
    });
    const byId = (id) => document.getElementById(id);
    const status = byId("status");
    const login = byId("login");
    const consent = byId("consent");
    const authorizationId = new URL(location.href).searchParams.get("authorization_id");
    const redirectBack = location.origin + location.pathname + (authorizationId ? "?authorization_id=" + encodeURIComponent(authorizationId) : "");

    function report(message, isError = false) {
      status.textContent = message;
      status.classList.toggle("error", isError);
    }
    function busy(value) {
      document.querySelectorAll("button").forEach((button) => button.disabled = value);
    }
    async function loadConsent() {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) { login.hidden = false; consent.hidden = true; return; }
      if (!authorizationId) { report("This authorization link is incomplete. Start the connection again from ChatGPT.", true); return; }
      report("Checking the connection request…");
      const { data, error } = await supabase.auth.oauth.getAuthorizationDetails(authorizationId);
      if (error || !data) { report(error?.message || "This connection request is no longer valid.", true); return; }
      if (!("authorization_id" in data) && data.redirect_url) { location.assign(data.redirect_url); return; }
      login.hidden = true;
      consent.hidden = false;
      byId("client").textContent = (data.client?.name || "ChatGPT") + " wants to connect";
      const scopes = String(data.scope || "shipbar.read shipbar.write").split(/\\s+/).filter(Boolean);
      byId("scopes").replaceChildren(...scopes.map((scope) => Object.assign(document.createElement("li"), { textContent: scope })));
      report("Signed in. Review and approve this private connection.");
    }

    login.addEventListener("submit", async (event) => {
      event.preventDefault(); busy(true); report("Sending your secure sign-in link…");
      const email = new FormData(login).get("email");
      const { error } = await supabase.auth.signInWithOtp({
        email,
        options: { shouldCreateUser: false, emailRedirectTo: redirectBack }
      });
      busy(false);
      report(error ? error.message : "Check your email, then open the secure link on this device.", Boolean(error));
    });
    byId("approve").addEventListener("click", async () => {
      busy(true); report("Connecting ShipBar…");
      const { data, error } = await supabase.auth.oauth.approveAuthorization(authorizationId);
      if (error) { busy(false); report(error.message, true); return; }
      location.assign(data.redirect_url);
    });
    byId("deny").addEventListener("click", async () => {
      busy(true);
      const { data, error } = await supabase.auth.oauth.denyAuthorization(authorizationId);
      if (error) { busy(false); report(error.message, true); return; }
      location.assign(data.redirect_url);
    });
    byId("signout").addEventListener("click", async () => { await supabase.auth.signOut(); location.reload(); });
    supabase.auth.onAuthStateChange(() => setTimeout(loadConsent, 0));
    await loadConsent();
  </script>
</body>
</html>`;
}

export function handleAuthRequest(
  request: Request,
  options: AuthPageOptions,
): Promise<Response> {
  const url = new URL(request.url);
  const marker = "/shipbar-auth";
  const index = url.pathname.indexOf(marker);
  const path = index >= 0
    ? url.pathname.slice(index + marker.length) || "/"
    : url.pathname;
  if (request.method !== "GET") {
    return Promise.resolve(new Response("Method not allowed", { status: 405 }));
  }
  if (path === "/") {
    return Promise.resolve(
      Response.redirect(`${options.publicBaseUrl}/oauth/consent`, 302),
    );
  }
  if (path !== "/oauth/consent") {
    return Promise.resolve(new Response("Not found", { status: 404 }));
  }
  return Promise.resolve(
    new Response(consentPage(options), {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
        "Content-Security-Policy":
          `default-src 'none'; script-src 'unsafe-inline' https://esm.sh; style-src 'unsafe-inline'; connect-src ${options.supabaseUrl}; img-src 'self' data:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'`,
        "Referrer-Policy": "no-referrer",
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
      },
    }),
  );
}
