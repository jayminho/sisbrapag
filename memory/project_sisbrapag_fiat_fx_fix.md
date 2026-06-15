---
name: project-sisbrapag-fiat-fx-fix
description: "SISBRAPAG fiat FX converter: switched to Frankfurter API with BCB provider for BRL (same-day rate); ECB for EUR/GBP"
metadata: 
  node_type: memory
  type: project
  originSessionId: f2a00917-a17a-496e-92e0-a62903c7ab0a
---

The sisbrapag.com site's currency converter had a delayed fiat-rate source (exchangerate-api.com). Fixed by switching to Frankfurter API (api.frankfurter.dev). Later discovered BRL via ECB was also stale (cross-rate, up to 3 days behind). Fixed a second time by adding BCB provider.

## Current state (as of 2026-06-15, commit `4310dce`)

Both `fetchFiatRates` (index.html) and `cvFetchFiat` (dashboard.html) now work as follows:

- **BRL as base** (`base=BRL`): adds `&provider=BCB` → Banco Central do Brasil, same-day rate
- **All other bases**: fires two parallel Frankfurter calls:
  1. Main call (default ECB) for all currencies
  2. `?base=USD&symbols=BRL&provider=BCB` for a fresh BRL rate
  - Patches `rates.BRL = BCB_usdBrl × rates.USD` (cross-derived; correct for any base)
- **Fallback 1:** exchangerate-api.com (free, no key)
- **Fallback 2:** hardcoded approximates `{ USD:1, EUR:0.92, GBP:0.79, BRL:5.65 }`

## Why BCB vs ECB for BRL

ECB derives BRL as a cross-rate from other providers, and was returning `"date":"2026-06-12"` on a Monday (3 days stale). BCB (Banco Central do Brasil) publishes the official PTAX rate daily and returned `"date":"2026-06-15"` with rate `5.0498`. EUR and GBP are fine via ECB — they're natively published currencies for ECB.

## Frankfurter provider parameter

Frankfurter v1 API supports `&provider=BCB` directly. BCB is one of 55 central bank sources. No API key required. URL: `https://api.frankfurter.dev/v1/latest?base=USD&symbols=BRL&provider=BCB`

## Deployment method note

Always deploy via `gh` CLI from `/Users/jpn/grok-projects/sisbrapag` using Desktop Commander MCP (not github.dev — no terminal there). Vercel auto-deploys from `main`.
