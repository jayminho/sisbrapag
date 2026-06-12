# SISBRAPAG — Bank / PIX Provider Integration Memory

_Last updated: 2026-06-12_

Reference doc for the PIX deposit rails decision. Companion to `docs/inter-api-reference.md` (Inter technical plan — architecture is provider-agnostic since the PIX API is a Bacen standard).

## Current status

- **Inter API: BLOCKED.** Bank manager unresponsive; account not enabled for API access. Full integration plan ready (tables, edge functions, dashboard flow) and carries over to any provider with minor auth/base-URL changes.
- **Decision (2026-06-12):** stop waiting on Inter alone; pursue crypto-friendly BaaS/IP providers in parallel.

## Market mapping (field research by Jayme)

### Crypto services → which provider they use

| Service | Provider |
|---|---|
| Criptonopix / Vellora | Transfero |
| Emx | BrasilCash IP |
| Pixley | CorpX |
| defibank.digital | Woovi IP Ltda (also used by adult-content sites) |
| crypix.me | Celcoin |
| comprecripto.io | PleBank (FitBank whitelabel) |
| Hyperliquid | Magen IP |
| etherexchange.com.br | — |
| OKTO IP TECH LTDA | (serves adult-content sites) |

### Providers used by Brazilian P2P traders

Cloudwalk, Stark Bank, Celcoin, FitBank, Cartos SCD, BTG, Pay4fun, Acessobank, BS2, Will, Portobank, Linker, ZRO IP, Fiducia SCMEPP (4307598), Cashway Tecnologia (34615822), Paymee, FX4 Bank Múltiplo das Américas (CorpX), BMP.

**Key insight:** no crypto service in the list banks with a traditional bank — they all sit on IPs/BaaS providers. PIX rails for crypto businesses come from BaaS infrastructure, not bank-manager approval.

## Sanitized shortlist

### Tier 1 — pursue now (primary rail candidates)

1. **Transfero** — crypto-native (Swiss-Brazilian group, BRZ stablecoin issuer). Will not de-bank a crypto business. Used by Criptonopix/Vellora.
2. **Celcoin** — largest BaaS (~R$30bi/month processed, full Banking/Payments/Regulatory licenses). Used by crypix.me + P2P traders. Best infrastructure.
3. **FitBank** — consolidated BaaS (PIX, boletos, white-label). Validated twice: comprecripto (via PleBank) + P2P traders.

### Tier 2 — backup / parallel track

4. **Woovi** — fast onboarding, tolerant of high-risk verticals, good dev-facing PIX APIs. Plan B if Tier 1 onboarding drags.
5. **BTG Pactual** — long-game banking relationship; genuinely crypto-friendly (owns Mynt exchange). Slower, but cultivate in parallel for credibility + redundancy.

### Cut (do not focus)

Stark Bank, BS2 (good but conservative; redundant vs BTG), Cartos, Acessobank, ZRO, Cashway, FX4/CorpX, Pay4fun, Linker, Portobank, Fiducia, Paymee, BMP, Cloudwalk, Will, BrasilCash, Magen, OKTO — small IPs / weak fit / highest regulatory-squeeze risk. Backup-of-backup at best.

Also noted: **Efí Bank (ex-Gerencianet)** — easiest self-service PIX API on the market (no bank manager needed); pragmatic unblock option even though not in the field-research lists. **Brasil Bitcoin** offers a combined PIX + crypto API (exchange, not a bank — weigh custody/regulatory comfort).

## Regulatory context (critical)

BCB published **three resolutions on 2025-11-10** regulating virtual assets: VASP licensing, crypto trading equated to the FX market, tighter rules on foreign exchanges. Rolling out through 2026 — directly affects SISBRAPAG's 3%/3% onramp/offramp model. **Ask every candidate provider how they're handling these rules** — a provider with an answer is one that will still bank us in 12 months.

Also relevant: BCB resolutions 494–498/2025 (end of pocket accounts, individualized accounts required) and Joint Resolution 16/2025 — favor providers with strong compliance.

## Strategy

- Keep **two rails** (primary + backup) so no single provider can kill the operation.
- Architecture stays provider-agnostic: same Supabase tables, edge functions (`pix-create-charge`, `pix-webhook`), and dashboard QR flow per `docs/inter-api-reference.md`.
- If Inter credentials ever arrive, Inter can be added as an extra rail behind the same edge function.

## Next steps

1. Contact Transfero, Celcoin, FitBank asking: (a) onboarding requirements for a crypto/remittance PJ, (b) PIX Cobrança API access, (c) pricing, (d) stance on the Nov/2025 BCB virtual-asset resolutions.
2. Pick primary + backup from whoever answers best.
3. Build the deposit feature per the existing plan.

## Sources

- [Celcoin BaaS overview](https://celcoin.com.br/articles/melhores-plataformas-baas-no-brasil/)
- [BCB crypto resolutions Nov 2025 — Agência Brasil](https://agenciabrasil.ebc.com.br/economia/noticia/2025-11/banco-central-estabelece-regras-para-o-mercado-de-criptoativos)
- [Análise das resoluções cripto — Conjur](https://www.conjur.com.br/2025-nov-21/cripto-resolucoes-do-banco-central-o-bom-o-ruim-e-o-questionavel/)
- [Regulatory outlook 2026 — Livecoins](https://livecoins.com.br/principais-mudancas-regulatorias-criptoativos-2026/)
- [Easiest PIX APIs to integrate](https://mayconbraga.com.br/blog/conteudo/as-3-apis-de-pix-mais-faceis-de-integrar)
- [Brasil Bitcoin PIX+crypto API](https://brasilbitcoin.com.br/api-pix-criptomoedas)
