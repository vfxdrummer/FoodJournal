import { corsHeaders, getUser, json, plaid, serviceClient } from "../_shared/plaid.ts";

// Pull new/changed transactions for all of the user's linked items, keep only dining
// (FOOD_AND_DRINK), and cache them in card_transactions. Incremental via the stored sync cursor.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const user = await getUser(req);
    const db = serviceClient();

    const { data: items, error } = await db
      .from("plaid_items")
      .select("item_id, access_token, transactions_cursor")
      .eq("user_id", user.id);
    if (error) throw error;
    if (!items || items.length === 0) return json({ added: 0 });

    let totalDining = 0;

    for (const item of items) {
      let cursor: string | undefined = item.transactions_cursor ?? undefined;
      let hasMore = true;

      while (hasMore) {
        const sync = await plaid("/transactions/sync", {
          access_token: item.access_token,
          cursor,
          count: 500,
        });

        // Added + modified both need upserting; keep only dining.
        const changed = [...(sync.added ?? []), ...(sync.modified ?? [])];
        const dining = changed.filter(
          (t: any) => t.personal_finance_category?.primary === "FOOD_AND_DRINK",
        );

        if (dining.length > 0) {
          const rows = dining.map((t: any) => ({
            user_id: user.id,
            item_id: item.item_id,
            transaction_id: t.transaction_id,
            name: t.name ?? null,
            merchant_name: t.merchant_name ?? null,
            amount: t.amount ?? null,
            iso_currency_code: t.iso_currency_code ?? null,
            date: t.authorized_date ?? t.date,
            category: t.personal_finance_category?.detailed ?? null,
            latitude: t.location?.lat ?? null,
            longitude: t.location?.lon ?? null,
            pending: t.pending ?? false,
          }));
          const { error: upErr } = await db
            .from("card_transactions")
            .upsert(rows, { onConflict: "transaction_id" });
          if (upErr) throw upErr;
          totalDining += rows.length;
        }

        const removedIds = (sync.removed ?? []).map((r: any) => r.transaction_id);
        if (removedIds.length > 0) {
          await db.from("card_transactions").delete().in("transaction_id", removedIds);
        }

        cursor = sync.next_cursor;
        hasMore = sync.has_more;
      }

      await db
        .from("plaid_items")
        .update({ transactions_cursor: cursor, updated_at: new Date().toISOString() })
        .eq("item_id", item.item_id);
    }

    return json({ added: totalDining });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 400);
  }
});
