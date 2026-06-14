# SISBRAPAG — Phase 4 & 5 Master Design Document
> Research-based design spec. No code built yet. Written: 2026-06-13

---

## About the receipt (Jayme's question)
The **deposit receipt** (jsPDF, branded PDF attached to credit/reject emails) is **100% complete** as of commit `6d03ffe`. 
Phases 4 and 5 each need their own receipt — same engine, different fields. Designed in this doc.

---

## Regulatory research summary

### International Transfers (BCB/BACEN — Res. 277/2022)
- All FX operations require a **"natureza da operação"** purpose code (BACEN classification).
- Companies without a corretora de câmbio license acting as a frontend/aggregator: the **partner bank** (executes the trade) bears the regulatory reporting obligation — SISBRAPAG just collects the data and passes it along. This is exactly the model here.
- Limit for unlicensed eFX fintechs: **USD 10,000 per operation**. If SISBRAPAG processes above that per client/operation, it must use a licensed bank as execution partner (already planned).
- KYC: counterpart name, CPF/CNPJ, and purpose are mandatory fields on all FX operations.
- A "natureza fiscal" code must be included — the partner bank files this. SISBRAPAG captures it from the user.

### Crypto (BCB Res. 519/520/521 — effective Feb 2, 2026)
- VASP license requires **R$10.8M–R$37.2M capital** + BCB authorization + independent CVM-registered auditor. SISBRAPAG does NOT become a VASP.
- **SISBRAPAG's model:** acts as a **client of Binance** (a licensed VASP), executing manually. Binance handles VASP compliance, Travel Rule, etc.
- **Reporting obligation (IN RFB 1888/2019):** crypto transactions above **R$35,000/month per user** must be reported. Since Binance is the exchange of execution, this obligation falls on Binance. SISBRAPAG should display a disclaimer and maintain internal logs for audit purposes.
- **What SISBRAPAG must do:** collect user KYC (already done), maintain internal transaction records, and add crypto disclaimer language to terms.

### Banking routing formats
| Currency | Routing type | Format | Notes |
|----------|-------------|--------|-------|
| EUR (EU/EEA) | IBAN | Up to 34 chars, starts with 2-letter country code + 2 check digits | Validate checksum client-side |
| GBP (UK) | Sort Code + Account | Sort: `XX-XX-XX` (6 digits) + 8-digit account | Sort code is embedded in UK IBAN at pos 9–14 |
| USD (USA) | ACH Routing + Account | Routing: exactly 9 digits (ABA) + account | Can also need SWIFT for intl wires |
| Any country | SWIFT/BIC + Account | 8 or 11 chars: BANK + CC + LL + BBB | Universal fallback |
| BRL (Brazil) | PIX key / TED | CPF, CNPJ, phone, email, or random UUID | For inbound transfers landing in BRL |

---

## Architecture: how phases interconnect

```
┌─────────────────────────────────────────────────────────────┐
│                    SISBRAPAG PLATFORM                       │
│                                                             │
│  BRL Balance (from deposits)  ←──────────────────────────┐ │
│         │                                                 │ │
│         ├──► Phase 4: International Transfer              │ │
│         │    (BRL → USD/EUR/GBP outbound)                 │ │
│         │    (USD/EUR → BRL inbound credit)               │ │
│         │                                                 │ │
│         └──► Phase 5: Crypto                              │ │
│              Buy: BRL deducted → crypto_holdings +        │ │
│              Sell: crypto_holdings - → BRL credited ──────┘ │
│              Withdraw: crypto_holdings - → external wallet  │
│                                                             │
│  Shared: FX rates · jsPDF receipts · Telegram · Emails     │
└─────────────────────────────────────────────────────────────┘
         │ Manual execution                │ Manual execution
         ▼                                 ▼
   Partner Bank                        Binance Business
   (FX leg)                            (Crypto trades)
```

---

## PHASE 4 — INTERNATIONAL TRANSFERS

### Concept
User submits a transfer request through the dashboard. Jayme receives it via Telegram + email + admin panel. Jayme executes the FX trade manually through the partner bank. Clicks "Concluído" in admin. System generates a PDF receipt and emails the user.

### Transfer directions
- **Outbound**: User pays BRL → recipient abroad gets USD/EUR/GBP/etc.
- **Inbound**: Foreign party sends USD/EUR → user receives BRL credit on platform

---

### Status machine

```
submitted
    │
    ▼
under_review  ──► (Jayme verifying KYC/limits)
    │
    ▼
processing  ──► (wire sent, waiting settlement)
    │
    ├──► completed  (settled, PDF receipt sent)
    └──► cancelled  (with reason, user email sent)
```

---

### DB Schema — `transfer_requests`

```sql
CREATE TABLE public.transfer_requests (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid references auth.users not null,
  reference_code       text unique not null,         -- 6-digit numeric, e.g. "TR-847201"

  -- Direction
  direction            text not null,                -- 'outbound' | 'inbound'

  -- Amount legs
  amount_source        numeric(15,2) not null,       -- amount user sends
  currency_source      text not null,                -- 'BRL' | 'USD' | 'EUR' | 'GBP'
  amount_target        numeric(15,2),                -- estimated at request (can differ from actual)
  currency_target      text not null,                -- 'USD' | 'EUR' | 'GBP' | 'BRL'

  -- Rate & fees (captured at request time)
  fx_rate_at_request   numeric(15,6),               -- e.g. 5.1234 (BRL per USD)
  fee_pct              numeric(5,2) default 3.0,    -- percentage fee
  fee_brl              numeric(12,2),               -- fee in BRL

  -- Recipient / counterpart details
  recipient_name       text not null,
  recipient_country    text not null,               -- ISO 3166-1 alpha-2
  routing_type         text not null,               -- 'iban' | 'sort_code' | 'ach' | 'swift'
  iban                 text,
  bic_swift            text,
  sort_code            text,                        -- UK: XX-XX-XX
  account_number       text,                        -- account number for sort_code / ach / swift
  ach_routing          text,                        -- 9-digit ABA routing number
  bank_name            text,
  bank_address         text,                        -- optional, for compliance

  -- BACEN compliance
  purpose_code         text not null,              -- natureza da operação
  purpose_description  text,                        -- human-readable
  reference_note       text,                        -- free-text from user (invoice #, etc.)
  recipient_tax_id     text,                        -- CPF/CNPJ or foreign tax ID

  -- Status
  status               text not null default 'submitted',
  cancelled_reason     text,

  -- Admin fields
  reviewed_by          text,
  reviewed_at          timestamptz,
  processing_started_at timestamptz,
  completed_at         timestamptz,
  actual_fx_rate       numeric(15,6),              -- rate used when actually executed
  actual_amount_target numeric(15,2),              -- what actually arrived / was sent
  partner_ref          text,                       -- bank's reference/SWIFT MR number
  admin_notes          text,

  created_at           timestamptz default now(),
  updated_at           timestamptz default now()
);

-- Indexes
CREATE INDEX transfers_user_id_idx ON public.transfer_requests (user_id);
CREATE INDEX transfers_status_idx ON public.transfer_requests (status);
CREATE INDEX transfers_created_idx ON public.transfer_requests (created_at DESC);

-- Auto-update trigger (reuse existing set_updated_at)
CREATE TRIGGER set_updated_at_transfer_requests
  BEFORE UPDATE ON public.transfer_requests
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- RLS
ALTER TABLE public.transfer_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY transfers_user_select ON public.transfer_requests
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY transfers_user_insert ON public.transfer_requests
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY transfers_admin_all ON public.transfer_requests
  FOR ALL USING (auth.jwt()->>'email' = 'jaymepereiranunes@yahoo.com.br');
```

---

### BACEN Purpose Codes (natureza da operação) — simplified dropdown

| Code | Label (PT) | Use case |
|------|-----------|---------|
| `SERVICOS` | Pagamento de serviços ao exterior | Software, consulting, SaaS |
| `IMPORTACAO` | Importação de mercadorias | Physical goods |
| `REMESSA_PF` | Remessa pessoal ao exterior | Personal transfer |
| `MANUTENCAO` | Manutenção de residente no exterior | Support for family abroad |
| `INVESTIMENTO` | Investimento no exterior | Financial investment |
| `DIVIDENDOS` | Remessa de dividendos e lucros | Profit distribution |
| `ROYALTIES` | Royalties e licenças | IP licensing |
| `OUTROS` | Outros (descrever) | Catch-all — requires description |

---

### Routing forms by destination

**EUR (SEPA):**
```
Recipient name (full legal name)    [required]
IBAN                                [required, validate checksum]
BIC/SWIFT                           [required, 8-11 chars]
Bank name                           [optional]
Purpose code                        [dropdown]
Reference / invoice number          [optional]
```

**GBP (UK):**
```
Recipient name                      [required]
Sort Code                           [required, format: XX-XX-XX, auto-format]
Account Number                      [required, 8 digits]
BIC/SWIFT                           [optional for UK domestic, required for intl]
Purpose code                        [dropdown]
Reference / invoice number          [optional]
```

**USD (USA):**
```
Recipient name                      [required]
ACH Routing Number                  [required, exactly 9 digits, validate MOD10]
Account Number                      [required]
Account type                        [Checking / Savings]
Bank name                           [required for USD wires]
SWIFT/BIC                           [optional — needed if bank requires intl wire vs ACH]
Purpose code                        [dropdown]
Reference / invoice number          [optional]
```

**Other currencies / SWIFT:**
```
Recipient name                      [required]
SWIFT/BIC                           [required]
Account Number / IBAN               [required]
Bank name                           [required]
Bank address                        [required]
Recipient address                   [required]
Recipient tax ID                    [required]
Purpose code                        [dropdown]
Reference / invoice number          [optional]
```

---

### User flow — step by step (dashboard.html)

```
[Transfers] nav tab
      │
      ▼
┌─────────────────────┐
│  STEP 1: Direction  │
│  ● Enviar (Outbound)│
│  ○ Receber (Inbound)│
└────────┬────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│  STEP 2: Amount & Currency              │
│  Você envia:  [R$ ___________] BRL      │
│  Destinatário recebe em: [USD ▼]        │
│  Taxa hoje: 1 USD = 5.12 BRL            │
│  Taxa SISBRAPAG (3%): R$ 153.60         │
│  Valor estimado: USD 970.08             │
│  ──────────────────────────────         │
│  [Continuar →]                          │
└────────┬────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│  STEP 3: Dados do Destinatário          │
│  (Form adapts to currency/country)      │
│  Nome completo: [________________]      │
│  País: [United States ▼]               │
│  ABA Routing: [_________]  ✅/⚠️        │
│  Conta: [__________________]            │
│  Banco: [________________]              │
│  [Continuar →]                          │
└────────┬────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│  STEP 4: Finalidade (BACEN)             │
│  Natureza: [Pagamento de serviços ▼]    │
│  Nota/Referência: [Invoice #___]        │
│  [Continuar →]                          │
└────────┬────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│  STEP 5: Confirmar                      │
│  Você envia: R$ 5.120,00               │
│  Destinatário recebe: ~USD 970,08       │
│  Taxa: 1 USD = 5.12 BRL                │
│  Taxa SISBRAPAG: R$ 153,60 (3%)        │
│  Ref: TR-847201                         │
│  ☐ Li e concordo com os Termos         │
│  [Enviar solicitação]                   │
└────────┬────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│  STEP 6: Status                         │
│  ● Solicitação recebida  ✅  13/06      │
│  ○ Em análise                           │
│  ○ Em processamento                     │
│  ○ Concluída                            │
│  Ref: TR-847201                         │
│  Nossa equipe entrará em contato.       │
└─────────────────────────────────────────┘
```

---

### Admin flow (admin.html)

**Transfers tab:**
- Badge shows count of `submitted` + `under_review` transfers
- Table: Ref | User | Direction | Amount | Status | Date | Actions

**Transfer detail modal:**
```
TR-847201  │  João Silva  │  Outbound BRL→USD
─────────────────────────────────────────────
User KYC:        ✅ Verified (docs uploaded)
Amount:          R$ 5.120,00 → ~USD 970,08
Rate at request: 5.12 BRL/USD
Fee:             R$ 153,60 (3%)
Recipient:       John Doe
Routing:         ACH | 021000021 | Acc 123456789
Bank:            JPMorgan Chase, New York
Purpose:         Pagamento de serviços ao exterior
Ref note:        Invoice #2024-042
Submitted:       13/06/2026 14:32
─────────────────────────────────────────────
[Marcar "Em análise"]  [Marcar "Em processamento"]
[✅ Concluir]           [❌ Cancelar]
```

**"Concluir" modal:**
```
Taxa real executada: [5.0987 ____]   ← actual rate used
Valor real recebido: [USD ____]      ← what arrived
Ref do banco/SWIFT MR: [__________]
Notas (opcional): [_______________]
[Gerar PDF + Enviar ao cliente]
```

**"Cancelar" modal:**
```
Motivo do cancelamento:
● Documentação insuficiente
● Dados bancários incorretos
● Limite excedido
● Operação não autorizada
● Outro: [_______________]
[Cancelar transferência]
```

---

### Email stages

| Trigger | To | Subject | Content |
|---------|-----|---------|---------|
| `submitted` | User | Solicitação de transferência recebida | Ref, amounts, "entraremos em contato em até 1 dia útil" |
| `under_review` | User | Transferência em análise | "Estamos verificando sua solicitação" |
| `processing` | User | Transferência em processamento | "O envio foi iniciado", estimated settlement |
| `completed` | User | Transferência concluída ✅ | PDF receipt attached, actual amounts, bank ref |
| `cancelled` | User | Transferência cancelada | Reason, what to do next, WhatsApp link |
| `submitted` | Admin via Telegram | New transfer request | Same as deposit Telegram notify |

---

### PDF Receipt — Transfer (jsPDF, same engine as deposit)

```
┌────────────────────────────────────────────────────┐
│  SISBRAPAG            COMPROVANTE DE TRANSFERÊNCIA │
├────────────────────────────────────────────────────┤
│  ██████ CONCLUÍDA ██████       Ref: TR-847201      │
│                                13/06/2026 16:45    │
├────────────────────────────────────────────────────┤
│  REMETENTE                                         │
│  Nome: João Silva                                  │
│  Enviou: R$ 5.120,00                               │
│                                                    │
│  DESTINATÁRIO                                      │
│  Nome: John Doe                                    │
│  Recebeu: USD 970,08                               │
│  Banco: JPMorgan Chase (ACH 021000021)             │
│  Conta: 123456789                                  │
│                                                    │
│  CÂMBIO                                            │
│  Taxa utilizada: 1 USD = 5.0987 BRL                │
│  Taxa de serviço: R$ 153,60 (3%)                   │
│  Ref. bancária: SFTXXXXXXXXXX                      │
│                                                    │
│  Finalidade: Pagamento de serviços ao exterior     │
├────────────────────────────────────────────────────┤
│  Este comprovante é de caráter informativo.        │
│  atendimento@sisbrapag.com  │  wa.me/5521987128712 │
└────────────────────────────────────────────────────┘
```

---

### Telegram notification (reuse notify-telegram edge fn, add `type: 'transfer'`)

```
🏦 *Nova Transferência*

👤 João Silva
📤 Saída: R$ 5.120,00 → USD
🏛️ JPMorgan Chase (ACH)
🎯 Pagamento de serviços
🔖 Ref: TR-847201

🔗 admin.sisbrapag.com
```

---

### Baby steps — implementation order (Phase 4)

**Sprint A — Database & scaffolding**
1. Write SQL migration: `transfer_requests` table + RLS → `supabase/transfers_table.sql`
2. Deploy migration via Supabase MCP `apply_migration`
3. Verify with `list_tables`

**Sprint B — Dashboard: direction + amount**
4. Add "Transferências" nav item + `#section-transfers` to dashboard.html
5. Build Step 1 (direction toggle: Enviar / Receber)
6. Build Step 2 (amount input + currency selector + live FX rate from existing Frankfurter logic + fee calc display)

**Sprint C — Dashboard: routing form**
7. Build Step 3 routing form — 4 variants:
   - IBAN + SWIFT (EUR)
   - Sort Code + Account (GBP)
   - ACH Routing + Account (USD)
   - SWIFT + Account (generic)
8. Add client-side validators:
   - IBAN: length check + country prefix check (no full MOD97 needed, just basic)
   - ACH Routing: exactly 9 digits, numeric
   - Sort Code: exactly 6 digits, auto-format XX-XX-XX
   - SWIFT: 8 or 11 chars, alphanumeric
9. Show green ✅ or orange ⚠️ inline per field

**Sprint D — Dashboard: purpose + submit + status**
10. Build Step 4 (purpose dropdown with BACEN codes)
11. Build Step 5 (review summary + submit → insert into `transfer_requests`)
12. On submit: call `send-email` edge fn (user confirmation) + call `notify-telegram` edge fn (admin)
13. Build Step 6 / status view (query `transfer_requests` for this user, show timeline)
14. Add "Minhas transferências" list (past transfers with status badges)

**Sprint E — Admin: transfers tab**
15. Add "Transferências" nav to admin.html with pending badge
16. Build transfers table (ref, user, direction, amount, status, date)
17. Build transfer detail modal (all fields + action buttons)

**Sprint F — Admin: actions + receipt**
18. "Em análise" + "Em processamento" buttons → update status + email user
19. "Concluir" modal (actual rate, actual amount, bank ref) → update status → generate PDF receipt → email user with PDF
20. "Cancelar" modal (canned reasons) → update status → email user

**Sprint G — PDF receipt**
21. Add `buildTransferReceiptPdf(transfer, outcome)` to admin.html using existing jsPDF pattern
22. Attach to completion email via `send-email` edge fn `attachments` array

---

## PHASE 5 — CRYPTO

### Concept
User holds a BRL balance (from deposits). They can buy crypto (BRL → crypto, manually executed by Jayme on Binance Business). Crypto is held as an internal "display balance" within SISBRAPAG. User can sell back to BRL or withdraw to an external wallet address.

### Key design decisions
- **No self-custody in P1.** SISBRAPAG shows a "portfolio" balance — crypto is actually held in Binance Business account.
- **Not a VASP.** Binance is the VASP. SISBRAPAG is Binance's client.
- **3% fee on all operations** (already established pricing on services.html).
- **Supported assets (P1):** BTC, ETH, USDT (TRC20 + ERC20), USDC (ERC20).
- **CoinGecko rates** already integrated in dashboard converter — reuse directly.
- **BRL balance deducted on buy.** If user doesn't have sufficient BRL balance, show error and direct to Deposit.

---

### Status machine (same for all order types)

```
pending
    │
    ▼
processing  (Jayme executing on Binance)
    │
    ├──► completed
    └──► failed  (with reason)
```

---

### DB Schema — `crypto_holdings` + `crypto_orders`

```sql
-- One row per user. Updated by admin when completing orders.
CREATE TABLE public.crypto_holdings (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users not null unique,
  btc_balance  numeric(18,8) default 0,
  eth_balance  numeric(18,8) default 0,
  usdt_balance numeric(18,8) default 0,  -- combined TRC20+ERC20 for display
  usdc_balance numeric(18,8) default 0,
  updated_at  timestamptz default now()
);

ALTER TABLE public.crypto_holdings ENABLE ROW LEVEL SECURITY;

CREATE POLICY crypto_holdings_user_select ON public.crypto_holdings
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY crypto_holdings_admin_all ON public.crypto_holdings
  FOR ALL USING (auth.jwt()->>'email' = 'jaymepereiranunes@yahoo.com.br');

-- Transaction log
CREATE TABLE public.crypto_orders (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid references auth.users not null,
  reference_code   text unique not null,           -- e.g. "CX-391847"
  order_type       text not null,                  -- 'buy' | 'sell' | 'withdraw'
  asset            text not null,                  -- 'BTC' | 'ETH' | 'USDT' | 'USDC'
  network          text,                           -- 'ERC20' | 'TRC20' | 'BTC' | 'ETH' (for withdraw)

  -- Amounts
  amount_crypto    numeric(18,8) not null,
  amount_brl       numeric(12,2),                  -- BRL leg (buy/sell)
  rate_at_request  numeric(18,2),                  -- BRL per 1 unit of asset
  fee_pct          numeric(5,2) default 3.0,
  fee_brl          numeric(12,2),

  -- Withdrawal only
  destination_address text,
  txhash           text,                           -- blockchain tx hash (set when done)

  -- Status
  status           text not null default 'pending',
  failed_reason    text,

  -- Admin
  reviewed_by      text,
  completed_at     timestamptz,
  actual_rate      numeric(18,2),                  -- rate Jayme actually executed at
  actual_amount_crypto numeric(18,8),              -- actual crypto received/sent
  binance_order_id text,                           -- internal ref
  admin_notes      text,

  created_at       timestamptz default now(),
  updated_at       timestamptz default now()
);

CREATE INDEX crypto_orders_user_idx ON public.crypto_orders (user_id);
CREATE INDEX crypto_orders_status_idx ON public.crypto_orders (status);

ALTER TABLE public.crypto_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY crypto_orders_user_select ON public.crypto_orders
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY crypto_orders_user_insert ON public.crypto_orders
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY crypto_orders_admin_all ON public.crypto_orders
  FOR ALL USING (auth.jwt()->>'email' = 'jaymepereiranunes@yahoo.com.br');
```

---

### User flow — Portfolio overview (dashboard.html)

```
[Cripto] nav tab
      │
      ▼
┌─────────────────────────────────────────────┐
│  💼 Portfólio Cripto                         │
│                                             │
│  ₿  BTC    0.00420000   ≈ R$ 2.241,14      │
│  Ξ  ETH    0.05000000   ≈ R$ 897,31        │
│  ◎  USDT   150.000000   ≈ R$ 765,00        │
│  ◈  USDC   0.000000     ≈ R$ 0,00          │
│                                             │
│  Total: ≈ R$ 3.903,45                      │
│  (valores em tempo real via CoinGecko)      │
│                                             │
│  [Comprar ▼]  [Vender ▼]  [Sacar ▼]       │
└─────────────────────────────────────────────┘
```

---

### User flow — Buy (Onramp)

```
STEP 1: Selecionar ativo
  ● BTC  ● ETH  ● USDT (TRC20)  ● USDT (ERC20)  ● USDC (ERC20)

STEP 2: Valor
  Pagar: [R$ 1.000,00 ___________]
  Você recebe: ~0.00187 BTC
  Cotação: 1 BTC = R$ 518.700,00 (CoinGecko, atualizado há 30s)
  Taxa SISBRAPAG (3%): R$ 30,00
  Saldo disponível: R$ 5.120,00  ✅ suficiente

STEP 3: Confirmar
  Debitado do seu saldo BRL: R$ 1.000,00
  Cripto estimada: ~0.00187 BTC
  Taxa: R$ 30,00
  Ref: CX-391847
  [Confirmar compra]

→ Creates crypto_orders row (type=buy)
→ Deducts amount_brl from profiles (or internal balance calc)
→ Telegram notify to admin
→ Email to user ("Compra solicitada")
```

---

### User flow — Sell (Offramp)

```
STEP 1: Selecionar ativo
  ● BTC (saldo: 0.00420) ● ETH (saldo: 0.05) ● USDT (saldo: 150)

STEP 2: Valor
  Vender: [0.00187 BTC ___]  ← or toggle to BRL amount
  Você recebe: ≈ R$ 970,00 BRL
  Cotação: 1 BTC = R$ 518.700,00
  Taxa SISBRAPAG (3%): R$ 29,10
  Recebe líquido: ≈ R$ 940,90

STEP 3: Confirmar
  → Creates crypto_orders row (type=sell)
  → Telegram + admin email
  → User email ("Venda solicitada")
  → Admin credits BRL balance + marks complete
```

---

### User flow — Withdraw (Crypto → External Wallet)

```
STEP 1: Selecionar ativo
  ● BTC ● ETH ● USDT ● USDC

STEP 2: Rede (for USDT/USDC)
  ● TRC20 (Tron) — menor taxa de rede
  ● ERC20 (Ethereum) — maior compatibilidade

STEP 3: Endereço e Valor
  Endereço da carteira: [0x________________]
  ⚠️ Verifique ANTES de confirmar. Endereços errados = perda permanente.
  Valor: [____] USDT  (saldo: 150 USDT)
  Taxa de rede estimada: ~1 USDT (variável)
  Taxa SISBRAPAG (3%): 4.50 USDT
  Você recebe: ~144.50 USDT

STEP 4: Confirmar
  → Creates crypto_orders (type=withdraw, destination_address, network)
  → Telegram + admin email
  → User email ("Saque solicitado")
  → Admin sends from Binance → updates txhash + marks complete
  → User email ("Saque enviado") with txhash link to block explorer
```

---

### Admin flow (admin.html) — Crypto tab

**List view:**
- Pending badge (count of pending orders)
- Table: Ref | User | Type | Asset | Amount | Status | Date

**Order detail modal:**
```
CX-391847  │  João Silva  │  COMPRA BTC
────────────────────────────────────────────
Tipo:        Compra (Buy)
Ativo:       BTC
BRL debitado: R$ 1.000,00
Cripto estimada: ~0.00187 BTC
Cotação solicitação: R$ 518.700,00/BTC
Taxa: R$ 30,00
Saldo BRL pré-ordem: R$ 5.120,00
Submetido: 13/06/2026 15:44
────────────────────────────────────────────
[✅ Concluir]    [❌ Falhou]
```

**"Concluir" modal:**
```
Cotação real executada (BRL/BTC): [518200 ____]
Cripto real creditada:            [0.001874____]
Order ID Binance (opcional):      [____________]
Notas:                            [____________]

→ Updates crypto_holdings (adds to user's balance)
→ Updates crypto_orders status = completed
→ Generates PDF receipt
→ Emails user
```

---

### Telegram notification

```
₿ *Nova Ordem Cripto*

👤 João Silva
📋 COMPRA BTC
💵 BRL: R$ 1.000,00
🔢 Cripto: ~0.00187 BTC
📊 Cotação: R$ 518.700/BTC
🔖 Ref: CX-391847

🔗 admin.sisbrapag.com
```

For withdrawals, also show destination address (truncated) and network.

---

### PDF Receipt — Crypto (jsPDF, same engine)

```
┌─────────────────────────────────────────────────────┐
│  SISBRAPAG              COMPROVANTE DE CRIPTO       │
├─────────────────────────────────────────────────────┤
│  ██████ CONCLUÍDA ██████       Ref: CX-391847       │
│  COMPRA BTC                    13/06/2026 16:30     │
├─────────────────────────────────────────────────────┤
│  CLIENTE: João Silva                                │
│                                                     │
│  OPERAÇÃO: Compra de Bitcoin (BTC)                  │
│  BRL debitado:        R$ 1.000,00                   │
│  Taxa de serviço:     R$ 30,00 (3%)                 │
│  BTC creditado:       0.00187400 BTC                │
│  Cotação executada:   1 BTC = R$ 518.200,00         │
│                                                     │
│  (Para saques) TX Hash: 0xabc...def                 │
│  Rede: TRC20 / Endereço: Txxxx...xxxx               │
├─────────────────────────────────────────────────────┤
│  Cripto é volátil. Não constitui recomendação.      │
│  atendimento@sisbrapag.com │ wa.me/5521987128712    │
└─────────────────────────────────────────────────────┘
```

---

### Baby steps — implementation order (Phase 5)

**Sprint A — Database**
1. SQL migration: `crypto_holdings` table + `crypto_orders` table + RLS → `supabase/crypto_tables.sql`
2. Apply migration + verify
3. Insert one `crypto_holdings` row per existing user (zero balances) — or create on first order

**Sprint B — Dashboard: portfolio view**
4. Add "Cripto" nav item + `#section-crypto` to dashboard.html
5. `loadCryptoPortfolio()`: fetch `crypto_holdings` for user + CoinGecko rates → render portfolio table
6. Show total BRL equivalent
7. Show [Comprar] [Vender] [Sacar] buttons (disabled until active account)

**Sprint C — Dashboard: buy flow**
8. Build buy wizard (asset select → amount → rate preview → confirm)
9. On confirm: insert `crypto_orders` (type=buy) + deduct from balance + Telegram + user email

**Sprint D — Dashboard: sell flow**
10. Build sell wizard (asset select → amount → rate preview → confirm)
11. On confirm: insert `crypto_orders` (type=sell) + Telegram + user email

**Sprint E — Dashboard: withdraw flow**
12. Build withdraw wizard (asset → network select → address → amount → WARNING → confirm)
13. Add address format preview/warning (not full validator — too complex for P1, just display the address back)
14. On confirm: insert `crypto_orders` (type=withdraw) + Telegram + user email

**Sprint F — Dashboard: orders history**
15. "Histórico" subtab: list all user's `crypto_orders` with status badges

**Sprint G — Admin: crypto tab**
16. Add "Cripto" nav to admin.html with badge
17. Build orders table (ref, user, type, asset, amount, status)
18. Build order detail modal

**Sprint H — Admin: actions**
19. "Concluir" modal → update `crypto_holdings` + update `crypto_orders` + generate PDF receipt + email user
20. "Falhou" modal (with reason) → update status + email user

**Sprint I — PDF receipt**
21. Add `buildCryptoReceiptPdf(order, outcome)` to admin.html
22. Wire to completion email via `send-email` edge fn

---

## Shared infrastructure between Phase 4 & 5

| Component | Status | Notes |
|-----------|--------|-------|
| FX rates (Frankfurter) | ✅ Live | Reuse in transfer fee calc |
| Crypto rates (CoinGecko) | ✅ Live | Reuse in crypto buy/sell |
| `send-email` edge fn | ✅ Live | Reuse for all new emails |
| `notify-telegram` edge fn | ✅ Live | Extend with transfer + crypto message types |
| jsPDF receipt engine | ✅ Live (admin.html) | New `buildTransferReceiptPdf` + `buildCryptoReceiptPdf` |
| `set_updated_at` trigger | ✅ Live | Apply to new tables |
| Reference code pattern | ✅ Live (deposits) | TR-XXXXXX for transfers, CX-XXXXXX for crypto |
| Admin modal pattern | ✅ Live | Copy deposit modal pattern |
| Status timeline (user) | ✅ Live (deposits) | Copy deposit status UI |

---

## Recommended build order (combined)

The two phases share so much that the best order is to build them in parallel sprints:

```
Week 1: Both databases (4 tables, migrations, RLS)
Week 2: Phase 4 Sprints B+C (transfer amount + routing forms)
Week 3: Phase 4 Sprints D+E (purpose + submit + status view)
Week 4: Phase 5 Sprints B+C (crypto portfolio + buy flow)
Week 5: Phase 4 Sprint F + Phase 5 Sprints D+E (admin transfers + crypto sell/withdraw)
Week 6: Admin actions + PDF receipts for both
```

Or: finish Phase 4 fully first (it's the core product), then Phase 5.

---

## What's NOT in P1 (save for later)

- **Automatic FX execution** via partner bank API (Wise, Transfero)
- **Real-time PIX collection for transfers** (Inter API — already backlogged)
- **Self-custody wallet generation** (EVM/TRC20/SOL)
- **Auto-match transfer payment** vs Inter extrato
- **TED holiday calendar** (transfers use email confirmation, no TED window)
- **Portfolio charts** (price history, P&L)
- **Limit alerts** (R$35k/month per user for crypto reporting)
- **Staking or yield** products

---

## ✅ Open questions — LOCKED (2026-06-13)

All questions answered. No open questions remain before Sprint A.

---

### 1. Transfer payment leg → **Option A confirmed**
Outbound transfers deduct from the user's existing BRL balance (funded via Deposit).
- If balance insufficient → show error with "Depositar agora" button.
- If user has BRL but needs to transfer in USD/EUR → auto-convert at current rate (or manual: user sees fee + converted amount and confirms). **Design decision: show explicit conversion step in wizard so user approves the rate before submitting.** No silent auto-convert.

---

### 2. Inbound transfer — SISBRAPAG receiving account details (LOCKED)

When a user requests an inbound transfer, show them SISBRAPAG's partner bank details to give to the foreign sender:

```
── Via ACH ────────────────────────────────────────────────────
Receiver:             SISBRAPAG
ACH Routing Number:   026073150
Account Number:       8897802943
Bank:                 Community Federal Savings Bank
                      5 Penn Plz FL 14, New York, NY 10001-1810

── Via WIRE Transfer ──────────────────────────────────────────
Receiver:             SISBRAPAG
Wire Routing Number:  026073008
Account Number:       8897802943
Bank:                 Community Federal Savings Bank
                      5 Penn Plz FL 14, New York, NY 10001-1810

── Via SWIFT ──────────────────────────────────────────────────
Receiver:             SISBRAPAG
SWIFT Code:           CMFGUS33
Account Number:       8897802943
Bank:                 Community Federal Savings Bank
                      5 Penn Plz FL 14, New York, NY 10001-1810
```

**Inbound flow design (updated):**
1. User selects "Receber do exterior"
2. Selects method they'll ask the sender to use (ACH / WIRE / SWIFT)
3. Enters: expected amount + currency, sender name, sender country, purpose code
4. System shows the correct SISBRAPAG receiving account details to share with the sender
5. User submits → creates `transfer_requests` row (direction=inbound)
6. Telegram + admin email: "New inbound transfer expected: USD X from [name]"
7. Admin watches Inter/partner bank for the wire to arrive
8. Admin clicks "Recebido" → enters actual amount received → generates BRL credit + receipt

**UX detail:** Show a "Copiar" button next to each field (account number, routing, SWIFT) and a "Compartilhar dados" button that copies all fields as formatted text for pasting into WhatsApp/email.

---

### 3. Fee structure — LOCKED + new feature: per-user fee tiers

**Default fees:**
| Transfer type | % fee | Fixed fee |
|--------------|-------|-----------|
| USD (ACH/WIRE) | 3% | + $30.00 flat |
| EUR (SEPA/WIRE) | 3% | + €1.00 flat |
| GBP | 3% | + £1.00 flat |
| Crypto (buy/sell/withdraw) | 3% | none |
| Other currencies | 3% | + $1.00 flat (USD equiv) |

**Per-user fee tier override (new feature — admin panel):**
Some users (VIP/corporate) get custom rates set individually by Jayme.

**DB change needed (`profiles` table):**
```sql
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS fee_pct_override  numeric(5,2) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS fee_note          text DEFAULT NULL;
-- NULL means "use platform default (3%)"
-- Non-null overrides the default for this user
-- fee_note: admin memo e.g. "Corporate rate — agreed 2026-06"
```

**Admin UI addition (profiles modal in admin.html):**
```
── Fee Tier ────────────────────────────────────
Taxa padrão da plataforma: 3%
Override para este usuário: [___ %]  (deixe vazio = padrão)
Nota interna: [________________________________]
[Salvar taxa]
```

**Dashboard / wizard logic:**
```js
// When calculating fee for any operation:
const userFeePct = profile.fee_pct_override ?? 3.0;
const feeAmount = amount * (userFeePct / 100);
// Show to user: "Taxa SISBRAPAG (X%): R$ Y"
```

**Fee display in wizard:** Always show the user their specific rate and total cost before they confirm. Never hidden.

---

### 4. USDT networks — Both ERC20 and TRC20 supported

- Both are fully supported in Binance Business.
- User chooses at withdrawal time.
- Default pre-selected: **TRC20** (lower network fee, most clients use it).
- Jayme's personal preference: ERC20 (but this doesn't affect defaults).
- Receipt and Telegram notification show the network used.
- Block explorer links in receipt:
  - ERC20 → `https://etherscan.io/tx/{txhash}`
  - TRC20 → `https://tronscan.org/#/transaction/{txhash}`
  - BTC → `https://blockchain.com/explorer/transactions/btc/{txhash}`
  - ETH (native) → `https://etherscan.io/tx/{txhash}`

---

### 5. Crypto receipt with txhash — Confirmed

**Updated PDF receipt (withdrawals):**
```
┌─────────────────────────────────────────────────────┐
│  SISBRAPAG              COMPROVANTE DE CRIPTO       │
├─────────────────────────────────────────────────────┤
│  ██████ ENVIADO ██████         Ref: CX-391847       │
│  SAQUE USDT (TRC20)            13/06/2026 16:30     │
├─────────────────────────────────────────────────────┤
│  CLIENTE: João Silva                                │
│                                                     │
│  Ativo: USDT (TRC20)                                │
│  Valor enviado: 144.50 USDT                         │
│  Taxa de serviço: 4.50 USDT (3%)                    │
│  Total debitado: 149.00 USDT                        │
│                                                     │
│  Endereço: TXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx         │
│  Rede: TRC20 (Tron)                                 │
│  TX Hash: abc123...def456                           │
│  Verificar: tronscan.org → [hash]                   │
│  Confirmado em: 13/06/2026 16:45                    │
├─────────────────────────────────────────────────────┤
│  Cripto é volátil. Não constitui recomendação.      │
│  atendimento@sisbrapag.com │ wa.me/5521987128712    │
└─────────────────────────────────────────────────────┘
```

For **buy/sell** receipts, txhash is omitted (internal operation, no on-chain tx).

---

## New sprint added: Fee tier admin UI

Between Phase 4 Sprint A (DB) and Sprint B (dashboard), add:

**Sprint 0 (quick, before anything else):**
- `ALTER TABLE profiles` to add `fee_pct_override` + `fee_note`
- Admin modal: add Fee Tier section (input + save)
- Dashboard: load user's effective fee rate at session start → use in all wizards

This is shared by both Phase 4 and Phase 5, so build it first.

---

## Updated DB migration order

```
Sprint 0:   profiles fee columns (ALTER TABLE — 5 min)
Sprint 4-A: transfer_requests table
Sprint 5-A: crypto_holdings + crypto_orders tables
```

All can be in a single `supabase/phase4-5-migrations.sql` file.

---

*All open questions resolved 2026-06-13. Ready to build Sprint 0 → Sprint A.*
