-- Reminders join the synced entities.
--
-- Reminders were frontend-only until the tasks screen gave their rows a
-- checkbox: a tick that does not survive a relaunch, let alone reach the other
-- device, is worse than no tick. The table mirrors `public.tasks` from
-- 0001_sync_tables.sql — same sync trio, same conflict rules, same policies —
-- and differs only where the model does.
--
-- `due_at` is NOT NULL where a task's `due_date` is nullable, and there is no
-- description, category or has_reminder column: a reminder is a moment, not a
-- piece of work.

-- ---------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------

create table if not exists public.reminders (
  id                text        not null,
  user_id           uuid        not null references auth.users(id) on delete cascade,
  title             text        not null,
  due_at            timestamptz not null,
  is_completed      boolean     not null default false,
  -- The enum *name*, not its index — see the same column on public.tasks.
  -- Reminders reuse TaskPriority, so the two columns hold the same three
  -- values and `_priority` in milo_sync_service.dart reads both.
  priority          text        not null default 'medium',
  client_updated_at bigint      not null,
  updated_at        timestamptz not null default now(),
  deleted           boolean     not null default false,
  primary key (user_id, id)
);

-- ---------------------------------------------------------------------
-- Trigger and index
-- ---------------------------------------------------------------------

-- `public.touch_updated_at()` is created by 0001 and reused as-is: clients may
-- send updated_at, and it is overwritten regardless, so no client can hide its
-- own rows from the other device by back-dating them.
drop trigger if exists reminders_touch_updated_at on public.reminders;

create trigger reminders_touch_updated_at
  before insert or update on public.reminders
  for each row execute function public.touch_updated_at();

-- Every pull is exactly "this user, changed since this cursor".
create index if not exists idx_reminders_user_updated
  on public.reminders (user_id, updated_at);

-- ---------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------

alter table public.reminders enable row level security;

-- RLS alone is not enough. PostgREST reaches this as the `authenticated`
-- role, and without the grant every request is a permission error rather than
-- an empty result. Supabase's default privileges cover tables created through
-- the dashboard; a table created by a migration does not get them for free.
grant select, insert, update, delete on public.reminders to authenticated;

drop policy if exists reminders_select on public.reminders;
drop policy if exists reminders_insert on public.reminders;
drop policy if exists reminders_update on public.reminders;
drop policy if exists reminders_delete on public.reminders;

create policy reminders_select on public.reminders
  for select using ((select auth.uid()) = user_id);

create policy reminders_insert on public.reminders
  for insert with check ((select auth.uid()) = user_id);

create policy reminders_update on public.reminders
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Sync itself never issues a hard delete; this exists so a user can purge
-- their own rows, and so `on delete cascade` from auth.users has somewhere to
-- land.
create policy reminders_delete on public.reminders
  for delete using ((select auth.uid()) = user_id);

-- PostgREST serves from a cached copy of the schema. Without this the table
-- exists and every request still answers "Could not find the table
-- 'public.reminders' in the schema cache".
notify pgrst, 'reload schema';
