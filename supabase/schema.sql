-- Life Manager — Supabase schema
-- Run this in the Supabase dashboard: SQL Editor → New query → paste → Run.

-- One table backs every screen; the app filters by `kind`.
create table if not exists public.items (
  uuid        uuid primary key,
  kind        text not null,             -- deal | budget | task | buy | dream
  title       text not null default '',
  note        text not null default '',
  amount      numeric,                   -- nullable (tasks/dreams have none)
  direction   text,                      -- deals: i_owe | they_owe
  category    text,                      -- budget: needs | wants | savings
  section     text,                      -- task/buy sub-group
  done        boolean not null default false,
  due_date    timestamptz,
  sort_order  integer not null default 0,
  updated_at  timestamptz not null default now(),
  is_deleted  boolean not null default false
);

create index if not exists items_kind_idx on public.items (kind);
create index if not exists items_updated_idx on public.items (updated_at);

-- Realtime: broadcast row changes so a second device updates live.
alter publication supabase_realtime add table public.items;

-- ─────────────────────────────────────────────────────────────────────────
-- ACCESS CONTROL
--
-- MVP (single user, no login): the app connects with the public anon key and
-- has no auth. The simplest working setup is a permissive policy. Anyone who
-- has BOTH your project URL and anon key could read/write, so treat the anon
-- key as semi-secret and prefer the hardened path below for real privacy.
-- ─────────────────────────────────────────────────────────────────────────
alter table public.items enable row level security;

create policy "anon full access (MVP)" on public.items
  for all
  to anon, authenticated
  using (true)
  with check (true);

-- ─────────────────────────────────────────────────────────────────────────
-- HARDENING (recommended once you add Supabase Auth): add an owner column and
-- scope every row to the signed-in user. See README "Making it private".
--
--   alter table public.items add column user_id uuid default auth.uid();
--   drop policy "anon full access (MVP)" on public.items;
--   create policy "owner only" on public.items
--     for all to authenticated
--     using (user_id = auth.uid())
--     with check (user_id = auth.uid());
-- ─────────────────────────────────────────────────────────────────────────
