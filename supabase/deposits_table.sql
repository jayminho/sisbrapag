-- SISBRAPAG — Manual Deposit Flow (Part 2)
-- deposits table: manual TED/PIX deposits with admin review.
-- Applied to project iiclntwwutsaoorbncfp on 2026-06-12.

create table if not exists public.deposits (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  method          text not null check (method in ('ted','pix')),
  amount          numeric(14,2) not null check (amount > 0),
  reference_code  text not null unique,
  status          text not null default 'created'
                    check (status in ('created','pending_review','credited','rejected','expired')),
  receipt_url     text,
  expires_at      timestamptz not null,
  reviewed_by     uuid references auth.users(id),
  reviewed_at     timestamptz,
  reject_reason   text,
  sender_name     text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists deposits_user_id_idx on public.deposits(user_id);
create index if not exists deposits_status_idx  on public.deposits(status);
create index if not exists deposits_expires_idx on public.deposits(expires_at) where status = 'created';

-- Decision #4: one OPEN deposit per user (created or pending_review)
create unique index if not exists deposits_one_open_per_user
  on public.deposits(user_id) where status in ('created','pending_review');

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists deposits_set_updated_at on public.deposits;
create trigger deposits_set_updated_at
  before update on public.deposits
  for each row execute function public.set_updated_at();

-- RLS
alter table public.deposits enable row level security;

create policy deposits_user_select on public.deposits
  for select using (auth.uid() = user_id);

create policy deposits_user_insert on public.deposits
  for insert with check (auth.uid() = user_id and status = 'created');

create policy deposits_user_update on public.deposits
  for update using (auth.uid() = user_id and status in ('created','pending_review'))
  with check (auth.uid() = user_id and status in ('created','pending_review','expired'));

create policy deposits_admin_all on public.deposits
  for all using ((auth.jwt() ->> 'email') = 'jaymepereiranunes@yahoo.com.br')
  with check ((auth.jwt() ->> 'email') = 'jaymepereiranunes@yahoo.com.br');
