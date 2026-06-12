# SISBRAPAG — Product Roadmap & TODO

> Build order is intentional: each phase lays the foundation for the next.
> Last updated: 2026-06-12 (evening)

## ▶ START HERE NEXT SESSION — Deposit Flow Part 2 (continued)
Deposit Part 2 core is LIVE (user screens + admin confirm/reject + deposits table + receipts bucket). Remaining, in order:
1. **Branded PDF receipt** on credit/reject (attach the comprovante from `receipt-template.html`) — START HERE.
2. **60-min expiry edge function** (server-side, replaces client-side fallback).
3. **Telegram approval bot** (instant phone notify on pending_review + inline ✅/❌).
4. Later: Inter extrato auto-matching, deposit limits, reconciliation report.
Also done today: admin email+password login + subdomain routing fix (admin/app roots).


---

## Phase 1 — Trust & Conversion (Homepage) ✅
*Completed 2026-06-11*

- [x] **"How it works" section** (index.html) — 3-step visual, desktop connector line, CTA
- [x] **Legal / compliance pages** — `terms.html` + `privacy.html`, linked in index/onboard/dashboard
- [x] **Testimonials section** (index.html) — 3 placeholder cards with star ratings
- [x] **Nav anchor links** — "How it works" added to homepage nav

---

## Phase 2 — User Experience (Dashboard) ✅
*Completed 2026-06-11*

- [x] **Pending user: estimated timeline + status message** (dashboard.html) — reads real `profiles.status`, shows 3-step progress card
- [x] **FX Converter in dashboard** — Converter tab with live Frankfurter + CoinGecko rates, country-prefilled FROM, preset amounts
- [x] **Document upload → admin email notification** — fires via `send-email` edge function on upload, includes user/doc/timestamp + admin link
- [x] **loadDocuments wired to nav** — documents list refreshes automatically when Documents section is opened

---

## Phase 3 — Operations (Admin Panel) ✅
*Completed 2026-06-11*

- [x] **Admin notes on user profiles** (admin.html) — `notes` column + textarea in admin modal
- [x] **Internal messaging system** (admin.html + dashboard.html) — `messages` table, two-way chat, unread badges, email on reply

---

## Phase 3.5 — Manual Deposit Flow ("good old days" TED + PIX)
*Interim funding system while PIX cash-in API is blocked (Inter creds pending). Spec complete 2026-06-12 → see `deposit-flow-part1.md`.*

**Part 1 — Design ✅ (2026-06-12, not built)**
- [x] Full flow spec: menu → amount → payment details → receipt upload → manual review
- [x] States: created → pending_review → credited / rejected / expired
- [x] Decisions: TED weekdays 09–16h BRT only / PIX 24/7; 60-min timer; one open deposit/user; numeric ref code
- [x] Review checklist (money landed, amount, ref, **sender name = holder, no third-party**)
- [x] Email at every stage + canned rejection reasons
- [x] Data model (`deposits`, upgrade-ready for auto-matching)
- [x] Standard branded PDF receipt (`receipt-template.html` + samples)

**Part 2 — Build**
- [x] Screens (funding menu, amount, payment details TED/PIX+QR, receipt upload, status) — dashboard.html
- [x] Supabase `deposits` table + RLS (`supabase/deposits_table.sql`)
- [x] `receipts` storage bucket + RLS (`supabase/receipts_bucket.sql`)
- [x] Admin confirm/reject dashboard (canned reasons, receipt view) — admin.html
- [x] TED availability gate: Brasília TZ (weekdays 09–16h) — _holiday calendar still TODO_
- [x] User + admin emails at each stage
- [ ] **PDF receipt generation** wired to credited/rejected ← NEXT
- [ ] 60-min expiry job (cron/edge fn) → auto-expire + email (currently client-side fallback only)
- [ ] TED holiday calendar (greys out national/ANBIMA holidays)
- [ ] **Telegram approval bot** — instant phone notification on pending_review w/ inline ✅ Creditar / ❌ Recusar buttons
- [ ] _Later:_ Inter extrato auto-matching (ref_code + amount), limits, reconciliation report

**Infra fixes (2026-06-12 eve)**
- [x] Admin email+password login (admin.html) — fixes magic-link friction on admin subdomain
- [x] Subdomain routing fix — vercel.json rewrites → redirects (admin/app roots now resolve)

---

## Phase 4 — Transactions
*The actual product. Builds directly on Phase 2 (quotation) and Phase 3 (messaging).*

- [ ] **Transfer request form** (dashboard.html)
  - User fills: amount, source currency, destination currency, recipient bank details
  - Pre-populated with their last quote
  - Submits → stored in new `transfer_requests` Supabase table
  - Admin gets email notification + sees it in admin panel

- [ ] **PIX / QR code payment initiation**
  - After transfer request submitted, generate a PIX QR code for the BRL leg
  - User pays via PIX from their bank app → funds received → admin processes FX leg
  - Research: Gerencianet / Asaas / Pagar.me for PIX QR generation API
  - _Note:_ This is the biggest build — requires a PIX provider integration

- [ ] **Transfer status tracking** (dashboard.html)
  - List of user's transfer requests with status (Requested → In Progress → Completed)
  - Admin can update status from admin panel
  - User gets email notification on status change (reuse edge function)

---

## Phase 5 — Growth
*Once the product works, grow it.*

- [ ] **Blog / insights section**
  - Static HTML pages targeting SEO: "como enviar dinheiro do Brasil para o exterior", etc.
  - Simple article template, no CMS needed initially
  - Link from homepage nav

- [ ] **Referral flow**
  - "Invite a colleague" button in dashboard
  - Pre-filled email with referral link (`?ref=USER_ID`)
  - Track referral source in `public.profiles.referred_by`

---

## Completed ✅
*(moved here once done)*

- [x] Magic link onboarding (onboard.html + dashboard.html)
- [x] Admin panel (admin.html)
- [x] Subdomain routing (app / admin)
- [x] Branded transactional emails (Resend + edge function)
- [x] Document upload in dashboard (Supabase Storage)
- [x] Page view analytics
- [x] Services page
- [x] Contact form (edge function)
- [x] Social proof user count on homepage
- [x] Security fix (Resend key rotation + edge function)
- [x] FX calculator on homepage
- [x] WhatsApp contact button
