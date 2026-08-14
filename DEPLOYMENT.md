# Deploying to Hostinger

This is a Next.js 16 app built with `output: "standalone"` — `npm run build` produces a
self-contained `.next/standalone/server.js` plus its own trimmed `node_modules`, so the
deployed app doesn't need the full dev dependency tree on the server. `npm run build` also runs
a `postbuild` step that copies `public/` and `.next/static/` into the standalone folder (Next
excludes those by default, but the standalone server does need them to serve assets).

You told me your Hostinger plan is Business/Premium shared hosting. That tier includes a
**Node.js app manager** in hPanel (via Phusion Passenger) — this is the piece that actually runs
the server; confirm it's there under hPanel → Advanced → **Setup Node.js App** before going
further. If it's not on your plan, Next.js can't run as a persistent server there, and the
fallback would be a static export talking to Supabase directly (a different architecture — ask
me if you land here).

## Option A — hPanel's Git deploy (simplest, no SSH needed)

Hostinger's hPanel has a **Git** section (under Advanced) that connects directly to a GitHub
repo and branch, and can auto-pull on push.

1. Push this repo to GitHub (see below).
2. hPanel → Advanced → **Git** → connect the repo, branch `main`.
3. Set the deployment/build command to:
   ```
   npm install && npm run build
   ```
4. hPanel → Advanced → **Setup Node.js App**:
   - Application root: wherever the Git tool checked the repo out to
   - Application startup file: `.next/standalone/server.js`
   - Add the environment variables from `.env.example` (with real values) in the Node.js app's
     env var section — this is where `SUPABASE_SERVICE_ROLE_KEY` and `NEXT_PUBLIC_APP_URL` (set
     to your real domain) go. Never put the service role key in `.env.local` committed to git —
     it isn't, but double-check before any commit that touches env files.
5. Restart the app from hPanel after each deploy (or set hPanel's Git tool to do it
   automatically if it offers that option).

## Option B — GitHub Actions + SSH (if your plan includes SSH access)

`.github/workflows/deploy.yml` is already set up for this (rsyncs `.next/standalone/` to the
server, then touches `tmp/restart.txt` — Passenger's soft-restart convention). It only runs when
you manually trigger it (Actions tab → Deploy to Hostinger → Run workflow), not on every push,
since it needs these repo secrets first (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://trpsghzizbnxewnellat.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | your publishable key |
| `NEXT_PUBLIC_APP_URL` | your real domain, e.g. `https://requisitions.acteaweb.org` |
| `HOSTINGER_SSH_HOST` | SSH host from hPanel → Advanced → SSH Access |
| `HOSTINGER_SSH_PORT` | usually `65002` on Hostinger shared plans |
| `HOSTINGER_SSH_USER` | your SSH username |
| `HOSTINGER_SSH_KEY` | a private key whose matching public key you've added in hPanel → SSH Access |
| `HOSTINGER_APP_PATH` | absolute path to the app directory on the server |

Once it's worked once, you can add `push: { branches: [main] }` to `deploy.yml`'s `on:` block to
auto-deploy on every push to main.

## Getting this repo onto GitHub

I don't have a GitHub CLI session or a remote configured yet. Tell me:
1. Do you already have a GitHub repo created for this, or should I create one?
2. If I should create one: what account/org, and what visibility (private strongly
   recommended — this handles real financial data)?

Once I know that, I'll add the remote and push.
