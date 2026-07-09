# Plaid Edge Functions

Three functions power card ingestion. The Plaid `client_id`/`secret` live **only** here as function
secrets — never in the app.

- `plaid-create-link-token` — starts the Hosted Link flow, returns a `hosted_link_url`.
- `plaid-exchange-token` — after Link finishes, swaps the public token → access token, stores it.
- `plaid-sync-transactions` — pulls dining charges into `card_transactions`.

## Deploy (one time)

```bash
# 1. Install + log in
brew install supabase/tap/supabase
supabase login

# 2. Link this project
supabase link --project-ref djjrmnpqyywploerecpr

# 3. Set the Plaid secrets (enter YOUR values; do not commit them)
supabase secrets set PLAID_CLIENT_ID=6a4ed82cc644ef000d4aa5a3
supabase secrets set PLAID_SECRET=your_sandbox_secret
supabase secrets set PLAID_ENV=sandbox

# 4. Deploy all three
supabase functions deploy plaid-create-link-token
supabase functions deploy plaid-exchange-token
supabase functions deploy plaid-sync-transactions
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically —
you do **not** set those.

## Sandbox testing

In Plaid Link (sandbox), use institution "First Platypus Bank" with credentials
`user_good` / `pass_good`. Dining transactions appear in `card_transactions` after a sync.

When you go live, set `PLAID_SECRET` to your production secret and `PLAID_ENV=production`
(requires Plaid production approval), then redeploy.
