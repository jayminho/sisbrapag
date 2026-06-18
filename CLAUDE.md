# SISBRAPAG — Project Instructions

## ⚠️ ALWAYS DEPLOY, NEVER LEAVE CHANGES LOCAL-ONLY

This is the #1 rule for this project. A code change is **not done** until it is
live on the production site. Editing a file in the local folder changes nothing
that the user can see — the live site (`www.sisbrapag.com`) serves the *deployed*
version, not the local file.

**After making ANY code change, you MUST deploy it.** Do not end your turn saying
"fixed" until the change is committed, pushed, and verified live. If you cannot
deploy for some reason, say so explicitly and loudly — do not imply it's live.

---

## 🎯 Source of truth — services, refs & IDs

> All verified live on 2026-06-18. The Supabase account has **three** projects —
> always use the `sisbrapag` ref below, never the others (`xowxow` /
> `jayminho's Project` are unrelated and must not be touched).

| Service | Identifier | Notes |
|---------|-----------|-------|
| **Production site** | `https://www.sisbrapag.com` | Bare `sisbrapag.com` 308-redirects to `www`. Always test/verify the `www` URL. |
| **App subdomain** | `https://app.sisbrapag.com` → `/dashboard.html` | per `vercel.json` redirect |
| **Admin subdomain** | `https://admin.sisbrapag.com` → `/admin.html` | per `vercel.json` redirect |
| **GitHub repo** | `https://github.com/jayminho/sisbrapag.git` | branch `main` |
| **Vercel** | project connected to the GitHub repo above | auto-deploys on push to `main`; no manual step |
| **Supabase project** | name `sisbrapag` · ref **`iiclntwwutsaoorbncfp`** | region `sa-east-1`, ACTIVE_HEALTHY |
| **Supabase URL** | `https://iiclntwwutsaoorbncfp.supabase.co` | wired into the frontend |
| **Supabase org** | `ygtgetydshlyycvgimsh` | |

**Supabase edge functions** (all deployed to ref `iiclntwwutsaoorbncfp`, in `supabase/functions/`):

| Function | verify_jwt | Purpose |
|----------|-----------|---------|
| `send-email` | false | outbound email |
| `expire-deposits` | false | deposit expiry job |
| `notify-telegram` | false | Telegram notifications |
| `execute-swap` | true | multi-currency Lock In swap (requires auth) |

---

## Integrations

### Email — Resend
- Provider: **Resend** (`https://api.resend.com/emails`), called by the `send-email` edge function.
- Default sender: **`SISBRAPAG <noreply@sisbrapag.com>`** (override per-call with a `from` field).
- Secret (Supabase env): **`RESEND_API_KEY`** — value lives in Supabase function secrets, not in the repo.
- Payload fields: `to, subject, html, from, attachments, replyTo`.

### Telegram — activity notifications
- Bot: **@sisbrapagbot** (id `8722822452`), via the `notify-telegram` edge function → `api.telegram.org/bot<token>/sendMessage`.
- Secrets (Supabase env): **`TELEGRAM_BOT_TOKEN`**, **`TELEGRAM_CHAT_ID`** — values in function secrets, not the repo.
- Sends alerts for activities like new signups / deposits.

### Cron jobs (pg_cron, in the Supabase DB)
| Job | Schedule | What it does |
|-----|----------|--------------|
| `expire-deposits-5min` | `*/5 * * * *` (every 5 min) | HTTP POST → `expire-deposits` edge function to expire stale deposits |

To inspect/change cron: `select * from cron.job;` (and `cron.schedule(...)` / `cron.unschedule(...)`).

---

## Data model — `public` schema (Supabase)

All tables have **RLS enabled**. Key tables:

| Table | Purpose | Notable columns |
|-------|---------|-----------------|
| `profiles` | One row per user | `status`, `fee_pct_override`, `fee_note`, `min_tx_brl`, `max_tx_brl`, `country`, `primary_use` |
| `deposits` | BRL deposits (PIX/manual) | `method`, `amount`, `status`, `receipt_url`, `expires_at`, `sender_name`, `reviewed_by` |
| `transfer_requests` | Cross-border transfers (in/out) | `direction`, `amount_source/target`, `currency_source/target`, `fx_rate_at_request`, `routing_type`, bank fields (`iban`,`bic_swift`,`sort_code`,`ach_routing`…), `status`, `source_balance` |
| `currency_swaps` | Lock In multi-currency swaps | `from_currency/to_currency`, `from_amount/to_amount`, `market_rate`, `applied_rate`, `fee_pct`, `status` |
| `crypto_orders` | Crypto buy/sell orders | `order_type`, `asset`, `network`, `amount_crypto/brl`, `rate_at_request`, `destination_address`, `txhash`, `binance_order_id`, `status` |
| `crypto_holdings` | Per-user crypto balances | `btc_balance`, `eth_balance`, `usdt_balance`, `usdc_balance` |
| `manual_adjustments` | Admin balance adjustments | `amount`, `currency`, `note`, `created_by` |
| `messages` | In-app user ↔ admin messages | `is_from_admin`, `body`, `read_at` |
| `page_views` | Lightweight analytics | `page`, `referrer`, `user_agent` |

> Balance is **derived**, not stored: `getAvailableBalance()` = deposited − spentBuy + earnedSell − spentXfer + adjTotal
> (across `deposits` / `crypto_orders` / `currency_swaps` / `transfer_requests` / `manual_adjustments`).

---

## How deployment works here

| Layer | What it is | How it deploys |
|-------|-----------|----------------|
| **Frontend** (`*.html`) | Static HTML/JS, no build step | Push to GitHub `main` → Vercel auto-deploys in ~30s |
| **GitHub** | `https://github.com/jayminho/sisbrapag.git`, branch `main` | `git commit` + `git push` |
| **Vercel** | Hosts the site, auto-deploys on push to `main` | Automatic — no manual step needed after push |
| **Supabase** | DB + edge functions in `supabase/functions/` | Edge functions deploy via Supabase MCP `deploy_edge_function` or `supabase functions deploy <name>`; SQL via `apply_migration` / `execute_sql` |

**Live domain:** the bare domain `sisbrapag.com` 308-redirects to **`www.sisbrapag.com`**.
Always test and verify against the `www` URL. App subdomain: `app.sisbrapag.com` → `/dashboard.html`.

---

## Standard frontend deploy procedure

Run git on the **user's real machine via Desktop Commander** (start_process), NOT
the sandbox bash — the sandbox has no GitHub credentials and cannot push.

```bash
cd ~/grok-projects/sisbrapag
rm -f .git/index.lock .git/HEAD.lock   # clear stale locks from any prior failed attempt
git add <files>
git commit -m "fix: <description>"
git push
```

Then **verify it actually went live** (wait ~40s for Vercel, then curl the www URL):

```bash
curl -sL "https://www.sisbrapag.com/dashboard.html?cb=$(date +%s)" | grep -c "<new code marker>"
```

Confirm the old/broken code is gone (count 0) and the new code is present (count ≥ 1).

## Supabase edge function deploy

After editing anything in `supabase/functions/<name>/`, redeploy that function —
a local edit does nothing until deployed. Use the Supabase MCP `deploy_edge_function`
tool (or `supabase functions deploy <name>` via Desktop Commander).

---

## Gotchas learned the hard way

- **Sandbox bash cannot push** (no GitHub auth, and it hits "Operation not permitted"
  on `.git` lock files). Always use **Desktop Commander** for git operations.
- **Stale lock files** (`.git/index.lock`, `.git/HEAD.lock`) from a failed sandbox
  attempt will block commits. Remove them first.
- **Hard-refresh ≠ deploy.** If the user reports "still broken after refresh," the
  most likely cause is the change was never deployed, not browser cache.
- **Test the `www` URL**, not the bare domain (which only returns a redirect stub).
