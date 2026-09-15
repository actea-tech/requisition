-- Fund requisitions: tell the requester they'll need to account for the
-- funds right in the "you've been paid" email, and let Finance send a
-- reminder if they haven't submitted yet. Also broadens the "Pending my
-- approval" dashboard count/list to include accounting reviews so Finance
-- sees them without a separate dashboard card.

-- The requester's own greeting was broken (used {{requester_name}}, never
-- present in this template's payload, instead of {{recipient_name}} —
-- migration 0016 fixed this same bug on 'submitted'/'dept_approved'/
-- 'finance_cleared'/'director_approved' but missed 'paid_posted'). Subject/
-- body also said "paid and closed" as a single event, no longer accurate
-- now that Paid and Posted & Closed are separate steps (migration 0044).
update email_templates set
  subject = 'Requisition {{requisition_number}} has been paid',
  html_body = $html$
<p>Hi {{recipient_name}},</p>
<p>Requisition <strong>{{requisition_number}}</strong> has been paid.{{#payment_voucher_number}} Voucher: {{payment_voucher_number}}.{{/payment_voucher_number}}{{#qbo_posting_reference}} QBO reference: {{qbo_posting_reference}}.{{/qbo_posting_reference}}</p>
{{#requires_accounting}}<p>Since this was a Fund/advance requisition, you'll need to account for how the funds were spent — add your expenditure lines and receipts, then submit for review.</p>{{/requires_accounting}}
<p><a href="{{requisition_link}}" class="btn">View requisition</a></p>
$html$
where key = 'paid_posted';

create or replace function notify_paid_posted(p_requisition_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_ids uuid[];
begin
  select * into r from requisitions where id = p_requisition_id;
  v_ids := array(select user_id from department_heads where department_id = r.department_id) || r.requester_id;

  perform enqueue_email_for_profiles(
    p_requisition_id, 'paid_posted', v_ids,
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'payment_voucher_number', r.payment_voucher_number,
      'qbo_posting_reference', r.qbo_posting_reference,
      'requisition_link', requisition_link(r.id),
      'requires_accounting', r.requisition_kind = 'fund'
    )
  );
end;
$$;

insert into email_templates (key, subject, html_body) values
('accounting_reminder', 'Reminder: expenditure accounting due for requisition {{requisition_number}}', $html$
<p>Hi {{recipient_name}},</p>
<p>This is a reminder that requisition <strong>{{requisition_number}}</strong> (<strong>{{currency}} {{amount}}</strong>) was paid, and we're still waiting on your expenditure accounting for it.</p>
<p><a href="{{requisition_link}}" class="btn">Submit accounting</a></p>
$html$)
on conflict (key) do nothing;

create function send_accounting_reminder(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
begin
  if not exists (
    select 1 from profiles where id = p_actor_id and is_active and role in ('finance_accountant', 'finance_assistant', 'admin')
  ) then
    raise exception 'Actor % is not permitted to send an accounting reminder', p_actor_id;
  end if;

  select * into r from requisitions where id = p_requisition_id;

  if r.requisition_kind <> 'fund' or r.status <> 'paid_posted' then
    raise exception 'Requisition % has no outstanding accounting to remind about', p_requisition_id;
  end if;

  perform notify_requester(p_requisition_id, 'accounting_reminder');
end;
$$;

grant execute on function send_accounting_reminder(uuid, uuid) to authenticated;

-- Reuse the existing "Pending my approval" dashboard count/list for
-- Finance's accounting reviews too, rather than a separate dashboard card —
-- same broad "any active finance_accountant/finance_assistant/admin" access
-- already established for approved_for_payment just above it.
create or replace function get_pending_approval_requisition_ids(p_user_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select r.id
    from requisitions r
   where r.requester_id <> p_user_id
     and r.status in ('dept_review', 'finance_review', 'director_review')
     and exists (
       select 1 from get_eligible_approver_ids(r.id, stage_key_for_status(r.status)) eid where eid = p_user_id
     )
     and not exists (
       select 1 from approval_actions aa
        where aa.requisition_id = r.id
          and aa.stage_key = stage_key_for_status(r.status)
          and aa.actor_id = p_user_id
          and aa.decision = 'approved'
          and aa.created_at >= r.stage_entered_at
     )

  union

  select r.id
    from requisitions r
   where r.requester_id <> p_user_id
     and r.status = 'approved_for_payment'
     and (
       r.finance_accountant_id = p_user_id
       or exists (
         select 1 from profiles
          where id = p_user_id and is_active and role in ('admin', 'finance_accountant', 'finance_assistant')
       )
     )

  union

  select r.id
    from requisitions r
   where r.requester_id <> p_user_id
     and r.status = 'accounting_review'
     and exists (
       select 1 from profiles
        where id = p_user_id and is_active and role in ('admin', 'finance_accountant', 'finance_assistant')
     )

  union

  select r.id
    from requisitions r
   where r.requester_id <> p_user_id
     and r.status = 'returned'
     and r.return_to = 'previous_stage'
     and r.returned_from_stage is not null
     and exists (
       select 1 from get_eligible_approver_ids(r.id, stage_key_for_status(r.returned_from_stage)) eid
        where eid = p_user_id
     );
$$;
