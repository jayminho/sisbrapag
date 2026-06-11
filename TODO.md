# SISBRAPAG — Product Roadmap & TODO

> Build order is intentional: each phase lays the foundation for the next.
> Last updated: 2026-06-11

---

## Phase 1 — Trust & Conversion (Homepage)
*Get visitors to convert. Simple HTML changes, no backend.*

- [ ] **"How it works" section** (index.html)
  - 3-step visual: Sign up → Send docs → Transfer funds
  - Simple icons, short copy, clean layout
  - _Unlocks:_ clearer user expectations → lower drop-off on onboarding

- [ ] **Legal / compliance pages**
  - `terms.html` — Terms of Service
  - `privacy.html` — Privacy Policy
  - Link in footer of index, onboard, dashboard
  - _Unlocks:_ trust for cautious users; required before any transaction flow

- [ ] **Testimonials section** (index.html)
  - Placeholder-ready cards (name, company, quote)
  - Can populate with real quotes as they come in
  - _Unlocks:_ social proof alongside the user count already live

---

## Phase 2 — User Experience (Dashboard)
*Make the dashboard useful for users who are already in.*

- [ ] **Pending user: estimated timeline + status message** (dashboard.html)
  - Show a friendly message when status = pending: e.g. "Typically activated within 1 business day"
  - Triggered automatically by Supabase profile status
  - _Unlocks:_ reduces silence/uncertainty post-signup; fewer "did it work?" messages

- [ ] **Quotation system in dashboard** (dashboard.html)
  - Mirror the FX calculator from index.html inside the dashboard
  - Personalised: show the user's country/currency by default from their profile
  - Save last quote to Supabase for reference
  - _Unlocks:_ user can price their transfer before requesting it → feeds directly into Phase 4

- [ ] **Document upload → admin email notification**
  - Trigger edge function `send-email` when a user uploads a document
  - Email to jaymepereiranunes@yahoo.com.br: user name, doc type, timestamp
  - _Unlocks:_ ops awareness; currently uploads happen silently

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
