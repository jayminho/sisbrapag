import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

// Server-side auto-expiry for stale deposits.
// Invoked every 5 minutes by pg_cron (job 'expire-deposits-5min').
// Flips any 'created' deposit past expires_at to 'expired' and emails the user.
// verify_jwt = false (called by cron with no JWT).

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const brl = (n: number) => 'R$ ' + Number(n).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

serve(async (_req) => {
  try {
    const now = new Date().toISOString()
    // Atomically flip all overdue 'created' deposits to 'expired' and get the affected rows back.
    const patchRes = await fetch(`${SUPABASE_URL}/rest/v1/deposits?status=eq.created&expires_at=lte.${now}`, {
      method: 'PATCH',
      headers: {
        'apikey': SERVICE_KEY,
        'Authorization': `Bearer ${SERVICE_KEY}`,
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      },
      body: JSON.stringify({ status: 'expired' }),
    })
    const expired = await patchRes.json()
    if (!Array.isArray(expired) || expired.length === 0) {
      return new Response(JSON.stringify({ expired: 0 }), { headers: { 'Content-Type': 'application/json' } })
    }

    for (const d of expired) {
      const pr = await fetch(`${SUPABASE_URL}/rest/v1/profiles?id=eq.${d.user_id}&select=email`, {
        headers: { 'apikey': SERVICE_KEY, 'Authorization': `Bearer ${SERVICE_KEY}` },
      })
      const profs = await pr.json()
      const email = profs?.[0]?.email
      if (!email) continue
      const html = `<div style="font-family:sans-serif;max-width:560px;margin:0 auto"><div style="background:#0B1120;padding:20px 28px"><span style="color:#10B981;font-weight:700;font-size:16px">SISBRAPAG</span></div><div style="padding:28px;background:#fff;border:1px solid #e2e8f0"><p style="margin:0;font-size:14px;color:#334155;line-height:1.6">O prazo de 60 minutos para concluir seu depósito de <strong>${brl(d.amount)}</strong> (ref ${d.reference_code}) expirou. Nenhum valor foi debitado.<br><br>Você pode iniciar um novo depósito quando quiser em <a href="https://app.sisbrapag.com" style="color:#10B981">app.sisbrapag.com</a>.</p></div></div>`
      await fetch(`${SUPABASE_URL}/functions/v1/send-email`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'apikey': SERVICE_KEY, 'Authorization': `Bearer ${SERVICE_KEY}` },
        body: JSON.stringify({ to: [email], subject: `Depósito expirado — ${brl(d.amount)}`, html, replyTo: 'atendimento@sisbrapag.com' }),
      })
    }
    return new Response(JSON.stringify({ expired: expired.length }), { headers: { 'Content-Type': 'application/json' } })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500, headers: { 'Content-Type': 'application/json' } })
  }
})
