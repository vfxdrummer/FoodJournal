import { corsHeaders, getUser, json, plaid, serviceClient } from "../_shared/plaid.ts";

// After the user finishes Hosted Link, the app calls this with the link_token. We fetch the session
// results server-side, exchange the public token for a long-lived access token, and store it.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const user = await getUser(req);
    const { link_token } = await req.json();
    if (!link_token) throw new Error("Missing link_token");

    // Retrieve the Hosted Link session to get the public token(s).
    const session = await plaid("/link/token/get", { link_token });
    const sessions = session.link_sessions ?? [];
    const publicToken =
      sessions
        .flatMap((s: any) => s.results?.item_add_results ?? [])
        .map((r: any) => r.public_token)
        .find((t: string | undefined) => !!t) ??
      sessions[0]?.on_success?.public_token;
    if (!publicToken) throw new Error("Link isn't finished yet — try again in a moment.");

    // Exchange for a long-lived access token.
    const exchange = await plaid("/item/public_token/exchange", { public_token: publicToken });
    const accessToken = exchange.access_token as string;
    const itemId = exchange.item_id as string;

    // Best-effort institution name (non-fatal).
    let institution: string | null = null;
    try {
      const item = await plaid("/item/get", { access_token: accessToken });
      const institutionId = item.item?.institution_id;
      if (institutionId) {
        const inst = await plaid("/institutions/get_by_id", {
          institution_id: institutionId,
          country_codes: ["US"],
        });
        institution = inst.institution?.name ?? null;
      }
    } catch (_) {
      // ignore
    }

    const db = serviceClient();
    const { error } = await db.from("plaid_items").upsert(
      {
        user_id: user.id,
        item_id: itemId,
        access_token: accessToken,
        institution_name: institution,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "item_id" },
    );
    if (error) throw error;

    return json({ ok: true, item_id: itemId, institution });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 400);
  }
});
