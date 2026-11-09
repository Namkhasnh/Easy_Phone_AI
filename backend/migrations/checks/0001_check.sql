-- Checks for 0001_init.sql (DATA_MODEL §9, D-033). Any failure raises and stops psql (ON_ERROR_STOP).
\set a '11111111-1111-1111-1111-111111111111'
\set b '22222222-2222-2222-2222-222222222222'
insert into auth.users values (:'a'), (:'b');
insert into profiles (id) values (:'a'), (:'b');
insert into subscriptions (user_id, product_id, original_transaction_id, status, environment)
  values (:'a', 'easyphone.premium.monthly', 'tx-a', 'active', 'Xcode'),
         (:'b', 'easyphone.premium.yearly', 'tx-b', 'expired', 'Sandbox');
insert into usage_events (user_id, endpoint, idempotency_key) values (:'a', '/v1/parse', 'k1'), (:'b', '/v1/parse', 'k1');
insert into usage_events (user_id, endpoint) values (:'a', '/v1/me'), (:'a', '/v1/me');  -- many null keys ok

do $$
declare n int;
begin
  -- gmail_accounts must not exist (D-150)
  if to_regclass('public.gmail_accounts') is not null then raise exception 'gmail_accounts exists'; end if;
  if (select count(*) from pg_class where relname in ('profiles','subscriptions','usage_events') and relrowsecurity) <> 3
    then raise exception 'RLS not enabled on all tables'; end if;

  -- user A sees only own rows
  execute 'set role authenticated';
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
  select count(*) into n from profiles;      if n <> 1 then raise exception 'A sees % profiles', n; end if;
  select count(*) into n from subscriptions; if n <> 1 then raise exception 'A sees % subscriptions', n; end if;
  select count(*) into n from usage_events;  if n <> 3 then raise exception 'A sees % usage rows', n; end if;
  select count(*) into n from usage_events where user_id <> auth.uid();
  if n <> 0 then raise exception 'A sees other users usage'; end if;

  -- client writes are refused
  begin insert into profiles (id) values ('11111111-1111-1111-1111-111111111111');
        raise exception 'authenticated insert allowed';
  exception when insufficient_privilege then null; end;
  begin update profiles set locale = 'en'; raise exception 'authenticated update allowed';
  exception when insufficient_privilege then null; end;
  begin delete from usage_events; raise exception 'authenticated delete allowed';
  exception when insufficient_privilege then null; end;
  execute 'reset role';

  -- anon sees nothing
  execute 'set role anon';
  select count(*) into n from profiles; if n <> 0 then raise exception 'anon sees % profiles', n; end if;
  select count(*) into n from usage_events; if n <> 0 then raise exception 'anon sees % usage rows', n; end if;
  execute 'reset role';

  -- service role (backend) writes
  execute 'set role service_role';
  insert into usage_events (user_id, endpoint, idempotency_key, attempt)
    values ('22222222-2222-2222-2222-222222222222', '/v1/extract', 'k2', 1);
  update profiles set locale = 'en' where id = '22222222-2222-2222-2222-222222222222';
  execute 'reset role';

  -- same (user, key) twice is refused
  begin insert into usage_events (user_id, endpoint, idempotency_key)
          values ('11111111-1111-1111-1111-111111111111', '/v1/parse', 'k1');
        raise exception 'duplicate idempotency key allowed';
  exception when unique_violation then null; end;

  -- check constraints
  begin insert into subscriptions (user_id, product_id, original_transaction_id, status, environment)
          values ('11111111-1111-1111-1111-111111111111', 'p', 'tx-x', 'bogus', 'Xcode');
        raise exception 'bad status allowed';
  exception when check_violation then null; end;
  begin insert into subscriptions (user_id, product_id, original_transaction_id, status, environment)
          values ('11111111-1111-1111-1111-111111111111', 'p', 'tx-y', 'active', 'Test');
        raise exception 'bad environment allowed';
  exception when check_violation then null; end;

  -- deleting the auth user cascades (D-033)
  delete from auth.users where id = '11111111-1111-1111-1111-111111111111';
  select count(*) into n from profiles where id = '11111111-1111-1111-1111-111111111111';
  if n <> 0 then raise exception 'profile not cascaded'; end if;
  select count(*) into n from subscriptions where user_id = '11111111-1111-1111-1111-111111111111';
  if n <> 0 then raise exception 'subscriptions not cascaded'; end if;
  select count(*) into n from usage_events where user_id = '11111111-1111-1111-1111-111111111111';
  if n <> 0 then raise exception 'usage_events not cascaded'; end if;
  select count(*) into n from usage_events; if n <> 2 then raise exception 'B rows lost (%)', n; end if;

  raise notice '0001_check: ALL CHECKS PASSED';
end $$;
