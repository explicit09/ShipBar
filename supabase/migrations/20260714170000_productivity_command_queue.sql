alter table public.task_mirrors
  add column if not exists prompt text not null default '',
  add column if not exists type text not null default 'idea',
  add column if not exists revision integer not null default 0,
  add column if not exists trashed_at timestamptz,
  add column if not exists source_app text not null default '',
  add column if not exists source_url text not null default '';

create table if not exists public.project_mirrors (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.relay_owners(id) on delete cascade,
  project_id text not null,
  name text not null,
  outcome text not null default '',
  base_prompt text not null default '',
  repo_path text not null default '',
  color text not null default 'blue',
  icon text not null default 'square.stack.3d.up',
  sort_order integer not null default 0,
  revision integer not null default 0,
  trashed_at timestamptz,
  source_updated_at timestamptz not null,
  synced_at timestamptz not null default now(),
  unique (owner_id, project_id)
);

create table if not exists public.command_queue (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.relay_owners(id) on delete cascade,
  idempotency_key text not null,
  device_id text not null,
  kind text not null,
  payload jsonb not null,
  status text not null default 'queued'
    check (status in ('queued','claimed','applied','failed','conflicted','canceled')),
  claimed_by text,
  lease_expires_at timestamptz,
  summary text not null default '',
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  applied_at timestamptz,
  unique (owner_id, idempotency_key)
);

create index if not exists command_queue_pending_idx
  on public.command_queue (owner_id, device_id, created_at)
  where status in ('queued','claimed');

alter table public.project_mirrors enable row level security;
alter table public.command_queue enable row level security;
revoke all on table public.project_mirrors from anon, authenticated;
revoke all on table public.command_queue from anon, authenticated;
grant select, insert, update, delete on table public.project_mirrors to service_role;
grant select, insert, update, delete on table public.command_queue to service_role;

create or replace function public.relay_enqueue_command(
  p_owner_id uuid, p_idempotency_key text, p_device_id text,
  p_kind text, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare item public.command_queue%rowtype;
begin
  insert into public.command_queue(owner_id,idempotency_key,device_id,kind,payload)
  values(p_owner_id,p_idempotency_key,p_device_id,p_kind,p_payload)
  on conflict(owner_id,idempotency_key) do nothing
  returning * into item;
  if item.id is null then
    select * into item from public.command_queue
      where owner_id=p_owner_id and idempotency_key=p_idempotency_key;
    if item.device_id is distinct from p_device_id
      or item.kind is distinct from p_kind
      or item.payload is distinct from p_payload then
      raise exception using errcode='22000', message='Idempotency key was already used with a different command payload.';
    end if;
  end if;
  return to_jsonb(item)-'owner_id'-'idempotency_key';
end;
$$;

create or replace function public.relay_claim_work(
  p_owner_id uuid, p_device_id text, p_now timestamptz, p_lease_expires_at timestamptz)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare captures jsonb; executions jsonb; commands jsonb;
begin
  with candidates as (
    select id from public.capture_queue where owner_id=p_owner_id
      and (status='queued' or (status='claimed' and lease_expires_at<p_now))
    order by created_at limit 20 for update skip locked
  ), claimed as (
    update public.capture_queue q set status='claimed',claimed_by=p_device_id,
      lease_expires_at=p_lease_expires_at,updated_at=p_now
    from candidates c where q.id=c.id returning q.*
  ) select coalesce(jsonb_agg(to_jsonb(claimed)-'owner_id'),'[]'::jsonb) into captures from claimed;

  with candidates as (
    select id from public.execution_queue where owner_id=p_owner_id and device_id=p_device_id
      and (status='queued' or (status='claimed' and lease_expires_at<p_now))
    order by created_at limit 10 for update skip locked
  ), claimed as (
    update public.execution_queue q set status='claimed',claimed_by=p_device_id,
      lease_expires_at=p_lease_expires_at,updated_at=p_now
    from candidates c where q.id=c.id returning q.*
  ), visible as (
    select * from claimed union select * from public.execution_queue
      where owner_id=p_owner_id and device_id=p_device_id
        and status in ('claimed','running','needs_review') and local_run_id is not null
  ) select coalesce(jsonb_agg(to_jsonb(visible)-'owner_id'),'[]'::jsonb) into executions from visible;

  with candidates as (
    select id from public.command_queue where owner_id=p_owner_id and device_id=p_device_id
      and (status='queued' or (status='claimed' and lease_expires_at<p_now))
    order by created_at limit 20 for update skip locked
  ), claimed as (
    update public.command_queue q set status='claimed',claimed_by=p_device_id,
      lease_expires_at=p_lease_expires_at,updated_at=p_now
    from candidates c where q.id=c.id returning q.*
  ) select coalesce(jsonb_agg(to_jsonb(claimed)-'owner_id'-'idempotency_key'),'[]'::jsonb)
    into commands from claimed;

  return jsonb_build_object('device_id',p_device_id,'lease_expires_at',p_lease_expires_at,
    'captures',captures,'executions',executions,'commands',commands);
end;
$$;

create or replace function public.relay_ack_command(
  p_owner_id uuid, p_device_id text, p_command_id uuid, p_status text,
  p_summary text, p_result jsonb, p_now timestamptz)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare item public.command_queue%rowtype;
begin
  if p_status not in ('applied','failed','conflicted') then
    raise exception using errcode='22023', message='Command acknowledgement status is invalid.';
  end if;
  update public.command_queue set status=p_status,summary=p_summary,result=p_result,
    updated_at=p_now,applied_at=case when p_status='applied' then p_now else null end,
    lease_expires_at=null
  where owner_id=p_owner_id and id=p_command_id and device_id=p_device_id
    and status='claimed' and claimed_by=p_device_id
  returning * into item;
  if item.id is null then
    raise exception using errcode='P0001', message='Command acknowledgement lost its claim or device compare-and-swap.';
  end if;
  return to_jsonb(item)-'owner_id'-'idempotency_key'-'payload';
end;
$$;

revoke all on function public.relay_enqueue_command(uuid,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.relay_ack_command(uuid,text,uuid,text,text,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function public.relay_enqueue_command(uuid,text,text,text,jsonb) to service_role;
grant execute on function public.relay_ack_command(uuid,text,uuid,text,text,jsonb,timestamptz) to service_role;
