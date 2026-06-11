---
name: project-sisbrapag-onboarding
description: "Full spec and current state of the SISBRAPAG onboarding system — magic link auth, Supabase setup, dashboard, and deploy workflow"
metadata: 
  node_type: memory
  type: project
  originSessionId: ff31d6bd-30a7-4af4-94fc-308e9d253955
---

Magic-link onboarding system for sisbrapag.com. Built and deployed 2026-06-10.

**Why:** Needed a frictionless signup flow (no password) to capture leads and collect business profile info.

**How to apply:** When touching onboard.html, dashboard.html, or Supabase config, read this first.

---

## Architecture

- **Static HTML only** — no backend. Supabase JS SDK runs entirely in the browser via CDN.
- **Auth:** Supabase magic link (`signInWithOtp`). No passwords. Free tier.
- **Profile storage:** `user_metadata` via `sb.auth.updateUser({ data: {...} })`.
- **Session persistence:** Supabase handles it via localStorage automatically.

## Files (all at repo root)

| File | URL | Purpose |
|------|-----|---------|
| `onboard.html` | sisbrapag.com/onboard.html | Signup: name + email → magic link |
| `dashboard.html` | sisbrapag.com/dashboard.html | Protected: profile form, services overview |
| `admin.html` | sisbrapag.com/admin.html | Admin only: user list, status toggle, profile view |

## Supabase config

- **Project URL:** `https://iiclntwwutsaoorbncfp.supabase.co`
- **Anon key:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlpY2xudHd3dXRzYW9vcmJuY2ZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEwODAyMTksImV4cCI6MjA5NjY1NjIxOX0.pf-aJ3idjxAyU2LTu9PizMdJ5fHqlQrabf8NqwvkLbI`
- **Magic link redirect:** `https://sisbrapag.com/dashboard.html`
- Supabase Dashboard: https://supabase.com/dashboard/project/iiclntwwutsaoorbncfp

## User flow

1. Visitor clicks "Get Started" on sisbrapag.com → `/onboard.html`
2. Enters name + email → Supabase sends magic link email
3. Clicks link in email → lands on `/dashboard.html` with active session
4. Fills profile form (phone, country, company, primary use) → saved to `user_metadata`
5. Dashboard shows account status (Pending → Active once profile complete)

## Profile fields stored in user_metadata

- `full_name` — set at signup via `signInWithOtp data:`
- `phone`, `country`, `company`, `primary_use` — set on dashboard profile form

## Deploy workflow

- Repo: github.com/jayminho/sisbrapag
- Vercel auto-deploys from `main` (outputDirectory: `.` = repo root)
- **Best deploy method:** `gh` CLI on local machine (authenticated as jayminho via keyring)
  ```bash
  cd /tmp && gh repo clone jayminho/sisbrapag
  # make changes
  git add . && git commit -m "..." && git push
  ```
- github.dev works for text edits but has no terminal and right-click is broken in browser

## Email delivery (Resend + branded template) — completed 2026-06-10

- **SMTP:** Resend (`smtp.resend.com:465`, user `resend`, sender `noreply@sisbrapag.com`, name `SISBRAPAG`)
  - API key: rotated 2026-06-11 (old key `re_FdB6VUSP_*` was exposed on GitHub and revoked). Current key `re_dkm19N7v_*` (Resend name: `sisbrapag-smtp`) saved to Supabase Auth → Emails → SMTP Settings → Password field AND stored as Supabase secret `RESEND_API_KEY` for the edge function.
  - Configured at: Supabase Dashboard → Auth → Emails → SMTP Settings
- **Branded email template:** `email-template-magic-link.html` (repo root, 110 lines)
  - Applied to both "Confirm sign up" AND "Magic link or OTP" templates in Supabase
  - Uses inline CSS, SISBRAPAG colors (#0B1120, #10B981), `{{ .ConfirmationURL }}` variable
- **DNS records added to Namecheap for Resend** (domain: sisbrapag.com):
  - DKIM TXT: `resend._domainkey` → Resend DKIM value
  - SPF TXT: `send` subdomain
  - MX: `send` → `feedback-smtp.sa-east-1.amazonses.com` priority 10
  - Resend domain ID: `366f07a7-6a17-46cf-9bbe-139d8545460c`
- **Status:** Fully working. Tested — branded email delivered, confirm button lands on dashboard. ✅

## Email forwarding (ImprovMX) — completed 2026-06-10

- Adding Resend MX record broke Namecheap's native email forwarding (only one mail mode allowed)
- Fixed with ImprovMX (free tier): forwards `*@sisbrapag.com` → personal inbox
- MX records added to Namecheap Custom MX:
  - `@` → `mx1.improvmx.com` priority 10
  - `@` → `mx2.improvmx.com` priority 20
- Verified via MXToolbox — both records live. hello@sisbrapag.com reaches Jayme's inbox. ✅

## Admin dashboard (admin.html) — completed 2026-06-10

- Auth guard: Supabase login required + email must be `jaymepereiranunes@yahoo.com.br`
- Features: user list table, status toggle (pending ↔ active), stats bar, search, full profile modal
- Supabase RLS policies: `profiles_admin_read` (SELECT all) and `profiles_admin_update` (UPDATE all) — gated on admin email via `auth.jwt()->>'email'`
- Commit: `bb617de`

## public.profiles table — completed 2026-06-10

- Columns: `id` (FK to auth.users), `email`, `full_name`, `phone`, `country`, `company`, `primary_use`, `status` (default `pending`), `created_at`, `notes` (added 2026-06-11)
- Trigger `on_auth_user_created_profile` auto-inserts row on every signup
- `dashboard.html` upserts to this table on every profile save (in addition to `user_metadata`)
- RLS: users can only access their own row; admin can read/update all

## Subdomain routing (completed 2026-06-10)

- `app.sisbrapag.com` → `/dashboard.html` ✅
  - Vercel domain added, CNAME `app` → `66ad730b4ed9b579.vercel-dns-017.com.` (Namecheap)
  - Bug fixed 2026-06-11: vercel.json had `/onboard.html` by mistake — corrected to `/dashboard.html` (commit `ef06892`)
- `admin.sisbrapag.com` → `/admin.html` ✅
  - Vercel domain added, CNAME `admin` → `66ad730b4ed9b579.vercel-dns-017.com.` (Namecheap)
- `sisbrapag.com` (naked/apex) → 308 redirect to `www.sisbrapag.com` ✅
  - Domain in Vercel. Namecheap A record `@` fixed 2026-06-11: was `216.198.79.1`, updated to `76.76.21.21` (Vercel IP)
- `vercel.json` host-based rewrites deployed (commit `07f5b43`, fixed `ef06892`)

## What's left / next steps

- [x] `app.sisbrapag.com` subdomain — DONE 2026-06-10
- [x] `admin.sisbrapag.com` subdomain — DONE 2026-06-10
- [x] Add "Get Started" link from contact section of index.html — DONE 2026-06-10 (commit `fa12bd5`)
- [x] Add DMARC TXT record — DONE 2026-06-10 (Namecheap `_dmarc`, `p=none`, reports to Jayme's Yahoo)
- [x] Wire service activation email — DONE 2026-06-10 (commit `69157ad`, fires on pending → active toggle)
- [x] Admin dashboard (admin.html) — DONE 2026-06-10
- [x] `public.profiles` table created and wired to dashboard — DONE 2026-06-10
- [x] Admin notification when new user registers — DONE 2026-06-10

## Completed (2026-06-11)

- [x] Welcome email post-signup — fires on first profile save, branded, via Resend. Commit `99d9a84`.
- [x] Social proof user count on homepage — live Supabase count in hero. Commit `e1ccae8`.
- [x] Services page — `/services.html` with 4 expanded cards + crypto pricing (3%/3%). Commit `bd95272`.
- [x] Security fix — Resend key rotated, edge function `send-email` deployed, no secrets in code. Commit `af795b3`.
- [x] Admin notes field — `notes` column in `public.profiles`, textarea in admin modal. Commit `deea0e3`.
- [x] Magic link fix — new Resend SMTP key saved to Supabase Auth SMTP settings. 2026-06-11.
- [x] Naked domain fix — Namecheap A record `@` → `76.76.21.21`. 2026-06-11.
- [x] app subdomain fix — vercel.json corrected to dashboard.html. Commit `ef06892`.

## Email architecture (post 2026-06-11)

All transactional emails (activation, welcome) go through `supabase/functions/send-email`:
- Frontend calls `${SUPABASE_URL}/functions/v1/send-email` with anon key
- Edge function reads `RESEND_API_KEY` from Supabase secrets and calls Resend server-side
- No API keys anywhere in frontend code or git history

## See also

- [[project-sisbrapag-site-changes]] — full site change log
