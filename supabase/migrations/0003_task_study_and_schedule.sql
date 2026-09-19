-- Study, subject, repeat and early reminder join the synced task columns.
--
-- All four were sheet-local state until now: the task sheet drew the controls
-- and dropped their values on save, which is a lie the UI told on purpose for
-- one design pass. These are the columns that end it.
--
-- `public.tasks` already carries its trigger, its (user_id, updated_at) index,
-- RLS and a table-level grant from 0001_sync_tables.sql, and a grant covers
-- columns added later — so this migration is the columns and the schema
-- reload, and nothing else.

alter table public.tasks
  -- Study work, which is what puts a subject on a task.
  add column if not exists is_study       boolean not null default false,
  -- The subject's id, not a foreign key. Subjects are tombstoned rather than
  -- removed, but they can still be purged, and a task should outlive the
  -- subject it was filed under rather than block its deletion. Every read
  -- resolves this against the live list and falls back to unfiled.
  add column if not exists subject_id     text,
  -- The enum *name*, not its index — see the priority column on this table.
  -- Recorded only; nothing regenerates a task from it yet.
  add column if not exists repeat_rule    text    not null default 'never',
  add column if not exists early_reminder text    not null default 'never';

-- PostgREST serves from a cached copy of the schema. Without this the columns
-- exist and every request still answers as though they do not.
notify pgrst, 'reload schema';
