-- Restaurant Journal — Plaid data foundation
-- Run this in the Supabase dashboard → SQL Editor (New query → paste → Run).
--
-- Security model:
--   * plaid_items holds the long-lived Plaid access_token. It is LOCKED DOWN: RLS is on and there
--     are NO policies, so neither the app (anon/authenticated) nor PostgREST can read or write it.
--     Only Edge Functions using the service_role key (which bypasses RLS) ever touch it. Access
--     tokens must never reach the client.
--   * card_transactions is the user's own dining data — readable by that user via RLS, but only
--     writable by the backend (service role). The app reads it and creates local visits.

create extension if not exists "pgcrypto";

-- One row per linked institution ("item"), per user.
create table if not exists public.plaid_items (
    id                  uuid primary key default gen_random_uuid(),
    user_id             uuid not null references auth.users(id) on delete cascade,
    item_id             text not null unique,
    access_token        text not null,
    institution_name    text,
    transactions_cursor text,               -- Plaid /transactions/sync cursor for incremental pulls
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now()
);

alter table public.plaid_items enable row level security;
-- Intentionally NO policies: service-role (Edge Functions) only. The client can never see tokens.

-- Cached dining transactions surfaced to the app to become visits.
create table if not exists public.card_transactions (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid not null references auth.users(id) on delete cascade,
    item_id           text not null,
    transaction_id    text not null unique, -- Plaid's stable id; dedupes across syncs
    name              text,
    merchant_name     text,
    amount            numeric(12,2),
    iso_currency_code text,
    date              date not null,
    category          text,
    latitude          double precision,
    longitude         double precision,
    pending           boolean not null default false,
    created_at        timestamptz not null default now()
);

alter table public.card_transactions enable row level security;

-- Owners may read their own transactions; writes happen only via the backend (service role).
create policy "read own transactions"
    on public.card_transactions
    for select
    to authenticated
    using (user_id = auth.uid());

create index if not exists card_transactions_user_date_idx
    on public.card_transactions (user_id, date desc);
