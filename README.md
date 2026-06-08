# SISBRAPAG Website

Official minimal static website for **SISBRAPAG** (Sistema Brasil Pagamentos Digitais Ltda).

- Super minimal, professional single-page design
- Prominent live **currency + crypto converter** (BRL, USD, EUR, GBP ↔ BTC, ETH, USDT, USDC and cross pairs)
- Built as a single `index.html` (Tailwind via CDN) for maximum portability

## Current Status (2026-06-08)

- **Live site**: https://sisbrapag.vercel.app/
- **GitHub repo**: https://github.com/jayminho/sisbrapag
- `vercel.json` present for explicit static configuration
- Ready for custom domain `sisbrapag.com` (Namecheap)

## Local development

The canonical deployment files are at the repo root (`index.html` + `vercel.json`).

```bash
# For local testing (from this repo or local copy)
python -m http.server 8787
# open http://localhost:8787
```

## Deployment

- Connected to Vercel for instant static deploys from this repo (GitHub integration).
- Next: Add `sisbrapag.com` + `www.sisbrapag.com` in Vercel Domains tab, then configure the DNS records shown by Vercel inside Namecheap.

Once the custom domain is set, changes pushed to this repo will automatically deploy.

## Company

SISBRAPAG — Sistema Brasil Pagamentos Digitais Ltda  
CNPJ: 32.742.398/0001-28  
Rio de Janeiro, Brazil

Domains: sisbrapag.com (primary international) / sisbrapag.com.br

---

*Last updated 2026-06-08*