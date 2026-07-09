import { corsHeaders, getUser, json, plaid } from "../_shared/plaid.ts";

// Creates a Hosted Link token so the app can open Plaid Link in a browser and, on completion,
// be redirected back to the app via a custom scheme.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const user = await getUser(req);
    const result = await plaid("/link/token/create", {
      client_name: "Restaurant Journal",
      language: "en",
      country_codes: ["US"],
      user: { client_user_id: user.id },
      products: ["transactions"],
      // Note: `is_mobile_app: true` would also require a registered https `redirect_uri`
      // (Universal Link) — only needed for app-to-app OAuth banks. For sandbox / password-based
      // institutions, the custom-scheme completion redirect alone works and ASWebAuthenticationSession
      // catches it. Add the Universal Link + is_mobile_app before shipping OAuth banks in production.
      hosted_link: {
        completion_redirect_uri: "restaurantjournal://plaid-complete",
      },
    });
    return json({ link_token: result.link_token, hosted_link_url: result.hosted_link_url });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 400);
  }
});
