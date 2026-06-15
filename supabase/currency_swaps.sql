-- ─────────────────────────────────────────────────────────────────
-- SISBRAPAG — Multi-Currency Lock-In
-- Migration: currency_swaps table + perform_swap() atomic RPC
-- ─────────────────────────────────────────────────────────────────

-- 1. TABLE
CREATE TABLE IF NOT EXISTS currency_swaps (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reference_code  TEXT UNIQUE,
  from_currency   TEXT NOT NULL DEFAULT 'BRL',
  from_amount     NUMERIC(15,2) NOT NULL,
  to_currency     TEXT NOT NULL CHECK (to_currency IN ('USD','EUR','GBP')),
  to_amount       NUMERIC(15,4) NOT NULL,
  market_rate     NUMERIC(15,6) NOT NULL,   -- raw market rate at time of swap
  applied_rate    NUMERIC(15,6) NOT NULL,   -- market_rate * 1.03 (3% spread captured here)
  fee_pct         NUMERIC(5,2)  NOT NULL DEFAULT 3.00,
  status          TEXT NOT NULL DEFAULT 'completed',
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- 2. RLS
-- service_role key bypasses RLS automatically in edge functions — no separate policy needed.
ALTER TABLE currency_swaps ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_swaps" ON currency_swaps
  FOR ALL USING (auth.uid() = user_id);

-- 3. REFERENCE CODE — sequence-based to avoid RANDOM() collision
CREATE SEQUENCE IF NOT EXISTS swap_ref_seq START 1;

CREATE OR REPLACE FUNCTION generate_swap_ref()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.reference_code IS NULL THEN
    NEW.reference_code :=
      'SWP-' || TO_CHAR(NOW(), 'YYYYMMDD') ||
      LPAD(NEXTVAL('swap_ref_seq')::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_swap_ref ON currency_swaps;
CREATE TRIGGER set_swap_ref
  BEFORE INSERT ON currency_swaps
  FOR EACH ROW EXECUTE FUNCTION generate_swap_ref();

-- 4. ATOMIC SWAP RPC
-- The edge function calls this single function. The advisory lock prevents
-- two simultaneous requests from both passing the balance check before
-- either has committed its insert.
CREATE OR REPLACE FUNCTION perform_swap(
  p_user_id      UUID,
  p_from_amount  NUMERIC,
  p_to_currency  TEXT,
  p_to_amount    NUMERIC,
  p_market_rate  NUMERIC,
  p_applied_rate NUMERIC
)
RETURNS currency_swaps
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_brl_balance  NUMERIC;
  v_swap         currency_swaps;
BEGIN
  -- Serialize concurrent swap attempts for this user
  PERFORM pg_advisory_xact_lock(hashtext(p_user_id::TEXT));

  -- Compute current BRL balance
  SELECT
    COALESCE((
      SELECT SUM(amount) FROM deposits
      WHERE user_id = p_user_id AND status = 'credited'
    ), 0)
    - COALESCE((
      SELECT SUM(amount_brl) FROM crypto_orders
      WHERE user_id = p_user_id AND status = 'completed' AND order_type = 'buy'
    ), 0)
    + COALESCE((
      SELECT SUM(amount_brl) FROM crypto_orders
      WHERE user_id = p_user_id AND status = 'completed' AND order_type = 'sell'
    ), 0)
    - COALESCE((
      SELECT SUM(amount_source) FROM transfer_requests
      WHERE user_id = p_user_id
        AND status != 'cancelled'
        AND (source_balance = 'BRL' OR source_balance IS NULL)
    ), 0)
    + COALESCE((
      SELECT SUM(amount) FROM manual_adjustments
      WHERE user_id = p_user_id
        AND (currency = 'BRL' OR currency IS NULL)
    ), 0)
    - COALESCE((
      SELECT SUM(from_amount) FROM currency_swaps
      WHERE user_id = p_user_id AND status = 'completed'
    ), 0)
  INTO v_brl_balance;

  IF COALESCE(v_brl_balance, 0) < p_from_amount THEN
    RAISE EXCEPTION 'insufficient_balance: have % BRL, need % BRL',
      ROUND(COALESCE(v_brl_balance, 0), 2), p_from_amount;
  END IF;

  INSERT INTO currency_swaps (
    user_id,
    from_currency,
    from_amount,
    to_currency,
    to_amount,
    market_rate,
    applied_rate,
    fee_pct,
    status
  ) VALUES (
    p_user_id,
    'BRL',
    p_from_amount,
    p_to_currency,
    p_to_amount,
    p_market_rate,
    p_applied_rate,
    3.00,
    'completed'
  )
  RETURNING * INTO v_swap;

  RETURN v_swap;
END;
$$;
