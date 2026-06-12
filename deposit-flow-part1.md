# SISBRAPAG — Manual Deposit Flow (Part One)

**Status:** Design spec — "good old days" TED + PIX manual deposit
**Date:** 2026-06-12
**Scope:** Funding flow only. Withdrawals, fees, and limits are later parts.

---

## 1. The two deposit options

Both are shown on the funding menu with the time expectation **stated up front**, before the user commits:

| Option | Label shown to user | Availability | Promise |
|---|---|---|---|
| **TED** | Transferência bancária (TED) | **Weekdays 09h–16h Brasília only** | "Creditado em até 60 minutos, em dias úteis das 09h às 16h." |
| **PIX** | PIX (chave ou QR Code) | **24/7** | "Creditado em até 60 minutos." |

**Availability rules (decided):**
- **PIX is 24/7.** Always selectable.
- **TED is weekdays 09h–16h Brasília time only.** Outside that window (nights, weekends, holidays) the TED option is **greyed out / disabled**, with a short disclaimer: *"TED disponível somente em dias úteis das 09h às 16h (horário de Brasília). Use PIX para depositar agora."*
- This needs a Brasília-timezone check + a Brazilian holiday calendar (ANBIMA/national holidays) to grey out holidays too.

Note: even PIX is **manual-review** in Part One — same 60-min review window, same dashboard confirm. The auto-credit upgrade comes later (Part 2, when statement/extrato matching is wired). For now the user experience is identical for both; only the payment details screen differs.

---

## 2. The receiving account (from Inter)

```
Banco:    INTER - 077
Titular:  SISTEMA BRASIL PAGAMENTOS DIGITAIS
CNPJ:     32.742.398/0001-28
Agência:  0001
Conta:    5476239-1
PIX (chave aleatória): a13f5b08-4fbf-4613-bfa2-7cd518388dd6
QR Code:  [gerado/estático — anexar imagem]
```

---

## 3. User flow

1. **Funding menu** → user picks TED or PIX (both show the 60-min business-hours promise).
2. **Amount screen** → user enters the amount they intend to deposit.
3. **Payment details screen** → app shows:
   - **TED:** full bank info above + a **unique reference code** for this deposit.
   - **PIX:** the PIX key + QR Code + the **unique reference code**.
4. **Confirm screen** → user clicks **"Já transferi"** → goes to receipt upload.
5. **Receipt upload** → user attaches the receipt image/PDF and clicks **OK**.
6. Deposit enters **under review** → you verify at the bank → click **OK** in your dashboard → balance credited.

### The 60-minute timer (critical)
- The deposit record is created at **step 3** (when payment details are shown) and starts a **60-minute clock**.
- If the user **does not upload a receipt within 60 minutes** → status auto-moves to **`expired`**, the user gets a "deposit cancelled" email, and the reference code is retired.
- The timer is about giving slow payers room — once a receipt is uploaded, the clock stops (it's now your job to review, not theirs).

---

## 4. Deposit states

```
created ──(payment details shown, 60-min clock starts)
   │
   ├── user uploads receipt ──► pending_review
   │                                │
   │                                ├── you confirm at bank ──► credited  ✅
   │                                └── you reject ──────────► rejected   ❌
   │
   └── 60 min, no receipt ───────► expired                              ⏰
```

Five terminal-ish states the user sees on their dashboard:
`created` → `pending_review` → `credited` / `rejected` / `expired`

(Your earlier "pending → under review → credited" maps to `created` → `pending_review` → `credited`.)

---

## 5. Your manual review checklist (the part that protects you)

When a deposit hits `pending_review`, the uploaded receipt is **only a claim**. You confirm against the **real bank account**, checking:

1. **Did the money actually land?** Match against the Inter statement, not the receipt image (receipts get photoshopped).
2. **Right amount?** Matches the amount the user entered.
3. **Right reference?** The unique code appears in the transfer (where the rail allows a message).
4. **⚠️ Same name? (KYC-critical)** The sender's name/CPF must match the account holder. **No third-party deposits.** If it came from someone else's name → **reject**, don't credit.

Only when all pass → click **OK** → `credited` → balance updates on their dashboard.

---

## 6. Emails at every stage (the user is informed end-to-end)

| Trigger | Email to user |
|---|---|
| Deposit created (step 3) | "Seu depósito de R$X foi iniciado. Você tem 60 minutos para concluir a transferência e enviar o comprovante." |
| Receipt uploaded | "Recebemos seu comprovante. Estamos verificando — crédito em até 60 min (horário comercial)." |
| Credited | "Seu depósito de R$X foi confirmado e seu saldo já está disponível." |
| Rejected | "Não conseguimos confirmar seu depósito. Motivo: [name mismatch / não localizado / valor divergente]." |
| Expired (no receipt in 60 min) | "Seu depósito foi cancelado por falta de confirmação. É só iniciar um novo quando quiser." |

---

## 7. Data model (designed to upgrade to auto-matching)

```
deposits
  id                uuid pk
  user_id           uuid fk
  method            enum('ted','pix')
  amount            numeric(14,2)
  reference_code    text unique        -- the key to future auto-reconciliation
  status            enum('created','pending_review','credited','rejected','expired')
  receipt_url       text null
  expires_at        timestamptz        -- created_at + 60 min
  reviewed_by       uuid null          -- you (admin)
  reviewed_at       timestamptz null
  reject_reason     text null
  sender_name       text null          -- captured at review, for the name-match audit trail
  created_at        timestamptz
  updated_at        timestamptz
```

**Why `reference_code` + `amount` matter now:** in Part 2, when you pull the Inter extrato (statement) automatically, you match an incoming transfer to an open deposit by `amount` + `reference_code`. That flips manual review into one-click (or auto) confirm **without changing this schema**. Build it in from day one.

---

## 8. What's deferred (Part 2 backlog)

**Build (the actual system — Part 1 above is design only):**
- Screens: funding menu → amount → payment details (TED/PIX) → receipt upload → status.
- Supabase `deposits` table (schema in §7) + RLS.
- 60-min expiry job (cron/edge function) → auto-`expired` + email.
- Admin confirm/reject dashboard with the canned rejection reasons.
- Branded PDF receipt generation wired to `credited` + `rejected` events.
- TED availability gate: Brasília-timezone check **+ Brazilian holiday calendar** to grey out nights/weekends/holidays.

**Instant approval notification — Telegram bot (recommended):**
- On `pending_review`, fire one HTTP POST to the Telegram Bot API → message hits your phone with amount, customer name, reference code, receipt link.
- Add **inline "✅ Creditar / ❌ Recusar" buttons** in the message so you can approve/reject from your phone without opening the dashboard — you just check Inter and tap.
- Free, instant, no per-message cost, trivial API. Beats WhatsApp (needs Meta business verification + approved templates), SMS (paid, no buttons), and email (slow, easy to miss).
- Stretch: the reject button opens a quick reason picker (same canned reasons).

**Later / nice-to-have:**
- Inter statement/extrato auto-matching → semi/fully-automatic credit (match by `reference_code` + `amount`).
- Deposit limits, min/max amounts, fees.
- Daily reconciliation report (deposits vs. bank statement).
- Withdrawals.
- Real PIX cash-in API (when Inter manager / crypto-friendly bank comes through).

---

## Decisions locked (was: open questions)

1. **Availability:** TED = weekdays 09h–16h Brasília only (greyed out otherwise, with disclaimer). PIX = 24/7.
2. **Holidays/weekends:** TED disabled; the timezone + holiday check drives the grey-out.
3. **Reference code:** short **numeric** (easy to type into a TED message field).
4. **One open deposit per user at a time.** If they try to open a second, block it and explain: they must cancel, let it expire, or complete the open one first.

## Rejection — premade reasons (dashboard dropdown)

When you reject in your dashboard, pick a canned reason (drives the email + the PDF receipt):
- `Valor divergente` — amount received ≠ amount declared.
- `Nome do depositante diverge do cadastro` — sender name/CPF ≠ account holder (third-party).
- `Depósito não localizado` — nothing matching landed in the account.
- `Comprovante inválido / ilegível` — receipt can't be verified.

## Standard PDF receipt (new standard, every outcome)

Every **credited** AND **rejected** deposit generates a clean branded **PDF receipt** — this is the SISBRAPAG standard going forward. Uses the visual identity (S-leaf logo, navy `#0B1120` + emerald `#10B981`, Space Grotesk / Inter). Template: `receipt-template.html` → render to PDF per deposit. Two variants:
- **Comprovante de Depósito — Creditado** (green accent, ✓).
- **Comprovante de Depósito — Recusado** (red accent, ✕, shows rejection reason).
```
