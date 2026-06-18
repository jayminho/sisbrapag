# SISBRAPAG — Project Instructions

## ⚠️ ALWAYS DEPLOY, NEVER LEAVE CHANGES LOCAL-ONLY

This is the #1 rule for this project. A code change is **not done** until it is
live on the production site. Editing a file in the local folder changes nothing
that the user can see — the live site (`www.sisbrapag.com`) serves the *deployed*
version, not the local file.

**After making ANY code change, you MUST deploy it.** Do not end your turn saying
"fixed" until the change is committed, pushed, and verified live. If you cannot
deploy for some reason, say so explicitly and loudly — do not imply it's live.

---

## How deployment works here

| Layer | What it is | How it deploys |
|-------|-----------|----------------|
| **Frontend** (`*.html`) | Static HTML/JS, no build step | Push to GitHub `main` → Vercel auto-deploys in ~30s |
| **GitHub** | `https://github.com/jayminho/sisbrapag.git`, branch `main` | `git commit` + `git push` |
| **Vercel** | Hosts the site, auto-deploys on push to `main` | Automatic — no manual step needed after push |
| **Supabase** | DB + edge functions in `supabase/functions/` | Edge functions deploy via Supabase MCP `deploy_edge_function` or `supabase functions deploy <name>`; SQL via `apply_migration` / `execute_sql` |

**Live domain:** the bare domain `sisbrapag.com` 308-redirects to **`www.sisbrapag.com`**.
Always test and verify against the `www` URL. App subdomain: `app.sisbrapag.com` → `/dashboard.html`.

---

## Standard frontend deploy procedure

Run git on the **user's real machine via Desktop Commander** (start_process), NOT
the sandbox bash — the sandbox has no GitHub credentials and cannot push.

```bash
cd ~/grok-projects/sisbrapag
rm -f .git/index.lock .git/HEAD.lock   # clear stale locks from any prior failed attempt
git add <files>
git commit -m "fix: <description>"
git push
```

Then **verify it actually went live** (wait ~40s for Vercel, then curl the www URL):

```bash
curl -sL "https://www.sisbrapag.com/dashboard.html?cb=$(date +%s)" | grep -c "<new code marker>"
```

Confirm the old/broken code is gone (count 0) and the new code is present (count ≥ 1).

## Supabase edge function deploy

After editing anything in `supabase/functions/<name>/`, redeploy that function —
a local edit does nothing until deployed. Use the Supabase MCP `deploy_edge_function`
tool (or `supabase functions deploy <name>` via Desktop Commander).

---

## Gotchas learned the hard way

- **Sandbox bash cannot push** (no GitHub auth, and it hits "Operation not permitted"
  on `.git` lock files). Always use **Desktop Commander** for git operations.
- **Stale lock files** (`.git/index.lock`, `.git/HEAD.lock`) from a failed sandbox
  attempt will block commits. Remove them first.
- **Hard-refresh ≠ deploy.** If the user reports "still broken after refresh," the
  most likely cause is the change was never deployed, not browser cache.
- **Test the `www` URL**, not the bare domain (which only returns a redirect stub).
