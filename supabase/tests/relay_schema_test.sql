begin;
create extension if not exists pgtap with schema extensions;
select plan(45);

select has_table('public', 'relay_owners', 'relay owners table exists');
select has_table('public', 'task_mirrors', 'task mirrors table exists');
select has_table('public', 'capture_queue', 'capture queue table exists');
select has_table('public', 'devices', 'devices table exists');
select has_table('public', 'execution_queue', 'execution queue table exists');

select has_column('public', 'relay_owners', 'api_key_hash', 'owner stores only a key hash');
select has_column('public', 'capture_queue', 'idempotency_key', 'captures have idempotency keys');
select has_column('public', 'capture_queue', 'lease_expires_at', 'captures have lease expiry');
select has_column('public', 'devices', 'last_seen_at', 'devices have heartbeats');
select has_column('public', 'execution_queue', 'device_id', 'executions target a device');

select ok((select relrowsecurity from pg_class where oid = 'public.relay_owners'::regclass), 'relay owners has RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.task_mirrors'::regclass), 'task mirrors has RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.capture_queue'::regclass), 'capture queue has RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.devices'::regclass), 'devices has RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.execution_queue'::regclass), 'execution queue has RLS');

select ok(not has_table_privilege('anon', 'public.relay_owners', 'select'), 'anon cannot read owners');
select ok(not has_table_privilege('anon', 'public.task_mirrors', 'select'), 'anon cannot read task mirrors');
select ok(not has_table_privilege('anon', 'public.capture_queue', 'select'), 'anon cannot read capture queue');
select ok(not has_table_privilege('anon', 'public.devices', 'select'), 'anon cannot read devices');
select ok(not has_table_privilege('anon', 'public.execution_queue', 'select'), 'anon cannot read executions');
select ok(not has_table_privilege('authenticated', 'public.task_mirrors', 'select'), 'authenticated clients cannot read mirrors directly');
select ok(not has_table_privilege('authenticated', 'public.capture_queue', 'insert'), 'authenticated clients cannot enqueue directly');
select ok(has_table_privilege('service_role', 'public.capture_queue', 'select'), 'service role can read relay queues');
select ok(has_table_privilege('service_role', 'public.capture_queue', 'insert'), 'service role can enqueue relay work');

select col_is_unique('public', 'relay_owners', 'api_key_hash', 'key hashes are unique');
select col_is_unique('public', 'capture_queue', array['owner_id', 'idempotency_key'], 'capture idempotency is owner scoped');
select col_is_unique('public', 'execution_queue', array['owner_id', 'idempotency_key'], 'execution idempotency is owner scoped');
select col_is_unique('public', 'devices', array['owner_id', 'device_id'], 'device identity is owner scoped');
select col_is_unique('public', 'task_mirrors', array['owner_id', 'task_id'], 'task mirror identity is owner scoped');

select has_index('public', 'capture_queue', 'capture_queue_pending_idx', 'captures have a pending claim index');
select has_index('public', 'execution_queue', 'execution_queue_pending_idx', 'executions have a pending claim index');
select has_index('public', 'task_mirrors', 'task_mirrors_search_idx', 'task mirrors have a search index');
select has_index('public', 'devices', 'devices_last_seen_idx', 'devices have a heartbeat index');

select has_function('public', 'relay_enqueue_capture', array['uuid','text','text','text','text','text','timestamp with time zone'], 'capture enqueue is atomic');
select has_function('public', 'relay_enqueue_execution', array['uuid','text','text','text','text','text'], 'execution enqueue is atomic');
select has_function('public', 'relay_claim_work', array['uuid','text','timestamp with time zone','timestamp with time zone'], 'claims are atomic');
select has_function('public', 'relay_transition_execution', array['uuid','text','uuid','text','text','text','text','timestamp with time zone'], 'execution transition is compare-and-swap');
select has_function('public', 'relay_ack_capture', array['uuid','text','uuid','text','timestamp with time zone'], 'capture acknowledgement is compare-and-swap');

insert into public.relay_owners (id, api_key_hash) values
  ('00000000-0000-0000-0000-000000000001', 'test-hash');
select lives_ok($$select public.relay_enqueue_capture(
  '00000000-0000-0000-0000-000000000001', 'capture-key', 'Original', '', null, 'normal', null)$$,
  'first capture idempotency key inserts');
select throws_ok($$select public.relay_enqueue_capture(
  '00000000-0000-0000-0000-000000000001', 'capture-key', 'Changed', '', null, 'normal', null)$$,
  '22000', 'Idempotency key was already used with a different capture payload.',
  'capture key cannot rewrite payload');
select lives_ok($$select public.relay_enqueue_execution(
  '00000000-0000-0000-0000-000000000001', 'execution-key', 'task-1', 'mac-a', '/repo', '')$$,
  'first execution idempotency key inserts');
select throws_ok($$select public.relay_enqueue_execution(
  '00000000-0000-0000-0000-000000000001', 'execution-key', 'task-2', 'mac-a', '/repo', '')$$,
  '22000', 'Idempotency key was already used with a different execution payload.',
  'execution key cannot rewrite payload');

update public.capture_queue set status = 'claimed', claimed_by = 'mac-a', lease_expires_at = now() + interval '5 minutes';
select is(
  jsonb_array_length((public.relay_claim_work(
    '00000000-0000-0000-0000-000000000001', 'mac-b', now(), now() + interval '1 minute'))->'captures'),
  0, 'a live capture lease cannot be stolen');
select is((select claimed_by from public.capture_queue where idempotency_key = 'capture-key'),
  'mac-a', 'live lease owner is preserved');

select throws_ok($$select public.relay_transition_execution(
  '00000000-0000-0000-0000-000000000001', 'mac-b',
  (select id from public.execution_queue where idempotency_key = 'execution-key'),
  'queued', 'claimed', null, null, now())$$,
  'P0001', 'Execution transition lost a status or device compare-and-swap.',
  'wrong device transition fails');
select lives_ok($$select public.relay_transition_execution(
  '00000000-0000-0000-0000-000000000001', 'mac-a',
  (select id from public.execution_queue where idempotency_key = 'execution-key'),
  'queued', 'claimed', 'run-1', null, now())$$,
  'matching device and previous status transition succeeds');
select throws_ok($$select public.relay_transition_execution(
  '00000000-0000-0000-0000-000000000001', 'mac-a',
  (select id from public.execution_queue where idempotency_key = 'execution-key'),
  'queued', 'canceled', null, null, now())$$,
  'P0001', 'Execution transition lost a status or device compare-and-swap.',
  'stale previous status cannot regress execution');

select * from finish();
rollback;
