---
name: project-sisbrapag-site-changes
description: Log of all changes made to the sisbrapag.com website (github.com/jayminho/sisbrapag)
metadata: 
  node_type: memory
  type: project
  originSessionId: 1a0a8073-0ca1-46cf-aac7-aac0b30d7bf5
---

Running log of changes to sisbrapag.com. Repo: github.com/jayminho/sisbrapag. Vercel auto-deploys from `main`. Deploy via `gh` CLI (not github.dev — no terminal there).

**How to apply:** Before making any site change, check this log to understand current state. After any change, add an entry here.

---

## Up next (start here next session)

- Test EUR (IBAN/BIC) and GBP (sort code) outbound transfer paths end-to-end
- Test crypto withdraw flow end-to-end
- **Phase 3 Item #2:** Internal messaging system (`messages` table in Supabase, inbox in dashboard, both-way admin ↔ user)

---

### 2026-06-15 — BRL exchange rate fix: BCB provider (commit `4310dce`)

- **Problem:** Frankfurter API was returning stale BRL rates (3 days behind) — ECB derives BRL as a cross-rate and it lagged vs. Google/XE/Morningstar.
- **Fix:** Both `index.html` (`fetchFiatRates`) and `dashboard.html` (`cvFetchFiat`) now fire two parallel Frankfurter calls when BRL is in play:
  1. Main call (ECB) for EUR, GBP, and all other fiat pairs
  2. `&provider=BCB` call (Banco Central do Brasil) for USD→BRL, then cross-derived for other bases via `BRL = BCB_usdBrl × rates.USD`
- **Result:** Rate is now same-day from BCB (5.0498 vs stale 5.1073). EUR/GBP unaffected — ECB is still authoritative for those.
- **Note:** EUR/GBP rates are fine via ECB — they're major currencies ECB publishes natively. Lag was BRL-specific.

### 2026-06-15 — "Repetir transferência" feature (commits from previous session)

- **What:** Repeat button appears on outbound transfer history rows when `routing` + `recipient_name` are present. Clicking it pre-fills the entire transfer wizard: currency, recipient name, country, all routing fields (IBAN/BIC, sort code/account, ACH routing/account/type), bank name, address, and purpose code.
- **Key pieces:**
  - `_trRepeatStore` — module-level cache of repeatable transfer data, keyed by transfer ID (avoids JSON in onclick attrs)
  - `trRepeat(id)` — sets `trState._prefill`, calls `trPickDirection('outbound')`, shows banner ("Dados de TRF-xxx pré-preenchidos · Informe o valor desejado")
  - `trApplyPrefill()` — called at end of `trRenderRecipientForm()`, fills routing fields and triggers live validation; `_recipientApplied` flag prevents clobbering on back-navigation
  - `trGoToDirection()` — new back button function that also clears prefill + banner
  - Supabase history query expanded to include `recipient_name, recipient_country, routing, purpose_code`
- **UX:** User sees "Repetir" link on eligible rows, hits it, sees amount step with green banner, fills amount, all recipient fields pre-populated on the next step.

### 2026-06-15 — Removed preset amount buttons from converters (previous session)

- **`index.html`:** Removed the "Quick presets" div block with 5 buttons (100, 500, 1,000, 5,000, 0.01 BTC) and the `.preset-btn` JS event listener.
- **`dashboard.html`:** Removed the preset amounts div (100, 500, 1,000, 5,000, 10,000 / 0.01 BTC) and the `.cv-preset` event listener from the converter widget.
- **Why:** Design philosophy — radical simplicity. Static shortcuts add visual clutter for no real conversion benefit.

### 2026-06-11 — Bug fixes: magic link + naked domain + vercel.json (commits `deea0e3`, `ef06892`)

- **Magic link fixed:** Resend API key rotated (old `re_FdB6VUSP_*` was revoked and exposed on GitHub). New key `re_dkm19N7v_*` saved to Supabase Auth → Emails → SMTP Settings (password field). Magic links on `onboard.html` now work. ✅
- **Naked domain fixed:** Namecheap A record `@` was pointing to wrong IP `216.198.79.1` — updated to `76.76.21.21` (Vercel). `sisbrapag.com` now resolves and 308-redirects to `www.sisbrapag.com`. ✅
- **`app` subdomain fixed (commit `ef06892`):** `vercel.json` had `app.sisbrapag.com` pointing to `/onboard.html` instead of `/dashboard.html`. Fixed and deployed. ✅

### 2026-06-11 — Phase 3 Item #1: Admin notes field (commit `deea0e3`)

- **Supabase:** `ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS notes text` — added `notes` column. Existing `profiles_admin_update` RLS policy covers it automatically.
- **admin.html:** Profile modal now shows a "Admin Notes" textarea (populated from `u.notes`). "Save notes" button calls `sb.from('profiles').update({ notes })` and shows "Saved ✓" feedback. `modalUserId` tracked as module-level variable.

### 2026-06-11 — Phase 1 & 2 complete + bug fixes (commit `7cca8ed`)

**Phase 1 — Trust & Conversion:**
- `index.html`: "How it works" 3-step section (id="how-it-works") added between Services and Converter
- `index.html`: Testimonials section with 3 placeholder cards (Ricardo M., Ana P., Carlos F.)
- `index.html`: Nav now includes "How it works" anchor link
- `index.html`: Footer updated with Terms and Privacy links
- `terms.html`: Full Terms of Service (LGPD, Brazilian law, Rio de Janeiro courts)
- `privacy.html`: Full LGPD-compliant Privacy Policy (AWS sa-east-1, Resend as processor)

**Phase 2 — Dashboard UX:**
- `dashboard.html`: Pending timeline card (3-step progress: profile complete → under review → activated); reads real `public.profiles.status`
- `dashboard.html`: Converter tab with live Frankfurter (fiat) + CoinGecko (crypto) rates; FROM pre-filled from user's country; preset amounts
- `dashboard.html`: Admin email notification on document upload (via `send-email` edge function)
- `onboard.html`: Footer updated with Terms/Privacy links + dynamic year

**Bug fixes (same commit):**
- `dashboard.html`: `loadDocuments()` now called when navigating to Documents section (was never loading on first visit)
- `dashboard.html`: Admin doc upload email `to` field fixed to array (Resend API requirement)
- `dashboard.html`: Converter sidebar icon changed to `fa-calculator` (was same as Services icon)
- `dashboard.html`: Terms/Privacy links added to sidebar bottom

### 2026-06-11 — Documents upload in dashboard

- **Supabase Storage:** `documents` bucket (private, 10 MB limit, PDF/JPG/PNG only). RLS: users can only read/write their own folder (`{user_id}/`).
- **dashboard.html:** Documents section fully wired. Upload card (type selector + file picker → `uploadDocument()`), uploaded files list (`loadDocuments()`), download via signed URL (60s), delete with confirm dialog.
- **Path scheme:** `{user_id}/{doc_type}_{timestamp}.{ext}` — isolates per user, encodes type in filename.
- **Commit:** `4a617bf` on `main`.

### 2026-06-11 — Supabase page view analytics

- **Table:** `public.page_views` (id, page, referrer, user_agent, created_at). RLS: anon INSERT allowed, admin-only SELECT.
- **Tracking snippet:** Added to `index.html`, `services.html`, `onboard.html` — fires on load via Supabase REST API (anon key, fire-and-forget).
- **Admin panel:** New "Page Views — Last 30 Days" section in `admin.html` — bar chart by page + total count. Uses existing Supabase client.
- **Commit:** `8ad3acb` on `main`.

### 2026-06-11 — Services page anchors from homepage cards

- **What:** Each homepage service card (`div` → `a`) now links to its anchor on `/services.html`: `#remittances`, `#import-export`, `#crypto`. Hover border matches card accent color.
- **Commit:** `bd5ec99` on `main`.

### 2026-06-11 — Working contact form on homepage

- **What:** Replaced static contact section in `index.html` with a two-column layout. Left: heading + Get Started / email / WhatsApp buttons. Right: name + email + message form.
- **How:** Calls `send-email` edge function → Resend → `hello@sisbrapag.com`. Spinner on submit, inline success/error feedback.
- **Commit:** `69b4130` on `main` (push from local machine).

---

## Change log

### 2026-06-11 — Security fix: Resend API key rotation + edge function
- **Issue:** Resend API key `re_FdB6VUSP_*` was hardcoded in `admin.html` and `dashboard.html` and pushed to GitHub. GitGuardian detected and alerted immediately.
- **Fix:** Revoked old key. Created new key stored as Supabase secret `RESEND_API_KEY` (never in code).
- **Supabase Edge Function:** Created `supabase/functions/send-email/index.ts` — all email sending now happens server-side. Frontend calls `/functions/v1/send-email` with anon key only.
- **Updated:** `admin.html` (activation email) and `dashboard.html` (welcome email) — both now call edge function instead of Resend directly.
- **Deployed:** `npx supabase functions deploy send-email --no-verify-jwt`. Tested via curl — confirmed working. ✅
- **Commit:** `af795b3` on `main`.

### 2026-06-11 — Services page + social proof + welcome email
- **Welcome email (dashboard.html):** Fires branded "You're all set" email via Resend on the first time a user completes their profile (detected by checking if `country` was empty before save). Non-blocking, silent fail. Commit `99d9a84`.
- **Social proof user count (index.html):** On page load, fetches `public.profiles` count from Supabase REST API and injects it into the hero — e.g. "Join 3 businesses already on SISBRAPAG". Hidden if 0 users or fetch fails. Commit `e1ccae8`.
- **Services page (services.html):** Built full `/services.html` with 4 expanded service cards (Remittances, Import/Export, Crypto Settlement, FX Exchange). Crypto pricing shown explicitly: 3% onramp / 3% offramp. Other services: "Contact for pricing" → WhatsApp. Dark CTA strip at bottom. Homepage "Talk to the team →" updated to "See all services →" linking to new page. Commit `bd95272`.

---

### 2026-06-10 — Subdomain routing via vercel.json + Namecheap CNAMEs
- **What:** Added host-based rewrites in `vercel.json` so subdomains route to specific pages.
  - `app.sisbrapag.com/` → `/dashboard.html`
  - `admin.sisbrapag.com/` → `/admin.html`
- **Vercel:** Both domains added to sisbrapag project (Production environment).
- **Namecheap:** CNAME records `app` and `admin` both → `66ad730b4ed9b579.vercel-dns-017.com.`
- **Commit:** `07f5b43` on `main`.

### 2026-06-10 — Service activation email (admin.html)
- **What:** When admin toggles a user from Pending → Active, an automated branded email is sent to that user via Resend API (called directly from browser, no backend needed).
- **Email:** From `noreply@sisbrapag.com`, subject "Your SISBRAPAG account is now active", includes first name, CTA "Go to Dashboard →", WhatsApp link in footer.
- **Logic:** Fires only on pending → active (not on active → pending). Non-blocking — runs in background, won't disrupt toggle if it fails.
- **Commit:** `69157ad` on `main`.

### 2026-06-10 — DMARC TXT record added (Namecheap)
- **What:** Added `_dmarc` TXT record: `v=DMARC1; p=none; rua=mailto:jaymepereiranunes@yahoo.com.br`
- **Why:** Improves email deliverability; monitor-only mode (`p=none`) — no risk, just starts collecting reports.
- **Where:** Namecheap Advanced DNS → HOST RECORDS.

### 2026-06-10 — "Get Started" CTA added to contact section (index.html)
- **What:** Added primary green "Get Started" button linking to `/onboard.html` in the contact/CTA section. Email and WhatsApp buttons remain as secondary outlined buttons.
- **Commit:** `fa12bd5` on `main`.

### 2026-06-10 — Dashboard UI fixes (profile banner + services state)
- **What:** Fixed stale UI state after profile save. Banner now hides immediately on save. Services section now dynamic — shows lock screen if profile incomplete, or all 4 service cards with "Pending activation" badges if complete.
- **Root cause:** `getUser()` after `updateUser()` returned stale JWT; fixed by patching `currentUser.user_metadata` in-memory immediately, then refreshing in background.
- **Commits:** `261b0ce` on `main`.

### 2026-06-10 — Admin dashboard (admin.html)
- **What:** Built `admin.html` — protected admin page at sisbrapag.com/admin.html.
  - Auth guard: requires Supabase login + email = jaymepereiranunes@yahoo.com.br
  - User list table: name, email, country, company, primary use, join date, status
  - Status toggle: click badge to flip any user pending ↔ active (updates public.profiles)
  - Stats bar: total / active / pending counts
  - Live search filter by name/email/company
  - Click any row → full profile modal
- **Supabase:** Added RLS policies `profiles_admin_read` and `profiles_admin_update` — admin email can read/update all rows.
- **Commit:** `bb617de` on `main`.

### 2026-06-10 — profiles table + dashboard wired to Supabase
- **What:** Created `public.profiles` table in Supabase (id, email, full_name, phone, country, company, primary_use, status, created_at). Trigger `on_auth_user_created_profile` auto-inserts row on signup. RLS enabled.
- **dashboard.html:** On profile save, upserts to `public.profiles` in addition to `user_metadata`. Commit `ec0014b`.
- **Why:** Enables admin queries and future email campaigns without raw auth.users access.

### 2026-06-10 — Admin notification on new signup
- **What:** PostgreSQL trigger `notify_admin_on_signup` on `auth.users` INSERT → calls `net.http_post` → Resend API → email to jaymepereiranunes@yahoo.com.br.
- **Details:** `pg_net` extension enabled via SQL editor. Trigger function uses `SECURITY DEFINER`, fires async HTTP POST to `https://api.resend.com/emails` with user name + email + timestamp. Saved as "Notify Admin on New Signup" query in Supabase SQL editor.
- **Tested:** Fake INSERT fired trigger, branded email delivered to Jayme's Yahoo inbox. ✅

### 2026-06-10 — Branded transactional email + ImprovMX forwarding
- **What:** Branded the Supabase magic link email with SISBRAPAG visual identity.
  - `email-template-magic-link.html` (repo root) — 110-line inline-CSS email template. SISBRAPAG logo header, green top bar, "Welcome to SISBRAPAG", CTA button, fallback link, footer.
  - Applied to both "Confirm sign up" AND "Magic link or OTP" templates in Supabase Auth → Emails.
- **DNS (Namecheap):** DKIM TXT (`resend._domainkey`), SPF TXT (`send` subdomain), MX (`send` → `feedback-smtp.sa-east-1.amazonses.com` priority 10).
- **ImprovMX:** `mx1/mx2.improvmx.com` MX records added to restore `*@sisbrapag.com` → personal inbox forwarding (Namecheap Custom MX mode had broken native email redirect).
- **Tested:** Full flow working — onboard → branded email → confirm → dashboard ✅
- See also: [[project-sisbrapag-onboarding]]

### 2026-06-10 — Onboarding system + Get Started CTA
- **What:** Built and deployed a full magic-link onboarding system.
  - `onboard.html` — signup page (name + email, sends Supabase magic link, no password)
  - `dashboard.html` — protected dashboard (auth guard, profile form, services overview)
  - `index.html` — added "Get Started" button in nav + hero CTA linking to `/onboard.html`
- **Auth:** Supabase project `iiclntwwutsaoorbncfp.supabase.co` (free tier). Magic link redirects to `sisbrapag.com/dashboard.html`. Profile saved to `user_metadata` via `sb.auth.updateUser()`.
- **Deploy method:** `gh` CLI — cloned to `/tmp/sisbrapag`, `git mv` to fix paths, committed and pushed. Desktop Commander / `gh auth` used (no PAT needed, authenticated as jayminho via keyring).
- **Commits:** `4f816cb` (move files to root), `b9b3a5b` (Get Started CTA).
- **Status:** Live at sisbrapag.com/onboard.html and sisbrapag.com/dashboard.html. ✅
- See also: [[project-sisbrapag-onboarding]]

### 2026-06-09 — WhatsApp contact number updated
- **What:** Updated WhatsApp button link from `wa.me/55` to `wa.me/5521987128712` in `index.html` line 356.
- **Commit:** "Update WhatsApp contact number to 5521987128712" on `main`.

### 2026-06-09 (earlier session) — Fiat FX converter fixed
- **What:** Switched `fetchFiatRates` from exchangerate-api.com to Frankfurter API (api.frankfurter.dev) as primary source, with exchangerate-api as fallback and hardcoded approximates as last resort.
- **Why:** exchangerate-api was causing delayed rates; CoinGecko (crypto side) worked fine.
- **Commit:** `fbb7dfd` on `main`.
- See also: [[project-sisbrapag-fiat-fx-fix]] for full detail.
