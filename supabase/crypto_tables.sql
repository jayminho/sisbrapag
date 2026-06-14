-- Phase 5: Crypto tables
-- Apply via: Supabase SQL Editor → Run

-- ─── crypto_holdings ─────────────────────────────────────────────────────────
-- One row per user. Balances updated by admin when completing orders.
CREATE TABLE IF NOT EXISTS public.crypto_holdings (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users not null unique,
  btc_balance  numeric(18,8) not null default 0,
  eth_balance  numeric(18,8) not null default 0,
  usdt_balance numeric(18,8) not null default 0,   -- combined TRC20+ERC20 for display
  usdc_balance numeric(18,8) not null default 0,
  updated_at   timestamptz not null default now()
);

ALTER TABLE public.crypto_holdings ENABLE ROW LEVEL SECURITY;

-- Users can read only their own row
CREATE POLICY crypto_holdings_user_select ON public.crypto_holdings
  FOR SELECT USING (auth.uid() = user_id);

-- Admin has full access
CREATE POLICY crypto_holdings_admin_all ON public.crypto_holdings
  FOR ALL USING (auth.jwt()->>'email' = 'jaymepereiranunes@yahoo.com.br');

-- Trigger: auto-update updated_at (reuse existing function)
CREATE TRIGGER set_updated_at_crypto_holdings
  BEFORE UPDATE ON public.crypto_holdings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ─── crypto_orders ───────────────────────────────────────────────────────────
-- Transaction log for buy / sell / withdraw orders
CREATE TABLE IF NOT EXISTS public.crypto_orders (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid references auth.users not null,
  reference_code         text unique not null,           -- e.g. "CX-391847"
  order_type             text not null                   -- 'buy' | 'sell' | 'withdraw'
                           CHECK (order_type IN ('buy','sell','withdraw')),
  asset                  text not null                   -- 'BTC' | 'ETH' | 'USDT' | 'USDC'
                           CHECK (asset IN ('BTC','ETH','USDT','USDC')),
  network                text,                           -- 'ERC20' | 'TRC20' | 'BTC' | 'ETH'

  -- Amounts
  amount_crypto          numeric(18,8) not null,
  amount_brl             numeric(12,2),                  -- BRL leg (buy/sell)
  rate_at_request        numeric(18,2),                  -- BRL per 1 unit of asset
  fee_pct                numeric(5,2) not null default 3.0,
  fee_brl                numeric(12,2),
  fee_crypto             numeric(18,8),                  -- fee in crypto terms (sell/withdraw)

  -- Withdrawal only
  destination_address    text,
  txhash                 text,                           -- blockchain tx hash (set when done)

  -- Status machine: pending → processing → completed | failed
  status                 text not null default 'pending'
                           CHECK (status IN ('pending','processing','completed','failed')),
  failed_reason          text,

  -- Admin execution fields
  reviewed_by            uuid references auth.users,
  completed_at           timestamptz,
  actual_rate            numeric(18,2),                  -- rate Jayme actually executed at
  actual_amount_crypto   numeric(18,8),                  -- actual crypto received/sent
  binance_order_id       text,
  admin_notes            text,

  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS crypto_orders_user_idx   ON public.crypto_orders (user_id);
CREATE INDEX IF NOT EXISTS crypto_orders_status_idx ON public.crypto_orders (status);
CREATE INDEX IF NOT EXISTS crypto_orders_created_idx ON public.crypto_orders (created_at DESC);

ALTER TABLE public.crypto_orders ENABLE ROW LEVEL SECURITY;

-- Users can read their own orders
CREATE POLICY crypto_orders_user_select ON public.crypto_orders
  FOR SELECT USING (auth.uid() = user_id);

-- Users can insert their own orders
CREATE POLICY crypto_orders_user_insert ON public.crypto_orders
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Admin has full access
CREATE POLICY crypto_orders_admin_all ON public.crypto_orders
  FOR ALL USING (auth.jwt()->>'email' = 'jaymepereiranunes@yahoo.com.br');

-- Trigger: auto-update updated_at
CREATE TRIGGER set_updated_at_crypto_orders
  BEFORE UPDATE ON public.crypto_orders
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
