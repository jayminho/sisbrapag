-- ─────────────────────────────────────────────────────────────────
-- SISBRAPAG — Multi-Currency Lock-In
-- Migration: add currency to manual_adjustments
-- ─────────────────────────────────────────────────────────────────
--
-- Allows admin to credit/debit any currency balance directly.
-- Example: user receives a USD wire; admin credits their USD balance.
-- Existing rows default to 'BRL' — no data migration needed.

ALTER TABLE manual_adjustments
  ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'BRL'
    CHECK (currency IN ('BRL','USD','EUR','GBP'));
