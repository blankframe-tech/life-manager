-- Life Manager — let an owner delete their own activity log
-- Run this ONCE in the Supabase dashboard (SQL Editor → New query → paste →
-- Run). Idempotent: safe to re-run.
--
-- WHY THIS EXISTS, AND WHAT IT GIVES UP
--
-- `history_events` was created with insert + select policies and deliberately
-- no delete policy, which made the log append-only at the database layer
-- "regardless of what the client sends". That was a real hardening property:
-- a compromised client could delete your items but not erase the record of
-- having done so.
--
-- Settings → Data → "Delete all data" needs to actually delete all data. A
-- reset that leaves the cloud log intact isn't just incomplete — the app
-- re-downloads every history row on the next realtime subscribe, so the wipe
-- visibly undoes itself.
--
-- The trade-off was made knowingly: this is a single-user personal app, the
-- client can already delete every item, and being able to purge your own
-- records matters more here than tamper-evidence against yourself. The policy
-- below is still owner-scoped — it permits deleting *your* rows, never anyone
-- else's.
--
-- If you'd rather have the audit trail back, drop this policy and the reset
-- will refuse to run with a message telling you why:
--   drop policy "owner delete" on public.history_events;

drop policy if exists "owner delete" on public.history_events;
create policy "owner delete" on public.history_events
  for delete to authenticated using (user_id = auth.uid());

-- ── Verify ──────────────────────────────────────────────────────────────────
-- Expect four policies on history_events: owner insert / owner select /
-- owner delete, all scoped by `user_id = auth.uid()`. No update policy — rows
-- still can't be rewritten in place, only added or removed.
select policyname, cmd, qual, with_check
  from pg_policies
 where schemaname = 'public' and tablename = 'history_events'
 order by cmd;
