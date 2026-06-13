# Deposit Flow — End-to-End Test Checklist

Test date: 2026-06-12
Run on production: `app.sisbrapag.com/dashboard.html` (user) + `admin.sisbrapag.com/admin.html` (admin)
Claude watches: `deposits` table, `receipts` bucket, edge function logs — live.

---

## A. PIX deposit — happy path (user side)

- [ ] **1. Open Deposit section** — nav item appears, wizard loads on step 1 (method).
- [ ] **2. PIX selectable, TED gating** — PIX is clickable 24/7. Check TED: greyed out if outside Mon–Fri 09–16h BRT, clickable inside. (Right now it's evening → TED should be greyed.)
- [ ] **3. Pick PIX → enter amount** — e.g. R$ 100,00. Advances to payment details.
- [ ] **4. `deposits` row created** — *(Claude confirms)* status `created`, 5-digit numeric ref, `expires_at` ≈ now +60 min, correct `amount_brl`.
- [ ] **5. PIX copia-e-cola + QR render** — code string shows, QR image draws, "copy" works.
- [ ] **6. 60-min countdown** — timer visible and ticking down.
- [ ] **7. "created" email to user** — arrives in inbox.
- [ ] **8. Upload receipt** — pick a test PDF/JPG. Uploads without error.
- [ ] **9. Receipt lands in bucket** — *(Claude confirms)* `receipts/{uid}/{deposit_id}.ext` exists.
- [ ] **10. Status → `pending_review`** — UI updates; "uploaded" email to user + "pending review" email to admin both fire.

## B. Admin review — credit (admin side)

- [ ] **11. Pending badge** — amber count shows on Deposits nav.
- [ ] **12. Deposit card** — shows user's real name (profiles join), amount, ref.
- [ ] **13. View receipt** — signed-URL link opens the uploaded file.
- [ ] **14. Credit** — confirm dialog → status flips to `credited`, `reviewed_by`/`reviewed_at` set. *(Claude confirms in DB.)*
- [ ] **15. Credit email** — user receives "deposit credited" email.
- [ ] **16. Balance updates** — user dashboard shows balance = sum(credited). Refresh and confirm R$ 100,00.

## C. Admin review — reject (second test deposit)

- [ ] **17. Create a 2nd PIX deposit + upload receipt** (repeat A).
- [ ] **18. Reject** — modal opens, pick a canned reason (valor divergente / nome diverge / não localizado / comprovante inválido) → status `rejected`.
- [ ] **19. Reject email** — user receives rejection email with the reason.
- [ ] **20. Balance unaffected** — still R$ 100,00 (rejected does not credit).

## D. Edge cases / guardrails

- [ ] **21. One open deposit per user** — try to start a 3rd deposit while one is still `created`/`pending_review`. DB partial unique index should block it; UI should handle gracefully (not crash).
- [ ] **22. Expiry fallback** — *(note only — real cron not built yet)* confirm client-side countdown hits 0 and flips to `expired` if tab left open. This is the gap we fix next.
- [ ] **23. TED block** (optional, if testing inside business hours) — shows Inter bank info (Ag 0001, Cc 5476239-1, CNPJ 32.742.398/0001-28).

---

## Watch-for / likely failure points
- Email `to` field must be an **array** (Resend requirement) — watch for silent non-delivery.
- Signed receipt URL expires in 120s — if "view receipt" 404s, that's expiry, just re-click.
- Balance is **derived** (sum of credited), no `profiles.balance` column — confirm the sum query is right.
- Admin/app are different origins → if admin shows logged-out, use the password login card.

## Result
- [ ] All green → proceed to **expiry edge function + cron** (next build).
- [ ] Bugs found → log them here, fix before building more.
