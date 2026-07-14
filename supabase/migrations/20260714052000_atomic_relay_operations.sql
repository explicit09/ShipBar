create or replace function public.relay_enqueue_capture(
  p_owner_id uuid, p_idempotency_key text, p_title text, p_description text,
  p_project_name text, p_priority text, p_due_at timestamptz)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare item public.capture_queue%rowtype;
begin
  insert into public.capture_queue (
    owner_id, idempotency_key, title, description, project_name, priority, due_at)
  values (p_owner_id, p_idempotency_key, p_title, p_description, p_project_name, p_priority, p_due_at)
  on conflict (owner_id, idempotency_key) do nothing
  returning * into item;
  if item.id is null then
    select * into item from public.capture_queue
      where owner_id = p_owner_id and idempotency_key = p_idempotency_key;
    if item.title is distinct from p_title
      or item.description is distinct from p_description
      or item.project_name is distinct from p_project_name
      or item.priority is distinct from p_priority
      or item.due_at is distinct from p_due_at then
      raise exception using errcode = '22000', message = 'Idempotency key was already used with a different capture payload.';
    end if;
  end if;
  return to_jsonb(item) - 'owner_id';
end;
$$;

create or replace function public.relay_enqueue_execution(
  p_owner_id uuid, p_idempotency_key text, p_task_id text, p_device_id text,
  p_repository_path text, p_instructions text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare item public.execution_queue%rowtype;
begin
  insert into public.execution_queue (
    owner_id, idempotency_key, task_id, device_id, repository_path, instructions)
  values (p_owner_id, p_idempotency_key, p_task_id, p_device_id, p_repository_path, p_instructions)
  on conflict (owner_id, idempotency_key) do nothing
  returning * into item;
  if item.id is null then
    select * into item from public.execution_queue
      where owner_id = p_owner_id and idempotency_key = p_idempotency_key;
    if item.task_id is distinct from p_task_id
      or item.device_id is distinct from p_device_id
      or item.repository_path is distinct from p_repository_path
      or item.instructions is distinct from p_instructions then
      raise exception using errcode = '22000', message = 'Idempotency key was already used with a different execution payload.';
    end if;
  end if;
  return to_jsonb(item) - 'owner_id';
end;
$$;

create or replace function public.relay_claim_work(
  p_owner_id uuid, p_device_id text, p_now timestamptz, p_lease_expires_at timestamptz)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare captures jsonb; executions jsonb;
begin
  with candidates as (
    select id from public.capture_queue
    where owner_id = p_owner_id
      and (status = 'queued' or (status = 'claimed' and lease_expires_at < p_now))
    order by created_at limit 20 for update skip locked
  ), claimed as (
    update public.capture_queue q set
      status = 'claimed', claimed_by = p_device_id,
      lease_expires_at = p_lease_expires_at, updated_at = p_now
    from candidates c where q.id = c.id
      and q.owner_id = p_owner_id
      and (q.status = 'queued' or (q.status = 'claimed' and q.lease_expires_at < p_now))
    returning q.*
  ) select coalesce(jsonb_agg(to_jsonb(claimed) - 'owner_id'), '[]'::jsonb)
    into captures from claimed;

  with candidates as (
    select id from public.execution_queue
    where owner_id = p_owner_id and device_id = p_device_id
      and (status = 'queued' or (status = 'claimed' and lease_expires_at < p_now))
    order by created_at limit 10 for update skip locked
  ), claimed as (
    update public.execution_queue q set
      status = 'claimed', claimed_by = p_device_id,
      lease_expires_at = p_lease_expires_at, updated_at = p_now
    from candidates c where q.id = c.id
      and q.owner_id = p_owner_id and q.device_id = p_device_id
      and (q.status = 'queued' or (q.status = 'claimed' and q.lease_expires_at < p_now))
    returning q.*
  ), visible as (
    select * from claimed
    union
    select * from public.execution_queue
      where owner_id = p_owner_id and device_id = p_device_id
        and status in ('claimed', 'running', 'needs_review') and local_run_id is not null
  ) select coalesce(jsonb_agg(to_jsonb(visible) - 'owner_id'), '[]'::jsonb)
    into executions from visible;
  return jsonb_build_object(
    'device_id', p_device_id, 'lease_expires_at', p_lease_expires_at,
    'captures', captures, 'executions', executions);
end;
$$;

create or replace function public.relay_transition_execution(
  p_owner_id uuid, p_device_id text, p_execution_id uuid,
  p_expected_status text, p_next_status text, p_local_run_id text,
  p_result_summary text, p_now timestamptz)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare item public.execution_queue%rowtype;
begin
  update public.execution_queue set
    status = p_next_status,
    local_run_id = coalesce(p_local_run_id, local_run_id),
    result_summary = coalesce(p_result_summary, result_summary),
    updated_at = p_now,
    lease_expires_at = case when p_next_status = 'claimed' then lease_expires_at else null end
  where owner_id = p_owner_id and id = p_execution_id and device_id = p_device_id
    and status = p_expected_status
    and (
      p_expected_status = p_next_status
      or (p_expected_status = 'queued' and p_next_status in ('claimed', 'canceled'))
      or (p_expected_status = 'claimed' and p_next_status in ('running', 'failed', 'canceled'))
      or (p_expected_status = 'running' and p_next_status in ('needs_review', 'failed', 'canceled'))
      or (p_expected_status = 'needs_review' and p_next_status in ('completed', 'running', 'failed', 'canceled'))
    )
  returning * into item;
  if item.id is null then
    raise exception using errcode = 'P0001', message = 'Execution transition lost a status or device compare-and-swap.';
  end if;
  return to_jsonb(item) - 'owner_id';
end;
$$;

create or replace function public.relay_ack_capture(
  p_owner_id uuid, p_device_id text, p_capture_id uuid, p_task_id text, p_now timestamptz)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare item public.capture_queue%rowtype;
begin
  update public.capture_queue set
    status = 'delivered', delivered_task_id = p_task_id, delivered_at = p_now,
    updated_at = p_now, lease_expires_at = null
  where owner_id = p_owner_id and id = p_capture_id
    and status = 'claimed' and claimed_by = p_device_id
  returning * into item;
  if item.id is null then
    raise exception using errcode = 'P0001', message = 'Capture acknowledgement lost its claim compare-and-swap.';
  end if;
  return to_jsonb(item) - 'owner_id';
end;
$$;

revoke all on function public.relay_enqueue_capture(uuid,text,text,text,text,text,timestamptz) from public, anon, authenticated;
revoke all on function public.relay_enqueue_execution(uuid,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.relay_claim_work(uuid,text,timestamptz,timestamptz) from public, anon, authenticated;
revoke all on function public.relay_transition_execution(uuid,text,uuid,text,text,text,text,timestamptz) from public, anon, authenticated;
revoke all on function public.relay_ack_capture(uuid,text,uuid,text,timestamptz) from public, anon, authenticated;
grant execute on function public.relay_enqueue_capture(uuid,text,text,text,text,text,timestamptz) to service_role;
grant execute on function public.relay_enqueue_execution(uuid,text,text,text,text,text) to service_role;
grant execute on function public.relay_claim_work(uuid,text,timestamptz,timestamptz) to service_role;
grant execute on function public.relay_transition_execution(uuid,text,uuid,text,text,text,text,timestamptz) to service_role;
grant execute on function public.relay_ack_capture(uuid,text,uuid,text,timestamptz) to service_role;
