# SISBRAPAG — Product Roadmap & TODO

> Build order is intentional: each phase lays the foundation for the next.
> Last updated: 2026-06-11

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

## Phase 3 — Operations (Admin Panel)
*Give the admin tools to manage users and communicate.*

- [ ] **Admin notes on user profiles** (admin.html)
  - Add a `notes` text field to `public.profiles`
  - In admin modal: textarea to write/save notes per user (e.g. "Spoke on WhatsApp, waiting for CNPJ")
  - _Unlocks:_ CRM-lite functionality without external tool

- [ ] **Internal messaging system** (admin.html + dashboard.html)
  - New Supabase table: `messages` (from, to, body, read, created_at)
  - Admin can drop a message to a specific user (e.g. "We need your company registration doc")
  - User sees a notification badge + inbox in their dashboard
  - Both-way: user can reply
  - _Unlocks:_ replaces ad-hoc WhatsApp back-and-forth; keeps comms inside the platform

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
