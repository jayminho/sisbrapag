import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// ── Rate fetching (4-tier BRL system) ───────────────────────────────────────

const CURRENCIES = ['USD', 'EUR', 'GBP'] as const
type FxCurrency = typeof CURRENCIES[number]

// AwesomeAPI returns BRL per 1 unit of foreign currency
async function rateFromAwesome(currency: FxCurrency): Promise<number | null> {
  try {
    const res = await fetch(
      `https://economia.awesomeapi.com.br/json/last/${currency}-BRL`,
      { signal: AbortSignal.timeout(5000) }
    )
    if (!res.ok) return null
    const data = await res.json()
    const rate = parseFloat(data[`${currency}BRL`]?.bid)
    return isFinite(rate) && rate > 0 ? rate : null
  } catch { return null }
}

// Frankfurter: EUR base; for USD and GBP, derive BRL via EUR
async function rateFromFrankfurter(currency: FxCurrency): Promise<number | null> {
  try {
    const res = await fetch(
      `https://api.frankfurter.app/latest?from=${currency}&to=BRL`,
      { signal: AbortSignal.timeout(5000) }
    )
    if (!res.ok) return null
    const data = await res.json()
    const rate = data?.rates?.BRL
    return isFinite(rate) && rate > 0 ? rate : null
  } catch { return null }
}

// exchangerate-api (free tier, no key)
async function rateFromExchangeRateApi(currency: FxCurrency): Promise<number | null> {
  try {
    const res = await fetch(
      `https://open.er-api.com/v6/latest/${currency}`,
      { signal: AbortSignal.timeout(5000) }
    )
    if (!res.ok) return null
    const data = await res.json()
    const rate = data?.rates?.BRL
    return isFinite(rate) && rate > 0 ? rate : null
  } catch { return null }
}

// Hardcoded fallback rates (BRL per 1 unit)
const FALLBACK_RATES: Record<FxCurrency, number> = {
  USD: 5.70,
  EUR: 6.20,
  GBP: 7.25,
}

async function getMarketRate(currency: FxCurrency): Promise<{ rate: number; source: string }> {
  const awesome = await rateFromAwesome(currency)
  if (awesome) return { rate: awesome, source: 'awesomeapi' }

  const frankfurter = await rateFromFrankfurter(currency)
  if (frankfurter) return { rate: frankfurter, source: 'frankfurter' }

  const erapi = await rateFromExchangeRateApi(currency)
  if (erapi) return { rate: erapi, source: 'exchangerate-api' }

  return { rate: FALLBACK_RATES[currency], source: 'hardcoded' }
}

// ── Main handler ─────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // ── Auth: extract user from JWT ──────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization header' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // User-scoped client (to verify session)
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    const { data: { user }, error: authError } = await userClient.auth.getUser()
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // ── Parse body ───────────────────────────────────────────────
    const body = await req.json()
    const { to_currency, from_amount } = body

    if (!CURRENCIES.includes(to_currency)) {
      return new Response(JSON.stringify({ error: 'Invalid to_currency. Must be USD, EUR, or GBP.' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    const fromAmount = parseFloat(from_amount)
    if (!isFinite(fromAmount) || fromAmount <= 0) {
      return new Response(JSON.stringify({ error: 'Invalid from_amount.' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // ── Fetch rate ───────────────────────────────────────────────
    const { rate: marketRate, source: rateSource } = await getMarketRate(to_currency as FxCurrency)
    const FEE = 0.03
    const appliedRate = marketRate * (1 + FEE)           // BRL per 1 foreign unit (worse for user)
    const toAmount    = parseFloat((fromAmount / appliedRate).toFixed(4))

    // ── Service-role client for RPC (bypasses RLS) ───────────────
    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // ── Atomic swap via RPC ──────────────────────────────────────
    const { data: swap, error: rpcError } = await adminClient.rpc('perform_swap', {
      p_user_id:      user.id,
      p_from_amount:  fromAmount,
      p_to_currency:  to_currency,
      p_to_amount:    toAmount,
      p_market_rate:  marketRate,
      p_applied_rate: appliedRate,
    })

    if (rpcError) {
      const isInsufficientBalance = rpcError.message?.includes('insufficient_balance')
      return new Response(
        JSON.stringify({
          error: isInsufficientBalance
            ? 'Saldo BRL insuficiente para este câmbio.'
            : 'Erro ao processar câmbio. Tente novamente.',
          detail: rpcError.message,
        }),
        {
          status: isInsufficientBalance ? 400 : 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // ── Telegram notification (fire-and-forget) ──────────────────
    // Intentionally not awaited — Telegram outage must never block the swap.
    const telegramUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/notify-telegram`
    const { data: profile } = await adminClient
      .from('profiles')
      .select('full_name')
      .eq('id', user.id)
      .single()

    fetch(telegramUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${Deno.env.get('SUPABASE_ANON_KEY')}`,
      },
      body: JSON.stringify({
        type:        'swap',
        name:        profile?.full_name || '—',
        userEmail:   user.email,
        fromAmount:  fromAmount.toLocaleString('pt-BR', { minimumFractionDigits: 2 }),
        toCurrency:  to_currency,
        toAmount:    toAmount.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 4 }),
        appliedRate: appliedRate.toFixed(4),
        marketRate:  marketRate.toFixed(4),
        rateSource,
        ref:         swap.reference_code,
      }),
    }).catch(() => { /* silent — Telegram down is not our problem */ })

    // ── Return result ────────────────────────────────────────────
    return new Response(
      JSON.stringify({
        success:        true,
        swap_id:        swap.id,
        reference_code: swap.reference_code,
        from_currency:  'BRL',
        from_amount:    fromAmount,
        to_currency:    to_currency,
        to_amount:      toAmount,
        applied_rate:   appliedRate,
        market_rate:    marketRate,
        rate_source:    rateSource,
        created_at:     swap.created_at,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
