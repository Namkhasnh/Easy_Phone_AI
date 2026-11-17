-- 0002: Gmail (Phase 2 in MVP, D-303; API_GMAIL.md §7, D-151, D-306). Apply after 0001_init.sql.
-- Tokens are Fernet-encrypted by the backend before insert (D-151); the database never sees a plain token.
begin;

create table gmail_accounts (
  id text primary key check (id ~ '^gma_[0-9A-Z]{26}$'),
  user_id uuid not null references profiles(id) on delete cascade,
  email text not null,
  refresh_token_enc bytea not null,
  scopes text[] not null,
  status text not null default 'connected' check (status in ('connected','needsReconnect')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, email));
create index on gmail_accounts (user_id);

-- One row per draft-creating call (API_GMAIL §5, D-105): a retry with the same key returns the same draft. 24 h.
create table gmail_draft_keys (
  user_id uuid not null references profiles(id) on delete cascade,
  idempotency_key text not null,
  account_id text not null references gmail_accounts(id) on delete cascade,
  draft_id text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, idempotency_key));

-- RLS on, and **no** client policy at all: tokens are never readable by the app (API_GMAIL §7).
alter table gmail_accounts   enable row level security;
alter table gmail_draft_keys enable row level security;
revoke all on gmail_accounts, gmail_draft_keys from anon, authenticated;

commit;
