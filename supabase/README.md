# Supabase setup

## Applying migrations

```bash
npx supabase login
npx supabase link --project-ref trpsghzizbnxewnellat
npx supabase db push
```

## One-time manual step: the email dispatch secret

Migration `0006_email_outbox_and_templates.sql` creates a Postgres trigger that calls the
`send-email` Edge Function via `pg_net` whenever a row is inserted into `email_outbox`. That call
is authenticated with your **service role key**, stored in Supabase Vault — not committed to this
repo. Set it once via the SQL Editor (Dashboard → SQL Editor) or the CLI:

```sql
select vault.create_secret('<your service role key>', 'service_role_key');
```

Get the service role key from Dashboard → Project Settings → API → `service_role` secret. This is
the same value you'll put in `.env.local` as `SUPABASE_SERVICE_ROLE_KEY` (server-only, never sent
to the browser).

## Deploying the Edge Function

```bash
npx supabase functions deploy send-email
npx supabase secrets set RESEND_API_KEY=<your resend api key>
npx supabase secrets set RESEND_FROM_EMAIL="ACTEA Requisitions <requisitions@yourdomain.org>"
```

`RESEND_FROM_EMAIL` must be on a domain you've verified in Resend (SPF/DKIM), or Resend will
reject the send.

## Bootstrapping the first admin

There's no public sign-up — every account is admin-provisioned. To create the very first admin
(who can then invite everyone else from Settings → Users), run once via the SQL Editor after
creating the auth user through Dashboard → Authentication → Users → Add user:

```sql
update profiles set role = 'admin' where email = 'you@acteaweb.org';
```

## Regenerating TypeScript types

After any migration change:

```bash
npx supabase gen types typescript --project-id trpsghzizbnxewnellat > ../lib/supabase/database.types.ts
```
