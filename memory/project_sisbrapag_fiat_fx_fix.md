---
name: project-sisbrapag-fiat-fx-fix
description: "SISBRAPAG site's fiat FX converter was switched from exchangerate-api to Frankfurter API to fix delays"
metadata: 
  node_type: memory
  type: project
  originSessionId: f2a00917-a17a-496e-92e0-a62903c7ab0a
---

The sisbrapag.com site's currency converter had a delayed fiat-rate source (exchangerate-api.com), while the crypto side (CoinGecko) worked flawlessly. Fixed by switching `fetchFiatRates` to a layered fallback: Frankfurter API (api.frankfurter.dev — free, no key, no quota, ECB-sourced) as primary, exchangerate-api as secondary, hardcoded approximates as last resort. Morningstar was researched and confirmed to NOT offer an accessible free FX API.

**Why:** User found Morningstar accurate via web search and asked to check if it had a free API first; it didn't, so Frankfurter was chosen as the best free/no-key/no-limit alternative.

**How to apply:** If asked about this site's converter again, the fix is live — commit `fbb7dfd` on `main` of github.com/jayminho/sisbrapag, deployed via github.dev (VS Code in browser, no PAT). Documented in STATUS.md and README.md in the project's local workspace (`/Users/jpn/grok-projects/sisbrapag/`). Vercel auto-deploys from `main`.

**Deployment method note:** The standard GitHub web CodeMirror editor corrupted the file twice; github.dev (VS Code in browser, authenticated via existing GitHub session as "jayminho") proved reliable — clipboard paste (cmd+v) avoids auto-indentation issues with multi-line code blocks. Use this approach again for future direct GitHub edits if the user wants to avoid personal access tokens.
