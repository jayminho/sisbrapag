## SISBRAPAG Website

Official minimal static website for **SISBRAPAG** (Sistema Brasil Pagamentos Digitais Ltda).

- Super minimal, professional single-page design
- Prominent live **currency + crypto converter** (BRL, USD, EUR, GBP ↔ BTC, ETH, USDT, USDC and cross pairs)
- Built as a single `index.html` (Tailwind via CDN) for maximum portability

### Local development
```bash
# From this folder
python -m http.server 8787
# open http://localhost:8787
```

### Deployment (recommended)
- Connected to Vercel for instant static deploys from this repo
- Custom domain: sisbrapag.com (configured via Namecheap DNS)

### Tech
- Pure vanilla + Tailwind play CDN + Font Awesome
- Live rates via CoinGecko + exchangerate-api (public, no keys)

Changes pushed here will (once Vercel is connected) automatically deploy.

---

Company: SISBRAPAG • Rio de Janeiro, Brazil
Domains: sisbrapag.com (primary international) / sisbrapag.com.br
