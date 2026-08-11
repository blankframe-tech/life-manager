-- Life Manager — restrict who can create an account
-- Run this ONCE in the Supabase dashboard (SQL Editor → New query → paste →
-- Run), after replacing the email below with your own.
--
-- Why: Google Sign-In on a project with signups enabled will happily mint an
-- account for *anyone* with a Google account. Owner-scoped RLS means a stranger
-- who signs in sees only their own empty dataset — no data of yours leaks — but
-- there's no reason to let unknown users accumulate in your project at all.
--
-- Belt and braces:
--   1. Dashboard → Authentication → Sign In / Providers → disable new signups
--      ("Allow new users to sign up" off). That's the primary control and it
--      cannot be expressed in SQL.
--   2. This script, which enforces the same rule at the database layer so it
--      survives someone flipping that switch back on.

-- ── 1. The allowlist ───────────────────────────────────────────────────────
create table if not exists public.allowed_emails (
  email      text primary key,
  created_at timestamptz not null default now()
);

-- Nobody reaches this table from the client: no policies are created, and RLS
-- is on, so it's readable only by the trigger below (which runs as its owner)
-- and by you in the dashboard.
alter table public.allowed_emails enable row level security;

-- ⚠️  REPLACE with your own address(es) before running.
--
-- Ran against the live project on 2026-08-11. Both addresses below already
-- had accounts at that point; the second was added after the verification
-- query at the bottom flagged it as an existing account missing from the
-- list. It owns no rows — it was a one-off test sign-in — but it's kept so
-- the account remains recreatable.
insert into public.allowed_emails (email) values
  ('the.abraar.rar@gmail.com'),
  ('abraar.ai.dev@gmail.com')
  on conflict (email) do nothing;

-- ── 2. Reject signups outside the allowlist ────────────────────────────────
-- `security definer` so the function can read `allowed_emails` regardless of
-- the caller; `search_path` is pinned because a definer function that resolves
-- names through a caller-controlled path is a privilege-escalation vector.
create or replace function public.enforce_email_allowlist()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.allowed_emails
    where lower(email) = lower(new.email)
  ) then
    raise exception 'Sign-ups are restricted for this project.'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

-- Fires only on INSERT (account creation). Existing users keep working even if
-- they're later removed from the allowlist — drop them from auth.users for
-- that, deliberately, rather than having logins fail mysteriously.
drop trigger if exists enforce_email_allowlist on auth.users;
create trigger enforce_email_allowlist
  before insert on auth.users
  for each row execute function public.enforce_email_allowlist();

-- ── 3. Verify ───────────────────────────────────────────────────────────────
-- Existing accounts should all be on the list. Any row returned here is an
-- account that could not be recreated today — review before you rely on this.
select u.email
  from auth.users u
  left join public.allowed_emails a on lower(a.email) = lower(u.email)
 where a.email is null;
