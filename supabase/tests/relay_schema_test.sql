begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

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

select * from finish();
rollback;
