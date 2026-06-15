-- ─────────────────────────────────────────────────────────────────
-- SISBRAPAG — Multi-Currency Lock-In
-- Migration: add source_balance to transfer_requests
-- ─────────────────────────────────────────────────────────────────
--
-- source_balance tracks which currency bucket the transfer draws from:
--   'BRL'        → deduct from BRL balance (legacy behaviour, default)
--   'USD'/'EUR'/'GBP' → deduct from that locked currency balance, NO spread
--
-- Existing rows default to 'BRL' — no data migration needed.

ALTER TABLE transfer_requests
  ADD COLUMN IF NOT EXISTS source_balance TEXT DEFAULT 'BRL'
    CHECK (source_balance IN ('BRL','USD','EUR','GBP'));
