-- Small non-secret config table (project URL, etc.) so trigger functions
-- don't hardcode values that might change across environments. Secrets
-- (the shared key used to authenticate calls into the send-email Edge
-- Function) live in Supabase Vault instead — see supabase/README.md.
create table app_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

insert into app_settings (key, value) values
  ('supabase_url', 'https://trpsghzizbnxewnellat.supabase.co'),
  ('app_url', 'http://localhost:3000');

create table email_templates (
  key text primary key,
  subject text not null,
  html_body text not null,
  updated_at timestamptz not null default now()
);

create trigger email_templates_set_updated_at
  before update on email_templates
  for each row execute function set_updated_at();

create table email_outbox (
  id uuid primary key default gen_random_uuid(),
  requisition_id uuid references requisitions (id) on delete cascade,
  template_key text not null references email_templates (key),
  to_emails text[] not null,
  cc_emails text[] not null default '{}',
  payload jsonb not null default '{}',
  status email_status not null default 'pending',
  attempts int not null default 0,
  error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index email_outbox_status_idx on email_outbox (status);
create index email_outbox_requisition_id_idx on email_outbox (requisition_id);

-- Enqueues one outbox row and fires the dispatch trigger below. Kept as a
-- SQL function (not just a raw insert) so every enqueue path — the workflow
-- engine, admin invites, future ad-hoc notifications — goes through one
-- place if we ever need to add dedupe/rate limiting.
create function enqueue_email(
  p_requisition_id uuid,
  p_template_key text,
  p_to_emails text[],
  p_payload jsonb default '{}',
  p_cc_emails text[] default '{}'
)
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  if p_to_emails is null or array_length(p_to_emails, 1) is null then
    return null;
  end if;

  insert into email_outbox (requisition_id, template_key, to_emails, cc_emails, payload)
  values (p_requisition_id, p_template_key, p_to_emails, p_cc_emails, p_payload)
  returning id into v_id;

  return v_id;
end;
$$;

-- Dispatches a newly-queued email to the send-email Edge Function via
-- pg_net. The Edge Function renders the template and calls Resend, then
-- updates this row's status — see supabase/functions/send-email.
create function dispatch_email_outbox()
returns trigger
language plpgsql
security definer
set search_path = public, net, vault
as $$
declare
  v_supabase_url text;
  v_service_key text;
begin
  select value into v_supabase_url from app_settings where key = 'supabase_url';
  select decrypted_secret into v_service_key from vault.decrypted_secrets where name = 'service_role_key' limit 1;

  if v_supabase_url is null or v_service_key is null then
    update email_outbox
      set status = 'failed', error = 'missing supabase_url app_setting or service_role_key vault secret'
      where id = new.id;
    return new;
  end if;

  perform net.http_post(
    url := v_supabase_url || '/functions/v1/send-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object('outbox_id', new.id)
  );

  return new;
end;
$$;

create trigger email_outbox_dispatch
  after insert on email_outbox
  for each row execute function dispatch_email_outbox();

-- Default ACTEA-branded templates. {{placeholders}} are filled by the
-- Edge Function from email_outbox.payload. Editable afterwards in
-- Settings > Email Templates without a migration.
insert into email_templates (key, subject, html_body) values
('account_invite', 'You''ve been added to ACTEA Requisitions', $html$
<p>Hi {{full_name}},</p>
<p>An administrator has created an ACTEA Requisitions account for you as <strong>{{role_label}}</strong>{{#department_name}} in the {{department_name}} department{{/department_name}}.</p>
<p><a href="{{invite_link}}" class="btn">Set your password</a></p>
<p>If you weren't expecting this, you can ignore this email.</p>
$html$),

('submitted', 'New requisition {{requisition_number}} awaiting your review', $html$
<p>Hello,</p>
<p><strong>{{requester_name}}</strong> ({{department_name}}) submitted requisition <strong>{{requisition_number}}</strong> for <strong>{{currency}} {{amount}}</strong>.</p>
<p>Purpose: {{purpose}}</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$),

('dept_returned', 'Requisition {{requisition_number}} returned for correction', $html$
<p>Hi {{requester_name}},</p>
<p>Your department head returned requisition <strong>{{requisition_number}}</strong> for correction:</p>
<blockquote>{{comments}}</blockquote>
<p><a href="{{requisition_link}}" class="btn">Update and resubmit</a></p>
$html$),

('dept_rejected', 'Requisition {{requisition_number}} was rejected', $html$
<p>Hi {{requester_name}},</p>
<p>Your department head rejected requisition <strong>{{requisition_number}}</strong>:</p>
<blockquote>{{comments}}</blockquote>
$html$),

('dept_approved', 'Requisition {{requisition_number}} ready for Finance review', $html$
<p>Hello,</p>
<p>Requisition <strong>{{requisition_number}}</strong> from {{requester_name}} ({{department_name}}) was approved at department level and needs Finance review.</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$),

('finance_returned', 'Requisition {{requisition_number}} returned by Finance', $html$
<p>Hi {{requester_name}},</p>
<p>Finance returned requisition <strong>{{requisition_number}}</strong> for correction:</p>
<blockquote>{{comments}}</blockquote>
<p><a href="{{requisition_link}}" class="btn">Update and resubmit</a></p>
$html$),

('finance_rejected', 'Requisition {{requisition_number}} was rejected by Finance', $html$
<p>Hi {{requester_name}},</p>
<p>Finance rejected requisition <strong>{{requisition_number}}</strong>:</p>
<blockquote>{{comments}}</blockquote>
$html$),

('finance_cleared', 'Requisition {{requisition_number}} cleared by Finance — authorization needed', $html$
<p>Hello,</p>
<p>Finance cleared requisition <strong>{{requisition_number}}</strong> from {{requester_name}} ({{department_name}}) for <strong>{{currency}} {{amount}}</strong>. It needs your authorization.</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$),

('director_returned', 'Requisition {{requisition_number}} returned by the Director', $html$
<p>Hi {{requester_name}},</p>
<p>The Director returned requisition <strong>{{requisition_number}}</strong> for correction:</p>
<blockquote>{{comments}}</blockquote>
<p><a href="{{requisition_link}}" class="btn">Update and resubmit</a></p>
$html$),

('director_rejected', 'Requisition {{requisition_number}} was rejected by the Director', $html$
<p>Hi {{requester_name}},</p>
<p>The Director rejected requisition <strong>{{requisition_number}}</strong>:</p>
<blockquote>{{comments}}</blockquote>
$html$),

('director_approved', 'Requisition {{requisition_number}} authorized — ready for payment processing', $html$
<p>Hello,</p>
<p>The Director authorized requisition <strong>{{requisition_number}}</strong> from {{requester_name}}. It's ready for payment processing.</p>
<p><a href="{{requisition_link}}" class="btn">Process payment</a></p>
$html$),

('paid_posted', 'Requisition {{requisition_number}} paid and closed', $html$
<p>Hi {{requester_name}},</p>
<p>Requisition <strong>{{requisition_number}}</strong> has been paid{{#qbo_posting_reference}} and posted in QuickBooks ({{qbo_posting_reference}}){{/qbo_posting_reference}}. Voucher: {{payment_voucher_number}}.</p>
<p><a href="{{requisition_link}}" class="btn">View requisition</a></p>
$html$);
