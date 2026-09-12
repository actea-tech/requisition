-- Per-currency cap on what a Finance Assistant can approve unassisted.
-- No threshold configured for a currency => not eligible via this path at
-- all (the safe default here is "capped", the opposite of the Director
-- threshold's "always required" default) — only forwarding (below) can
-- grant them eligibility on a specific requisition in that case.
create table finance_assistant_thresholds (
  currency text primary key,
  threshold_amount numeric(14,2) not null,
  updated_at timestamptz not null default now()
);

create trigger finance_assistant_thresholds_set_updated_at
  before update on finance_assistant_thresholds
  for each row execute function set_updated_at();

alter table finance_assistant_thresholds enable row level security;

create policy finance_assistant_thresholds_select on finance_assistant_thresholds for select to authenticated using (true);
create policy finance_assistant_thresholds_write on finance_assistant_thresholds for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());

grant select, insert, update, delete on finance_assistant_thresholds to authenticated;

-- Full delegation: forwarding a specific over-threshold requisition to a
-- specific Assistant makes them eligible for it (see get_eligible_
-- approver_ids below) same as any other eligible Finance approver — no
-- "all must approve" override the way finance_approver_group gets, so
-- under the default first-approver mode their approval alone resolves it.
create table finance_assistant_forwards (
  requisition_id uuid not null references requisitions (id) on delete cascade,
  assistant_id uuid not null references profiles (id),
  forwarded_by uuid references profiles (id),
  created_at timestamptz not null default now(),
  primary key (requisition_id, assistant_id)
);

alter table finance_assistant_forwards enable row level security;

create policy finance_assistant_forwards_select on finance_assistant_forwards for select to authenticated
  using (auth_is_finance() or auth_is_admin() or assistant_id = auth.uid());
create policy finance_assistant_forwards_write on finance_assistant_forwards for all to authenticated
  using (auth_role() = 'finance_accountant' or auth_is_admin())
  with check (auth_role() = 'finance_accountant' or auth_is_admin());

grant select, insert, delete on finance_assistant_forwards to authenticated;

create or replace function get_eligible_approver_ids(p_requisition_id uuid, p_stage_key approval_stage_key)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select dh.user_id
    from requisitions r
    join department_heads dh on dh.department_id = r.department_id
    join profiles p on p.id = dh.user_id and p.is_active
   where r.id = p_requisition_id and p_stage_key = 'department'
     and dh.user_id <> r.requester_id

  union

  select p.id
    from profiles p, requisitions r
   where p_stage_key = 'finance' and p.is_active and p.role = 'finance_accountant'
     and r.id = p_requisition_id and p.id <> r.requester_id

  union

  select p.id
    from profiles p, requisitions r
   where p_stage_key = 'finance' and p.is_active and p.role = 'finance_assistant'
     and r.id = p_requisition_id and p.id <> r.requester_id
     and (
       exists (
         select 1 from finance_assistant_thresholds fat
          where fat.currency = r.currency and r.amount <= fat.threshold_amount
       )
       or exists (
         select 1 from finance_assistant_forwards faf
          where faf.requisition_id = r.id and faf.assistant_id = p.id
       )
     )

  union

  select fag.user_id
    from finance_approver_group fag
    join profiles p on p.id = fag.user_id and p.is_active
    join requisitions r on r.id = fag.requisition_id
   where p_stage_key = 'finance' and fag.requisition_id = p_requisition_id
     and fag.user_id <> r.requester_id

  union

  select p.id
    from profiles p, requisitions r
   where p_stage_key = 'director' and p.is_active and p.role = 'director'
     and r.id = p_requisition_id and p.id <> r.requester_id;
$$;

-- Assistants who are over threshold (or unconfigured) and not forwarded
-- still get an FYI email whenever the eligible Finance recipients would —
-- covers stage-entry, Director/authorizer sending it back to Finance, and
-- any future call site, all through this one change point. So if the
-- Accountant misses something, an Assistant who's in the loop can flag it.
create or replace function notify_role_group(
  p_requisition_id uuid,
  p_stage_key approval_stage_key,
  p_template_key text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_payload jsonb;
begin
  select * into r from requisitions where id = p_requisition_id;
  v_payload := jsonb_build_object(
    'requisition_number', r.requisition_number,
    'requester_name', (select full_name from profiles where id = r.requester_id),
    'department_name', (select name from departments where id = r.department_id),
    'amount', r.amount,
    'currency', r.currency,
    'purpose', r.purpose,
    'requisition_link', requisition_link(r.id)
  );

  perform enqueue_email_for_profiles(
    p_requisition_id,
    p_template_key,
    array(select get_eligible_approver_ids(p_requisition_id, p_stage_key)),
    v_payload
  );

  if p_stage_key = 'finance' then
    perform enqueue_email_for_profiles(
      p_requisition_id,
      'finance_assistant_no_action_needed',
      array(
        select p.id from profiles p
         where p.role = 'finance_assistant' and p.is_active and p.id <> r.requester_id
           and p.id not in (select get_eligible_approver_ids(p_requisition_id, 'finance'))
      ),
      v_payload
    );
  end if;
end;
$$;

insert into email_templates (key, subject, html_body) values
('finance_assistant_no_action_needed', 'Requisition {{requisition_number}} at Finance — no action needed from you', $html$
<p>Hi {{recipient_name}},</p>
<p>Requisition <strong>{{requisition_number}}</strong> from {{requester_name}} ({{department_name}}) for <strong>{{currency}} {{amount}}</strong> has reached Finance review. It's above your current approval threshold, so no action is needed from you at this time — the Finance Accountant will handle it, or forward it to you if needed.</p>
<p><a href="{{requisition_link}}" class="btn">View requisition</a></p>
$html$)
on conflict (key) do nothing;
