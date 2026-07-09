import { corsHeaders, getUser, json, plaid, serviceClient } from "../_shared/plaid.ts";

// Disconnect the user's linked card(s): revoke the Plaid items (stops access + billing) and delete
// their stored access tokens and cached transactions.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const user = await getUser(req);
    const db = serviceClient();

    const { data: items } = await db
      .from("plaid_items")
      .select("access_token")
      .eq("user_id", user.id);

    for (const item of items ?? []) {
      try {
        await plaid("/item/remove", { access_token: item.access_token });
      } catch (_) {
        // Best-effort — still remove our copies below.
      }
    }

    await db.from("card_transactions").delete().eq("user_id", user.id);
    await db.from("plaid_items").delete().eq("user_id", user.id);

    return json({ ok: true });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 400);
  }
});
