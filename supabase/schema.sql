-- Life Manager — Supabase schema
-- For a BRAND NEW project: run this in the Supabase dashboard (SQL Editor →
-- New query → paste → Run) to get straight to the hardened, owner-scoped
-- state described below. If you already ran an older version of this file
-- (permissive anon policy, no `history_events` table), use
-- `migrate_auth_and_history.sql` instead — it's the one-time upgrade path for
-- an existing project, and this file will no longer match what's live there.

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
  is_deleted  boolean not null default false,
  user_id     uuid not null default auth.uid()
);

create index if not exists items_kind_idx on public.items (kind);
create index if not exists items_updated_idx on public.items (updated_at);

-- Append-only activity log — one row per add/edit/complete/delete.
create table if not exists public.history_events (
  uuid       uuid primary key,
  item_uuid  uuid not null,
  item_kind  text not null,
  title      text not null default '',
  action     text not null,            -- created | edited | completed | uncompleted | deleted
  timestamp  timestamptz not null,
  user_id    uuid not null default auth.uid()
);

create index if not exists history_events_timestamp_idx on public.history_events (timestamp);
create index if not exists history_events_item_uuid_idx on public.history_events (item_uuid);

-- Realtime: broadcast row changes so a second device updates live.
alter publication supabase_realtime add table public.items;
alter publication supabase_realtime add table public.history_events;

-- ─────────────────────────────────────────────────────────────────────────
-- ACCESS CONTROL
--
-- Requires Supabase Auth (Google Sign-In — see HANDOFF.md for setup). Every
-- row is scoped to its owner via `user_id = auth.uid()`; the anon key alone
-- grants no access at all. `history_events` has no *update* policy, so events
-- can be added and removed but never rewritten in place. It does allow the
-- owner to delete their own rows, so that Settings → Data → "Delete all data"
-- can actually clear everything — see `allow_history_delete.sql` for the full
-- reasoning and how to revert to a strictly append-only log.
-- ─────────────────────────────────────────────────────────────────────────
alter table public.items enable row level security;

create policy "owner only" on public.items
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table public.history_events enable row level security;

create policy "owner insert" on public.history_events
  for insert to authenticated with check (user_id = auth.uid());
create policy "owner select" on public.history_events
  for select to authenticated using (user_id = auth.uid());
create policy "owner delete" on public.history_events
  for delete to authenticated using (user_id = auth.uid());
