import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const BOT_TOKEN = Deno.env.get('TELEGRAM_BOT_TOKEN')
    const CHAT_ID   = Deno.env.get('TELEGRAM_CHAT_ID')

    if (!BOT_TOKEN || !CHAT_ID) {
      return new Response(JSON.stringify({ error: 'Missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const body = await req.json()
    const { type } = body

    let text = ''

    // ── New user signup ───────────────────────────────────────────────────────
    if (type === 'new_user') {
      const { email, name } = body
      text = [
        `🆕 *Novo usuário cadastrado*`,
        ``,
        `📧 E-mail: \`${email}\``,
        name ? `👤 Nome: ${name}` : null,
        ``,
        `Acesse o painel admin para aprovar.`,
      ].filter(l => l !== null).join('\n')

    // ── Deposit (legacy format — no type field) ───────────────────────────────
    } else if (!type || type === 'deposit') {
      const { name, amount, method, ref } = body
      const methodLabel = method === 'ted' ? 'TED' : method === 'pix' ? 'PIX' : (method || '—')
      text = [
        `💰 *Novo depósito recebido*`,
        ``,
        `👤 Cliente: ${name || '—'}`,
        `💵 Valor: R$ ${amount}`,
        `🏦 Método: ${methodLabel}`,
        `🔖 Ref: \`${ref}\``,
      ].join('\n')

    // ── International transfer ────────────────────────────────────────────────
    } else if (type === 'transfer') {
      const { name, userEmail, direction, amount, ref, recipient, bank, purpose } = body
      text = [
        `🌍 *Nova transferência internacional*`,
        ``,
        `👤 Cliente: ${name || '—'}`,
        userEmail ? `📧 E-mail: ${userEmail}` : null,
        `↔️ Direção: ${direction || '—'}`,
        `💵 Valor: ${amount}`,
        `🏦 Destino: ${recipient || '—'} ${bank ? `· ${bank}` : ''}`,
        purpose ? `📋 Finalidade: ${purpose}` : null,
        `🔖 Ref: \`${ref}\``,
      ].filter(l => l !== null).join('\n')

    // ── Crypto order ─────────────────────────────────────────────────────────
    } else if (type === 'crypto') {
      const { name, userEmail, orderType, asset, network, brlAmount, cryptoAmount, ref, address } = body
      const typeLabel  = { buy: '🟢 Compra', sell: '🔴 Venda', withdraw: '📤 Saque' }[orderType] || orderType || '—'
      text = [
        `₿ *Nova ordem de cripto — ${typeLabel}*`,
        ``,
        `👤 Cliente: ${name || '—'}`,
        userEmail ? `📧 E-mail: ${userEmail}` : null,
        `🪙 Ativo: ${asset || '—'}${network ? ` (${network})` : ''}`,
        brlAmount   ? `💵 BRL: ${brlAmount}` : null,
        cryptoAmount ? `🔢 Qty: ${cryptoAmount}` : null,
        address     ? `📍 Endereço: \`${address?.slice(0, 10)}…${address?.slice(-6)}\`` : null,
        `🔖 Ref: \`${ref}\``,
      ].filter(l => l !== null).join('\n')

    // ── Lock-in swap ─────────────────────────────────────────────────────────
    } else if (type === 'swap') {
      const { name, userEmail, fromAmount, toCurrency, toAmount, appliedRate, marketRate, rateSource, ref } = body
      const flag = { USD: '🇺🇸', EUR: '🇪🇺', GBP: '🇬🇧' }[toCurrency] || '🌍'
      text = [
        `🔒 *Lock In — Câmbio executado*`,
        ``,
        `👤 Cliente: ${name || '—'}`,
        userEmail ? `📧 ${userEmail}` : null,
        `💵 BRL debitado: R$ ${fromAmount}`,
        `${flag} ${toCurrency} creditado: ${toAmount}`,
        `📊 Taxa aplicada: ${appliedRate} BRL/${toCurrency}`,
        `💹 Taxa mercado: ${marketRate} BRL/${toCurrency}`,
        rateSource ? `🔌 Fonte: ${rateSource}` : null,
        `🔖 Ref: \`${ref}\``,
        ``,
        `→ Comprar ${toCurrency === 'USD' ? 'USDC' : toCurrency}: ~${toAmount} ${toCurrency}`,
      ].filter(Boolean).join('\n')

    } else {
      // Unknown type — send raw dump so nothing is silently swallowed
      text = `⚠️ *Evento SISBRAPAG (tipo desconhecido: ${type})*\n\n\`\`\`\n${JSON.stringify(body, null, 2)}\n\`\`\``
    }

    const tgRes = await fetch(
      `https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chat_id: CHAT_ID,
          text,
          parse_mode: 'Markdown',
        }),
      }
    )

    const tgData = await tgRes.json()

    return new Response(JSON.stringify(tgData), {
      status: tgRes.status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
