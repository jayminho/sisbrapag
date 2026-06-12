# Banco Inter API — Reference for SISBRAPAG PIX Deposit System

> **Source:** developers.inter.co (official portal). Compiled 2026-06-11.  
> **Status:** Ready to implement — awaiting Inter API credentials activation on Jayme's account.  
> **Purpose:** Full reference for building the PIX QR code deposit flow in SISBRAPAG.

---

## 1. Overview

Banco Inter provides a REST API for PJ (business) accounts. All calls are authenticated via **OAuth 2.0 + mTLS** (mutual TLS). This means every request must present a client certificate alongside the Bearer token. There is no way to call the API from the browser — **all calls must go through a server-side function** (Supabase Edge Function in our case).

### Relevant API for SISBRAPAG deposits

| What we need | Inter API module |
|---|---|
| Generate PIX QR code for deposit | **PIX Cobrança Imediata** (`/pix/v2/cob`) |
| Get QR code image (PNG) | `/pix/v2/cob/{txid}/qrcode` |
| Check if payment was received | **Webhook** (Inter calls us when paid) |
| Confirm payment status manually | `GET /pix/v2/cob/{txid}` |

---

## 2. Base URLs

| Environment | Base URL |
|---|---|
| **Production** | `https://cdpj.partners.bancointer.com.br` |
| **Sandbox** | `https://cdpjsandbox.ti.inter.co` |

All endpoints below are relative to the base URL.

---

## 3. Authentication

### 3.1 What you need (from Internet Banking PJ)

1. **client_id** — shown in the integration panel
2. **client_secret** — shown in the integration panel
3. **Certificate file** (`.crt`) — downloaded from Inter integration panel
4. **Private key file** (`.key`) — downloaded from Inter integration panel

> ⚠️ The `.crt` and `.key` files are used for mTLS. They must NEVER be committed to git or exposed in frontend code. Store them as Supabase secrets / environment variables.

### 3.2 How to create the integration (Inter Internet Banking)

1. Login to Inter Internet Banking (via QR Code)
2. Go to **Soluções para sua empresa → Nova Integração**
3. Fill in details and accept required permissions (scopes)
4. Download the `.crt` and `.key` files
5. Activate the integration

### 3.3 Required scopes for PIX deposits

| Scope | Purpose |
|---|---|
| `cob.write` | Create PIX charges (generate QR codes) |
| `cob.read` | Read/query PIX charges |
| `pix.read` | Read received PIX transactions |
| `webhook.write` | Register/delete webhook URL |
| `webhook.read` | Read registered webhook |

### 3.4 Getting an access token

```
POST /oauth/v2/token
Content-Type: application/x-www-form-urlencoded
[mTLS: present client.crt + client.key]

Body (form-encoded):
  client_id=YOUR_CLIENT_ID
  client_secret=YOUR_CLIENT_SECRET
  grant_type=client_credentials
  scope=cob.write cob.read pix.read webhook.write webhook.read
```

**Response:**
```json
{
  "access_token": "eyJ...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "scope": "cob.write cob.read pix.read webhook.write webhook.read"
}
```

- Token expires in **3600 seconds (1 hour)**
- Cache the token; request a new one only when expired
- All subsequent calls: `Authorization: Bearer {access_token}` + mTLS cert

---

## 4. PIX Cobrança (Charge / QR Code)

### 4.1 Create an immediate PIX charge

```
POST /pix/v2/cob
Authorization: Bearer {token}
Content-Type: application/json
[mTLS required]
```

**Request body:**
```json
{
  "calendario": {
    "expiracao": 3600
  },
  "devedor": {
    "nome": "Nome do Usuário SISBRAPAG"
  },
  "valor": {
    "original": "500.00"
  },
  "chave": "SEU_PIX_KEY_INTER",
  "solicitacaoPagador": "Depósito SISBRAPAG #USER_ID"
}
```

| Field | Description |
|---|---|
| `calendario.expiracao` | QR code validity in seconds (3600 = 1 hour) |
| `devedor.nome` | Payer name (optional but good UX) |
| `devedor.cpf` | Payer CPF (optional) |
| `valor.original` | Amount in BRL as string with 2 decimal places |
| `chave` | Your Inter account PIX key (CPF, CNPJ, email, phone, or random key) |
| `solicitacaoPagador` | Message shown to payer in their bank app |

**Response:**
```json
{
  "txid": "7978c0c97ea847e78e8849634473c1f1",
  "revisao": 0,
  "loc": {
    "id": 789,
    "location": "pix.inter.com.br/qr/v2/9d36b84fc70b478a...",
    "tipoCob": "cob"
  },
  "location": "pix.inter.com.br/qr/v2/9d36b84fc70b478a...",
  "status": "ATIVA",
  "calendario": {
    "criacao": "2021-01-01T16:00:00.000Z",
    "expiracao": 3600
  },
  "devedor": {
    "nome": "Nome do Usuário"
  },
  "valor": {
    "original": "500.00"
  },
  "chave": "SEU_PIX_KEY_INTER",
  "solicitacaoPagador": "Depósito SISBRAPAG #USER_ID",
  "pixCopiaECola": "00020101021226890014br.gov.bcb.pix..."
}
```

| Key field | Use |
|---|---|
| `txid` | **Store this** — used to check payment status + link to user deposit |
| `pixCopiaECola` | PIX "Copia e Cola" string — show in UI for manual copy |
| `location` | Dynamic QR code URL |
| `status` | `ATIVA` = pending payment |

### 4.2 Get QR code image (PNG)

```
GET /pix/v2/cob/{txid}/qrcode
Authorization: Bearer {token}
[mTLS required]
```

**Response:**
```json
{
  "qrcode": "iVBORw0KGgo...",   // base64-encoded PNG
  "imagemQrcode": "data:image/png;base64,iVBOR..."
}
```

Use `imagemQrcode` directly as `<img src="...">` in the dashboard.

### 4.3 Check charge status

```
GET /pix/v2/cob/{txid}
Authorization: Bearer {token}
[mTLS required]
```

Possible `status` values:

| Status | Meaning |
|---|---|
| `ATIVA` | QR code active, payment pending |
| `CONCLUIDA` | **Payment received** ✅ |
| `REMOVIDA_PELO_USUARIO_RECEBEDOR` | Cancelled by us |
| `REMOVIDA_PELO_PSP` | Cancelled by Inter |

---

## 5. Webhooks (Payment Confirmation)

### 5.1 Register your webhook URL

```
PUT /pix/v2/webhook/{chave}
Authorization: Bearer {token}
Content-Type: application/json
[mTLS required]
```

`{chave}` = your Inter PIX key (same one used to create charges)

**Body:**
```json
{
  "webhookUrl": "https://iiclntwwutsaoorbncfp.supabase.co/functions/v1/pix-webhook"
}
```

> Do this **once** when setting up production. Inter will call this URL whenever a PIX payment is received.

### 5.2 Webhook payload (Inter calls SISBRAPAG)

When a user pays the QR code, Inter sends a `POST` to your webhook URL:

```json
{
  "pix": [
    {
      "endToEndId": "E00000000202101010000000000000000",
      "txid": "7978c0c97ea847e78e8849634473c1f1",
      "valor": "500.00",
      "horario": "2021-01-01T16:01:35.000Z",
      "infoPagador": "optional message from payer"
    }
  ]
}
```

| Field | Use |
|---|---|
| `txid` | Match to our `deposits` table row |
| `valor` | Confirm amount matches what was requested |
| `endToEndId` | Store for audit trail / reconciliation |
| `horario` | Timestamp of payment |

### 5.3 Webhook security

Inter does **not** send a secret header by default. To validate authenticity:
- Check that the request comes from Inter's IP ranges (optional)
- Verify `txid` exists in our database before crediting
- Always confirm by calling `GET /pix/v2/cob/{txid}` before crediting balance (double-check)

---

## 6. Sandbox Environment

- URL: `https://cdpjsandbox.ti.inter.co`
- Sandbox credentials are separate from production
- **How to simulate a payment in sandbox:** After creating a charge, call the sandbox simulator endpoint (Inter provides a UI or API endpoint to simulate payment receipt)
- Sandbox does NOT send real webhooks — you will need to poll `GET /pix/v2/cob/{txid}` to check status in sandbox testing

---

## 7. Error Codes

| HTTP Status | Meaning |
|---|---|
| `400` | Invalid request body / missing fields |
| `401` | Invalid/expired token or wrong mTLS certificate |
| `403` | Scope not authorized for this operation |
| `404` | txid not found |
| `422` | Business rule violation (e.g. expired charge) |
| `429` | Rate limit exceeded |
| `500` | Inter internal error — retry with backoff |

---

## 8. SISBRAPAG Implementation Plan

### Architecture

```
User (dashboard.html)
       │
       ▼
[Supabase Edge Function: pix-create-charge]
       │  ← stores deposit row in Supabase (status: pending)
       │  ← calls Inter API with mTLS cert (server-side only)
       │  ← returns QR code image + txid to frontend
       ▼
User sees QR code → opens bank app → scans → pays
       │
       ▼
Inter calls webhook →
[Supabase Edge Function: pix-webhook]
       │  ← finds deposit row by txid
       │  ← calls GET /pix/v2/cob/{txid} to confirm (belt+suspenders)
       │  ← updates deposit status to confirmed
       │  ← updates user balance in Supabase
       │  ← sends email to user "Depósito confirmado!"
       ▼
User balance updated in dashboard
```

### Supabase tables needed

**`public.deposits`**
```sql
id            uuid primary key default gen_random_uuid()
user_id       uuid references auth.users
amount_brl    numeric(12,2) not null
txid          text unique not null        -- Inter txid
status        text default 'pending'      -- pending | confirmed | expired
pix_end_to_end_id  text                  -- set on confirmation
created_at    timestamptz default now()
confirmed_at  timestamptz
expires_at    timestamptz                 -- created_at + expiracao seconds
```

**`public.balances`** (or add `balance_brl` column to `public.profiles`)
```sql
user_id       uuid primary key references auth.users
balance_brl   numeric(12,2) default 0
updated_at    timestamptz default now()
```

### Supabase Edge Functions needed

| Function | Trigger | Purpose |
|---|---|---|
| `pix-create-charge` | Called by dashboard | Creates Inter PIX charge, stores deposit row, returns QR image |
| `pix-webhook` | Called by Inter (POST) | Receives payment notification, confirms, credits balance |

### Supabase Secrets needed

| Secret name | Value |
|---|---|
| `INTER_CLIENT_ID` | From Inter integration panel |
| `INTER_CLIENT_SECRET` | From Inter integration panel |
| `INTER_CERT` | Contents of `.crt` file (base64 or PEM) |
| `INTER_KEY` | Contents of `.key` file (base64 or PEM) |
| `INTER_PIX_KEY` | Your PIX key registered on the Inter account |
| `INTER_BASE_URL` | `https://cdpj.partners.bancointer.com.br` (prod) or sandbox URL |

---

## 9. Dashboard UX Flow

1. User clicks **"Depositar"** tab in dashboard
2. Types amount in BRL (min R$10, for example)
3. Clicks **"Gerar QR Code"**
4. Dashboard calls `pix-create-charge` edge function
5. QR code image + "Pix Copia e Cola" string displayed
6. Countdown timer shows QR code expiry (1 hour)
7. Dashboard polls `GET /pix/v2/cob/{txid}` every 10 seconds via another edge function (or listens via Supabase Realtime on the `deposits` table)
8. When Inter webhook fires → `deposits.status` → `confirmed` → Supabase Realtime pushes update to dashboard
9. Dashboard shows **"Depósito confirmado! R$ 500,00 creditado."** and updates balance display

---

## 10. Reference Links

| Resource | URL |
|---|---|
| Developer portal | https://developers.inter.co |
| PIX Cobrança API reference | https://developers.inter.co/references/pix |
| Token/Auth reference | https://developers.inter.co/references/token |
| Banking API (balance, statement) | https://developers.inter.co/references/banking |
| Sandbox docs | https://developers.inter.co/sandbox |
| Error codes | https://developers.inter.co/erros-status-code |
| FAQ | https://developers.inter.co/duvidas-frequentes |
| Developer community | https://comunidade.inter.co/developers |
| Support contact | https://developers.inter.co/contacts |
| Inter PJ account opening | https://www.bancointer.com.br/empresas/conta-digital/pessoa-juridica/ |
