create extension if not exists pgcrypto with schema extensions;

create table public.relay_owners (
  id uuid primary key default gen_random_uuid(),
  label text not null default 'Personal',
  api_key_hash text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.task_mirrors (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.relay_owners(id) on delete cascade,
  task_id text not null,
  title text not null,
  description text not null default '',
  status text not null,
  priority text not null default 'normal',
  project_name text,
  due_at timestamptz,
  focus_date date,
  focus_order integer,
  is_inbox boolean not null default true,
  source_updated_at timestamptz not null,
  synced_at timestamptz not null default now(),
  unique (owner_id, task_id)
);

create table public.capture_queue (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.relay_owners(id) on delete cascade,
  idempotency_key text not null,
  title text not null,
  description text not null default '',
  project_name text,
  priority text not null default 'normal',
  due_at timestamptz,
  status text not null default 'queued'
    check (status in ('queued', 'claimed', 'delivered', 'canceled')),
  claimed_by text,
  lease_expires_at timestamptz,
  delivered_task_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  delivered_at timestamptz,
  unique (owner_id, idempotency_key)
);

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.relay_owners(id) on delete cascade,
  device_id text not null,
  name text not null,
  platform text not null check (platform in ('macos', 'ios', 'windows', 'linux')),
  capabilities text[] not null default '{}',
  last_seen_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, device_id)
);

create table public.execution_queue (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.relay_owners(id) on delete cascade,
  idempotency_key text not null,
  task_id text not null,
  device_id text not null,
  repository_path text,
  instructions text not null default '',
  status text not null default 'queued'
    check (status in ('queued', 'claimed', 'running', 'needs_review', 'completed', 'failed', 'canceled')),
  claimed_by text,
  lease_expires_at timestamptz,
  local_run_id text,
  result_summary text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, idempotency_key)
);

create index capture_queue_pending_idx
  on public.capture_queue (owner_id, created_at)
  where status in ('queued', 'claimed');
create index execution_queue_pending_idx
  on public.execution_queue (owner_id, device_id, created_at)
  where status in ('queued', 'claimed', 'running');
create index task_mirrors_search_idx
  on public.task_mirrors using gin (to_tsvector('simple', title || ' ' || description));
create index devices_last_seen_idx
  on public.devices (owner_id, last_seen_at desc);

alter table public.relay_owners enable row level security;
alter table public.task_mirrors enable row level security;
alter table public.capture_queue enable row level security;
alter table public.devices enable row level security;
alter table public.execution_queue enable row level security;

revoke all on table public.relay_owners from anon, authenticated;
revoke all on table public.task_mirrors from anon, authenticated;
revoke all on table public.capture_queue from anon, authenticated;
revoke all on table public.devices from anon, authenticated;
revoke all on table public.execution_queue from anon, authenticated;
