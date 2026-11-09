-- 0001_init (DATA_MODEL §9, D-031, D-033, D-246). Run once in Supabase Dashboard → SQL Editor.
-- Tables + indexes are verbatim from DATA_MODEL §9. Local check: checks/run_local.sh (Docker, no Supabase).
begin;

create table profiles (id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(), locale text not null default 'vi');
create table subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  product_id text not null,                                   -- easyphone.premium.monthly|yearly (D-091)
  original_transaction_id text not null unique,
  expires_at timestamptz, updated_at timestamptz not null default now(),
  status text not null check (status in ('active','expired','inGracePeriod','billingRetry','revoked','refunded')),
  environment text not null check (environment in ('Sandbox','Production','Xcode')));  -- 'Xcode': dev only (D-240)
create table usage_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  endpoint text not null,                                     -- '/v1/parse'
  units int not null default 1,                               -- quota units (D-086, D-093); 0 = refunded (D-231)
  idempotency_key text,                                       -- D-230/D-245; null for unmetered rows
  attempt int not null default 0,                             -- D-246: latest attempt number; only it may commit/refund
  tokens_in int not null default 0, tokens_out int not null default 0,
  cost_usd numeric(10,6) not null default 0, created_at timestamptz not null default now());
create index on usage_events (user_id, created_at);
create unique index on usage_events (user_id, idempotency_key) where idempotency_key is not null;
-- gmail_accounts: Phase 2 only (D-150). Do not create.

alter table profiles      enable row level security;
alter table subscriptions enable row level security;
alter table usage_events  enable row level security;

-- Clients may only read their own rows; the backend writes with the service role (D-033).
create policy profiles_select_own      on profiles      for select to authenticated using (id = (select auth.uid()));
create policy subscriptions_select_own on subscriptions for select to authenticated using (user_id = (select auth.uid()));
create policy usage_events_select_own  on usage_events  for select to authenticated using (user_id = (select auth.uid()));

-- Defense in depth: no client writes even if a write policy is added by mistake.
revoke insert, update, delete, truncate on profiles, subscriptions, usage_events from anon, authenticated;

commit;
