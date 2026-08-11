-- Life Manager — auth hardening + history log migration
-- Run this ONCE in the Supabase dashboard (SQL Editor → New query → paste →
-- Run) — and only after Google Sign-In is proven working end-to-end against
-- this project (see HANDOFF.md).
--
-- NOTE (2026-08-11): the original version of this script assumed
-- `public.items` held only fake seed data and truncated it before adding
-- `user_id`. By the time this actually ran, the table held real synced data
-- (72 rows), so it was rewritten to backfill `user_id` in place instead of
-- truncating — safety-checked to abort unless exactly one row exists in
-- auth.users (this app is single-user by design; see HANDOFF.md "Decisions
-- on record"). No data was lost. Keeping the backfill version here since
-- it's strictly safer than truncate and this script should never run twice
-- against the same project anyway (the `alter table ... add column` and
-- `drop policy` steps are not idempotent).

-- ── 0. Safety check — abort if this isn't a single-user project ────────────
do $$
declare
  user_count int;
begin
  select count(*) into user_count from auth.users;
  if user_count != 1 then
    raise exception 'Expected exactly 1 user in auth.users, found %. Aborting to avoid assigning items to the wrong owner.', user_count;
  end if;
end $$;

-- ── 1. Scope `items` to its owner, preserving existing rows ────────────────
alter table public.items add column user_id uuid;
update public.items set user_id = (select id from auth.users limit 1);
alter table public.items alter column user_id set not null;
alter table public.items alter column user_id set default auth.uid();

drop policy "anon full access (MVP)" on public.items;
create policy "owner only" on public.items
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ── 2. New table: append-only activity log ──────────────────────────────────
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

alter publication supabase_realtime add table public.history_events;
alter table public.history_events enable row level security;

-- Insert + select only — no update/delete policy, so the log is append-only
-- at the database layer regardless of what the client sends.
create policy "owner insert" on public.history_events
  for insert to authenticated with check (user_id = auth.uid());
create policy "owner select" on public.history_events
  for select to authenticated using (user_id = auth.uid());
