import { corsHeaders, getUser, json, plaid, serviceClient } from "../_shared/plaid.ts";

// Full account deletion (App Store requirement): revoke Plaid items, delete the user's server-side
// financial data, then delete the auth user itself. Irreversible.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const user = await getUser(req);
    const db = serviceClient();

    // Revoke Plaid items first so we stop access + billing.
    const { data: items } = await db
      .from("plaid_items")
      .select("access_token")
      .eq("user_id", user.id);
    for (const item of items ?? []) {
      try {
        await plaid("/item/remove", { access_token: item.access_token });
      } catch (_) {
        // best-effort
      }
    }

    await db.from("card_transactions").delete().eq("user_id", user.id);
    await db.from("plaid_items").delete().eq("user_id", user.id);

    // Delete the auth user (admin action via the service role).
    const { error } = await db.auth.admin.deleteUser(user.id);
    if (error) throw error;

    return json({ ok: true });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 400);
  }
});
