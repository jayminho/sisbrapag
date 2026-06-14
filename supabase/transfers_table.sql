-- Phase 4 Sprint A — International transfers
-- Applied via Supabase MCP migration `phase4_sprintA_transfer_requests` (2026-06-13)
-- Reuses existing public.set_updated_at() trigger function (from deposits).

CREATE TABLE IF NOT EXISTS public.transfer_requests (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid references auth.users not null,
  reference_code        text unique not null,          -- e.g. "TR-847201"

  -- Direction
  direction             text not null check (direction in ('outbound','inbound')),

  -- Amount legs
  amount_source         numeric(15,2) not null,
  currency_source       text not null,
  amount_target         numeric(15,2),
  currency_target       text not null,

  -- Rate & fees (captured at request time)
  fx_rate_at_request    numeric(15,6),
  fee_pct               numeric(5,2) default 3.0,
  fee_brl               numeric(12,2),

  -- Recipient / counterpart details
  recipient_name        text not null,
  recipient_country     text not null,                 -- ISO 3166-1 alpha-2
  routing_type          text not null check (routing_type in ('iban','sort_code','ach','swift')),
  iban                  text,
  bic_swift             text,
  sort_code             text,                          -- UK: XX-XX-XX
  account_number        text,
  ach_routing           text,                          -- 9-digit ABA
  bank_name             text,
  bank_address          text,

  -- BACEN compliance
  purpose_code          text not null,                 -- natureza da operacao
  purpose_description   text,
  reference_note        text,
  recipient_tax_id      text,

  -- Status
  status                text not null default 'submitted'
                          check (status in ('submitted','under_review','processing','completed','cancelled')),
  cancelled_reason      text,

  -- Admin fields
  reviewed_by           uuid references auth.users,   -- admin user id (matches deposits.reviewed_by)
  reviewed_at           timestamptz,
  processing_started_at timestamptz,
  completed_at          timestamptz,
  actual_fx_rate        numeric(15,6),
  actual_amount_target  numeric(15,2),
  partner_ref           text,                          -- bank SWIFT MR / reference
  admin_notes           text,

  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
);

CREATE INDEX IF NOT EXISTS transfers_user_id_idx ON public.transfer_requests (user_id);
CREATE INDEX IF NOT EXISTS transfers_status_idx  ON public.transfer_requests (status);
CREATE INDEX IF NOT EXISTS transfers_created_idx ON public.transfer_requests (created_at DESC);

DROP TRIGGER IF EXISTS set_updated_at_transfer_requests ON public.transfer_requests;
CREATE TRIGGER set_updated_at_transfer_requests
  BEFORE UPDATE ON public.transfer_requests
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- RLS
ALTER TABLE public.transfer_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS transfers_user_select ON public.transfer_requests;
CREATE POLICY transfers_user_select ON public.transfer_requests
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS transfers_user_insert ON public.transfer_requests;
CREATE POLICY transfers_user_insert ON public.transfer_requests
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS transfers_admin_all ON public.transfer_requests;
CREATE POLICY transfers_admin_all ON public.transfer_requests
  FOR ALL USING (auth.jwt()->>'email' = 'jaymepereiranunes@yahoo.com.br');
