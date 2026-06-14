-- Sprint 0 — Per-user fee tier override on profiles
-- Applied via Supabase MCP migration `sprint0_profiles_fee_tier` (2026-06-13)
-- NULL fee_pct_override => platform default (3%). Non-null overrides for this user.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS fee_pct_override numeric(5,2) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS fee_note text DEFAULT NULL;

COMMENT ON COLUMN public.profiles.fee_pct_override IS 'Per-user fee % override. NULL = platform default (3%).';
COMMENT ON COLUMN public.profiles.fee_note IS 'Admin internal memo for the fee tier, e.g. "Corporate rate agreed 2026-06".';
