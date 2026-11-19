-- Checks for 0002_gmail.sql (own user c; 0001_check.sql deletes its users).
\set a '33333333-3333-3333-3333-333333333333'
insert into auth.users values (:'a');
insert into profiles (id) values (:'a');
insert into gmail_accounts (id, user_id, email, refresh_token_enc, scopes)
  values ('gma_01JD0000000000000000000000', :'a', 'a@gmail.com', '\x00', '{gmail.readonly}');
insert into gmail_draft_keys (user_id, idempotency_key, account_id, draft_id)
  values (:'a', 'k1', 'gma_01JD0000000000000000000000', 'r-1');

do $$
declare n int;
begin
  if (select count(*) from pg_class where relname in ('gmail_accounts','gmail_draft_keys') and relrowsecurity) <> 2
    then raise exception 'RLS not enabled on gmail tables'; end if;
  begin
    insert into gmail_accounts (id, user_id, email, refresh_token_enc, scopes)
      values ('bad', '33333333-3333-3333-3333-333333333333', 'x@gmail.com', '\x00', '{}');
    raise exception 'bad id accepted';
  exception when check_violation then null; end;
  begin
    insert into gmail_accounts (id, user_id, email, refresh_token_enc, scopes)
      values ('gma_01JD0000000000000000000001', '33333333-3333-3333-3333-333333333333', 'a@gmail.com', '\x00', '{}');
    raise exception 'duplicate email accepted';
  exception when unique_violation then null; end;

  -- the app (authenticated) cannot read or write either table
  execute 'set role authenticated';
  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
  begin select count(*) into n from gmail_accounts; raise exception 'client can read gmail_accounts';
  exception when insufficient_privilege then null; end;
  begin select count(*) into n from gmail_draft_keys; raise exception 'client can read gmail_draft_keys';
  exception when insufficient_privilege then null; end;
  execute 'reset role';

  -- deleting the profile removes the account and its draft keys (DELETE /v1/me cascade)
  delete from profiles where id = '33333333-3333-3333-3333-333333333333';
  if (select count(*) from gmail_accounts) <> 0 or (select count(*) from gmail_draft_keys) <> 0
    then raise exception 'gmail rows survived profile delete'; end if;
  raise notice '0002_check: ALL CHECKS PASSED';
end $$;
