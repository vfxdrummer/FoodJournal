-- Restaurant Journal — anonymous product analytics
-- Run in Supabase → SQL Editor.
--
-- Privacy model: events are keyed by a random per-install id (NOT the user account), carry no
-- photos/financial data, and the app can only INSERT — never read them back. Reads happen only in
-- the SQL Editor (which runs as the postgres role and bypasses RLS).

create table if not exists public.events (
    id          uuid primary key default gen_random_uuid(),
    install_id  text not null,               -- anonymous, per-install (resets on app delete)
    name        text not null,               -- e.g. "scan_completed", "visit_viewed"
    props       jsonb not null default '{}',
    app_version text,
    created_at  timestamptz not null default now()
);

alter table public.events enable row level security;

-- The app (anon / signed-in) may insert events, and nothing more.
grant insert on public.events to anon, authenticated;

create policy "insert events" on public.events
    for insert to anon, authenticated
    with check (true);

create index if not exists events_name_created_idx on public.events (name, created_at desc);
create index if not exists events_install_created_idx on public.events (install_id, created_at desc);
