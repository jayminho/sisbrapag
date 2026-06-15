# SISBRAPAG — Multi-Currency Lock-In: Architecture & Engineering Plan

**Date:** 2026-06-15  
**Feature:** 4-currency wallet with BRL→FX lock-in, Telegram hedging alerts, fee-aware transfers

---

## 1. CONCEPT SUMMARY

Users deposit BRL. They can "lock in" to USD, EUR, or GBP at today's rate. The 3% margin is captured at swap time. Their foreign balance sits untouched until they decide to send — at which point no additional fee applies because we already made our margin.

```
BRL deposit → Lock In (swap, 3% captured) → USD/EUR/GBP balance → Send (no extra fee)
                                                     ↓
                                            Telegram alert to Jayme → buy USDC hedge
```

---

## 2. DATABASE CHANGES

### 2a. New table: `currency_swaps`

```sql
CREATE TABLE currency_swaps (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reference_code  TEXT UNIQUE,
  from_currency   TEXT NOT NULL DEFAULT 'BRL',
  from_amount     NUMERIC(15,2) NOT NULL,
  to_currency     TEXT NOT NULL CHECK (to_currency IN ('USD','EUR','GBP')),
  to_amount       NUMERIC(15,4) NOT NULL,
  market_rate     NUMERIC(15,6) NOT NULL,   -- raw rate at time of swap
  applied_rate    NUMERIC(15,6) NOT NULL,   -- market_rate * 1.03 (user pays this)
  fee_pct         NUMERIC(5,2)  NOT NULL DEFAULT 3.00,
  status          TEXT NOT NULL DEFAULT 'completed',
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- RLS
-- NOTE: service_role key bypasses RLS automatically in edge functions.
-- No separate service_role policy needed or correct here.
ALTER TABLE currency_swaps ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_own_swaps" ON currency_swaps
  FOR ALL USING (auth.uid() = user_id);

-- Reference code: use a sequence to avoid RANDOM() collision risk
CREATE SEQUENCE swap_ref_seq START 1;

CREATE OR REPLACE FUNCTION generate_swap_ref() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.reference_code IS NULL THEN
    NEW.reference_code := 'SWP-' || TO_CHAR(NOW(), 'YYYYMMDD') ||
      LPAD(NEXTVAL('swap_ref_seq')::TEXT, 5, '0');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_swap_ref
  BEFORE INSERT ON currency_swaps
  FOR EACH ROW EXECUTE FUNCTION generate_swap_ref();
```

### 2aa. Atomic swap RPC — `perform_swap()`

The edge function must NOT do: fetch balance → check → insert (race condition if two requests overlap).
Instead, a single Postgres RPC handles the entire operation atomically with row-level locking.

```sql
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
  -- Lock the user's deposit rows to prevent concurrent double-spend
  PERFORM pg_advisory_xact_lock(hashtext(p_user_id::TEXT));

  -- Compute current BRL balance inline
  SELECT
    COALESCE(SUM(d.amount), 0)
    - COALESCE((SELECT SUM(co.amount_brl) FROM crypto_orders co
                WHERE co.user_id = p_user_id AND co.status = 'completed' AND co.order_type = 'buy'), 0)
    + COALESCE((SELECT SUM(co.amount_brl) FROM crypto_orders co
                WHERE co.user_id = p_user_id AND co.status = 'completed' AND co.order_type = 'sell'), 0)
    - COALESCE((SELECT SUM(tr.amount_source) FROM transfer_requests tr
                WHERE tr.user_id = p_user_id AND tr.status != 'cancelled'
                  AND (tr.source_balance = 'BRL' OR tr.source_balance IS NULL)), 0)
    + COALESCE((SELECT SUM(ma.amount) FROM manual_adjustments ma
                WHERE ma.user_id = p_user_id AND (ma.currency = 'BRL' OR ma.currency IS NULL)), 0)
    - COALESCE((SELECT SUM(cs.from_amount) FROM currency_swaps cs
                WHERE cs.user_id = p_user_id AND cs.status = 'completed'), 0)
  INTO v_brl_balance
  FROM deposits d
  WHERE d.user_id = p_user_id AND d.status = 'credited';

  IF v_brl_balance < p_from_amount THEN
    RAISE EXCEPTION 'insufficient_balance: have % need %', v_brl_balance, p_from_amount;
  END IF;

  INSERT INTO currency_swaps (
    user_id, from_currency, from_amount,
    to_currency, to_amount, market_rate, applied_rate, fee_pct, status
  ) VALUES (
    p_user_id, 'BRL', p_from_amount,
    p_to_currency, p_to_amount, p_market_rate, p_applied_rate, 3.00, 'completed'
  )
  RETURNING * INTO v_swap;

  RETURN v_swap;
END;
$$;
```

Edge function simply calls: `supabase.rpc('perform_swap', { p_user_id, p_from_amount, ... })`
One round trip. Atomically safe.

### 2b. Alter `transfer_requests`

Add one column to track which balance the transfer draws from:

```sql
ALTER TABLE transfer_requests
  ADD COLUMN source_balance TEXT DEFAULT 'BRL'
  CHECK (source_balance IN ('BRL','USD','EUR','GBP'));
-- NULL / 'BRL' = legacy behaviour (deduct BRL, apply spread at transfer time)
-- 'USD'/'EUR'/'GBP' = deduct from locked balance, NO additional spread
```

### 2b. Alter `manual_adjustments` — add currency column

```sql
ALTER TABLE manual_adjustments
  ADD COLUMN currency TEXT NOT NULL DEFAULT 'BRL'
  CHECK (currency IN ('BRL','USD','EUR','GBP'));
```

This lets you manually credit/debit any currency balance (e.g., you receive a wire on a user's behalf and need to credit their USD). The `getBalances()` function buckets adjustments by currency.

### 2c. No stored balances

Balances remain **derived** (computed from transactions), consistent with the existing pattern. No balance columns on the users/profiles table. Single source of truth = the transaction tables.

---

## 3. BALANCE FORMULA

### Current (BRL only)
```
BRL = deposited − spentBuy + earnedSell − spentXfer + adjTotal
```

### New: `getBalances()` returns `{ brl, usd, eur, gbp }`

**BRL:**
```
deposited
− spentBuy          (crypto_orders buy, completed)
+ earnedSell        (crypto_orders sell, completed)
− spentXferBRL      (transfer_requests where source_balance='BRL', not cancelled)
+ adjTotal          (manual_adjustments)
− swappedOutBRL     (currency_swaps from_currency='BRL', completed)
```

**USD (same pattern for EUR / GBP):**
```
swappedInUSD        (currency_swaps to_currency='USD', completed → sum to_amount)
− spentXferUSD      (transfer_requests where source_balance='USD', not cancelled → sum amount_source)
```

### Implementation note
All 5 source tables fetched in one `Promise.all`. The function returns the object; callers pick the currency they need.

---

## 4. SWAP RATE LOGIC

Market rate fetched from the existing 4-tier BRL system (AwesomeAPI → Frankfurter/BCB → exchangerate-api → hardcoded).

**Applied rate = market_rate × 1.03**  
(User pays more BRL per foreign unit — margin captured here.)

Example — sperle, R$40,600 → USD:
| | |
|---|---|
| Market rate | 5.7000 BRL/USD |
| Applied rate | 5.8710 BRL/USD |
| USD credited | **$6,915.49** |
| Margin captured | R$ 1,218.00 (≈ 3%) |

When sperle later sends $6,915.49 USD → **no additional deduction**.

---

## 5. NEW EDGE FUNCTION: `execute-swap`

**File:** `supabase/functions/execute-swap/index.ts`

```
POST /execute-swap
Body: { to_currency: 'USD'|'EUR'|'GBP', from_amount: number }
Auth: Bearer (user JWT)
```

Steps:
1. Authenticate user from JWT (reject if no valid session)
2. Fetch live market rate for `to_currency` (4-tier BRL system)
3. Compute `applied_rate = market_rate * 1.03`
4. Compute `to_amount = from_amount / applied_rate`
5. Call `perform_swap()` RPC via service_role client (atomic balance check + insert)
6. If RPC throws `insufficient_balance` → return 400
7. Fire Telegram notification (type: `swap`) — non-blocking (don't await or fail swap if Telegram is down)
8. Return `{ swap_id, reference_code, to_amount, applied_rate, to_currency }`

**Security:** Balance check happens server-side inside the RPC. Client never tells server what the balance is.
**Telegram is fire-and-forget:** a Telegram outage must never block a swap from completing.

---

## 6. TELEGRAM NOTIFICATION — NEW TYPE: `swap`

Add to `notify-telegram/index.ts`:

```typescript
} else if (type === 'swap') {
  const { name, userEmail, fromAmount, toCurrency, toAmount, appliedRate, marketRate, ref } = body
  const flag = { USD: '🇺🇸', EUR: '🇪🇺', GBP: '🇬🇧' }[toCurrency] || '🌍'
  text = [
    `🔒 *Lock In — Câmbio executado*`,
    ``,
    `👤 Cliente: ${name || '—'}`,
    userEmail ? `📧 ${userEmail}` : null,
    `💵 BRL debitado: R$ ${fromAmount}`,
    `${flag} ${toCurrency} creditado: ${toAmount}`,
    `📊 Taxa aplicada: ${appliedRate} BRL/${toCurrency}`,
    `💹 Taxa mercado: ${marketRate} BRL/${toCurrency}`,
    `🔖 Ref: \`${ref}\``,
    ``,
    `→ Comprar USDC: ~${toAmount} ${toCurrency}`,
  ].filter(Boolean).join('\n')
}
```

---

## 7. TRANSFER PAGE LOGIC CHANGES

### Fee decision tree
```
User wants to send USD
  ├─ Has USD balance ≥ amount?
  │     YES → draw from USD balance, source_balance='USD', NO spread
  │     NO  → draw from BRL balance, convert at transfer time, 3% applies
  └─ (user cannot mix — must use one source)
```

### UI change on transfer form
- Add source selector when user has foreign balance: "Send from: [BRL balance] or [USD balance]"
- If USD selected: fee line shows "✓ Conversion fee already applied at lock-in"
- If BRL selected (for foreign currency transfer): fee line shows "3% service fee applies"

---

## 8. UI DESIGN

### 8a. Overview — Balance section

Replace the single balance card with a multi-currency display.

**Layout (4 cards, 2×2 grid):**
```
┌─────────────────────┬─────────────────────┐
│  BRL                │  USD                │
│  R$ 0,00            │  $6.915,49          │
│  [+ Add Funds]      │  [Lock In more]     │
├─────────────────────┼─────────────────────┤
│  EUR                │  GBP                │
│  €0,00              │  £0,00              │
│  [Lock In]          │  [Lock In]          │
└─────────────────────┴─────────────────────┘
```

Rules:
- Cards with zero balance show gray amount, still visible (no hidden state)
- Each card has a small action link: BRL → "+ Add Funds", foreign currencies → "Lock In"
- The currency with the largest balance gets a subtle highlight border

### 8b. Sidebar nav change

Rename "Converter" → "Lock In"  
Icon: `fa-lock` (replaces `fa-calculator`)

### 8c. Lock In section (replaces Converter)

```
┌─────────────────────────────────────────────┐
│  LOCK IN                                    │
│  Convert BRL to a foreign currency          │
│  and protect your money from devaluation.   │
│                                             │
│  YOUR BRL BALANCE                           │
│  R$ 40.600,00                               │
│                                             │
│  CONVERT TO                                 │
│  [ USD ▼ ]  [ EUR ▼ ]  [ GBP ▼ ]  ← tabs  │
│                                             │
│  AMOUNT (BRL)                               │
│  ┌──────────────────────────┐               │
│  │ R$ 40.600,00             │  [USE ALL]    │
│  └──────────────────────────┘               │
│                                             │
│  YOU WILL LOCK IN                           │
│  $6.915,49 USD                              │
│  Rate: 5.871 BRL/USD (incl. 3% fee)        │
│                                             │
│  [  LOCK IN NOW  ]                          │
│                                             │
│  ⓘ Locked funds can be sent anytime.       │
│    No additional fee when sending.          │
└─────────────────────────────────────────────┘
```

**After confirmation:**
```
┌─────────────────────────────────────────────┐
│  ✓ Locked in successfully                   │
│                                             │
│  $6.915,49 USD added to your balance        │
│  Ref: SWP-2026061500001                     │
│                                             │
│  [  VIEW BALANCE  ]  [  LOCK IN MORE  ]     │
└─────────────────────────────────────────────┘
```

### 8d. Transaction history — new row type

Swap rows display as:
```
15 jun 2026  |  Lock In ↔  |  SWP-xxx  |  R$ 40.600 → $6.915,49 USD  |  ● Completed
```

---

## 9. FILES TO CHANGE

| File | Change |
|------|--------|
| `supabase/currency_swaps.sql` | New table + perform_swap RPC (replaces naive insert) |
| `supabase/transfers_source_balance.sql` | ALTER transfer_requests ADD source_balance |
| `supabase/manual_adjustments_currency.sql` | ALTER manual_adjustments ADD currency |
| `supabase/functions/execute-swap/index.ts` | New edge function (calls RPC, fires Telegram async) |
| `supabase/functions/notify-telegram/index.ts` | Add `swap` type |
| `dashboard.html` | getBalances(), 4-currency cards, Lock In section, transfer logic, tx history, nav rename |

---

## 10. IMPLEMENTATION ORDER

```
Phase 1 — Database
  1. Run currency_swaps migration
  2. Run transfers_source_balance migration

Phase 2 — Backend
  3. Deploy execute-swap edge function
  4. Update notify-telegram with swap type

Phase 3 — Frontend
  5. Update getAvailableBalance() → getBalances()
  6. Update Overview balance display (4 cards)
  7. Replace Converter with Lock In (calls execute-swap)
  8. Update transfer section (source_balance logic)
  9. Update tx history (show swaps)
  10. Rename nav item
```

---

## 11. EDGE CASES & RULES

| Scenario | Behaviour |
|----------|-----------|
| User swaps partial BRL (not all) | Both BRL and USD balances coexist |
| User tries to swap more than BRL balance | Server rejects with 400 |
| User has USD balance but sends less than balance | Remaining USD balance unchanged |
| User has USD and wants to send EUR | Must use BRL balance (cross-currency via BRL) |
| Rate fetch fails | Swap blocked, error shown, user retries |
| Admin manual_adjustment in foreign currency | Out of scope for now — BRL only |

---

## 12. NOT IN SCOPE (this iteration)

- Reverse swap: USD → BRL (not needed yet)
- Partial swap of foreign balance back to BRL
- Interest or yield on locked balances
- Crypto interaction with FX balances
- PIX deposit directly into USD (BRL deposit first, then swap)
