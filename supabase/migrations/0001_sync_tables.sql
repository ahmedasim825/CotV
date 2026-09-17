-- Cross-device sync: tasks, habits, study, chat and settings.
--
-- Conventions follow the logged_foods tables already in this project: one
-- row per record scoped by user_id, row-level security on every table, and
-- the client passing user_id explicitly as well as relying on RLS.
--
-- Two departures worth knowing about.
--
-- `id` is text, not uuid. Milo's identifiers are not all uuids — a study
-- log is `study-<subjectId>-<micros>` and a chat session is
-- `chat-<micros>-<uuid8>` — and a uuid column would reject both.
--
-- Every table carries two timestamps, because they answer different
-- questions. `updated_at` is the server's own clock, set by a trigger, and
-- decides *what to fetch*: it is the only ordering the two devices both
-- agree on, and it is never compared against a device clock.
-- `client_updated_at` is the device's clock at the moment of the write, and
-- decides *who wins a conflict*. Clock skew between the two devices is
-- therefore confined to the rare genuine conflict, rather than corrupting
-- the fetch cursor.

-- ---------------------------------------------------------------------
-- Server-side stamping
-- ---------------------------------------------------------------------

-- Clients may send updated_at; it is overwritten regardless. A client that
-- could set the fetch cursor could hide its own rows from the other device
-- by back-dating them.
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table if not exists public.tasks (
  id                text        not null,
  user_id           uuid        not null references auth.users(id) on delete cascade,
  title             text        not null,
  description       text        not null default '',
  due_date          timestamptz,
  is_completed      boolean     not null default false,
  category          text        not null default 'General',
  -- The enum *name*, not its index. TaskPriorityAdapter stores an index
  -- locally, and reordering the enum must not silently repoint every
  -- remote row at a different priority.
  priority          text        not null default 'medium',
  created_at        timestamptz not null,
  has_reminder      boolean     not null default false,
  client_updated_at bigint      not null,
  updated_at        timestamptz not null default now(),
  deleted           boolean     not null default false,
  primary key (user_id, id)
);

create table if not exists public.habits (
  id                text        not null,
  user_id           uuid        not null references auth.users(id) on delete cascade,
  title             text        not null,
  frequency         text        not null default 'daily',
  completed_dates   date[]      not null default '{}',
  color_hex         text        not null default '#D8A657',
  client_updated_at bigint      not null,
  updated_at        timestamptz not null default now(),
  deleted           boolean     not null default false,
  primary key (user_id, id)
);

-- streak_count is deliberately absent. It is derived from completed_dates,
-- and the merge recomputes it from the union of both devices' dates — a
-- stored count would arrive disagreeing with the dates beneath it.

create table if not exists public.subjects (
  id                text        not null,
  user_id           uuid        not null references auth.users(id) on delete cascade,
  name              text        not null,
  color_value       bigint      not null,
  created_at        timestamptz not null,
  client_updated_at bigint      not null,
  updated_at        timestamptz not null default now(),
  deleted           boolean     not null default false,
  primary key (user_id, id)
);

create table if not exists public.study_logs (
  id                text        not null,
  user_id           uuid        not null references auth.users(id) on delete cascade,
  -- No foreign key to subjects. subject_name is denormalised locally on
  -- purpose so history survives the subject being renamed or deleted, and
  -- a constraint here would undo that.
  subject_id        text        not null,
  subject_name      text        not null,
  duration_minutes  integer     not null,
  "timestamp"       timestamptz not null,
  client_updated_at bigint      not null,
  updated_at        timestamptz not null default now(),
  deleted           boolean     not null default false,
  primary key (user_id, id)
);

create table if not exists public.chat_sessions (
  id                text        not null,
  user_id           uuid        not null references auth.users(id) on delete cascade,
  title             text        not null,
  created_at        timestamptz not null,
  client_updated_at bigint      not null,
  updated_at        timestamptz not null default now(),
  deleted           boolean     not null default false,
  primary key (user_id, id)
);

create table if not exists public.chat_messages (
  id                text        not null,
  user_id           uuid        not null references auth.users(id) on delete cascade,
  session_id        text        not null,
  role              text        not null,
  content           text        not null,
  "timestamp"       timestamptz not null,
  tokens_used       integer,
  client_updated_at bigint      not null,
  updated_at        timestamptz not null default now(),
  deleted           boolean     not null default false,
  primary key (user_id, id),
  -- Deliberately without `on delete cascade`. Deletes are soft on both
  -- sides now, so a cascade would never fire; and a hard delete that
  -- reached this table would take messages with it without leaving the
  -- tombstones the other device needs to learn about them.
  foreign key (user_id, session_id)
    references public.chat_sessions(user_id, id)
);

-- Settings sync per key rather than as one wide row. A single record
-- holding a dozen unrelated preferences is the worst case for record-level
-- last-write-wins: two devices each changing a different preference offline
-- and one of them loses. Per-key is cheap here because the model is already
-- a bag of independent scalars.
--
-- The client only ever writes the keys on its allowlist — see
-- syncedSettingKeys in lib/src/services/sync_merge.dart. Notably absent:
-- the biometric flag, whose authoritative copy is in the device Keychain.
create table if not exists public.user_settings (
  user_id           uuid        not null references auth.users(id) on delete cascade,
  key               text        not null,
  value             jsonb,
  client_updated_at bigint      not null,
  updated_at        timestamptz not null default now(),
  primary key (user_id, key)
);

-- ---------------------------------------------------------------------
-- Triggers and indexes
-- ---------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'tasks', 'habits', 'subjects', 'study_logs',
    'chat_sessions', 'chat_messages', 'user_settings'
  ] loop
    execute format(
      'drop trigger if exists %I on public.%I', t || '_touch_updated_at', t
    );
    execute format(
      'create trigger %I before insert or update on public.%I
         for each row execute function public.touch_updated_at()',
      t || '_touch_updated_at', t
    );

    -- Every pull is exactly "this user, changed since this cursor".
    execute format(
      'create index if not exists %I on public.%I (user_id, updated_at)',
      'idx_' || t || '_user_updated', t
    );
  end loop;
end $$;

-- Messages are also read per session when a thread is reconciled.
create index if not exists idx_chat_messages_session
  on public.chat_messages (user_id, session_id, "timestamp");

-- ---------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'tasks', 'habits', 'subjects', 'study_logs',
    'chat_sessions', 'chat_messages', 'user_settings'
  ] loop
    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);

    execute format(
      'create policy %I on public.%I for select using (auth.uid() = user_id)',
      t || '_select', t
    );
    execute format(
      'create policy %I on public.%I for insert with check (auth.uid() = user_id)',
      t || '_insert', t
    );
    execute format(
      'create policy %I on public.%I for update
         using (auth.uid() = user_id) with check (auth.uid() = user_id)',
      t || '_update', t
    );
    -- Sync itself never issues a hard delete; this exists so a user can
    -- purge their own rows, and so `on delete cascade` from auth.users
    -- has somewhere to land.
    execute format(
      'create policy %I on public.%I for delete using (auth.uid() = user_id)',
      t || '_delete', t
    );
  end loop;
end $$;
