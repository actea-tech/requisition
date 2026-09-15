-- Bespoke pair of RPCs rather than routing through the generic
-- record_approval_action/evaluate_stage/get_eligible_approver_ids engine —
-- this is a single-submitter/single-reviewer side-flow, not a
-- multi-approver stage, the same reasoning that already justified
-- cancel_requisition/decide_cancellation being their own thing.
create function submit_requisition_accounting(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_finance_ids uuid[];
begin
  select * into r from requisitions where id = p_requisition_id;

  if r.requester_id <> p_actor_id then
    raise exception 'Actor % is not the requester for requisition %', p_actor_id, p_requisition_id;
  end if;

  if r.requisition_kind <> 'fund' then
    raise exception 'Requisition % is not a Fund requisition', p_requisition_id;
  end if;

  if r.status <> 'paid_posted' then
    raise exception 'Requisition % is not ready for an accounting submission (status: %)', p_requisition_id, r.status;
  end if;

  if not exists (
    select 1 from requisition_expenditures where requisition_id = p_requisition_id and entry_type = 'expense'
  ) then
    raise exception 'Add at least one expenditure line before submitting';
  end if;

  update requisitions set status = 'accounting_review' where id = p_requisition_id;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision)
  values (p_requisition_id, 'payment', p_actor_id, 'accounting_submitted');

  v_finance_ids := (
    case
      when r.finance_accountant_id is not null then array[r.finance_accountant_id]
      else array(select id from profiles where role = 'finance_accountant' and is_active)
    end
  ) || array(select id from profiles where role = 'finance_assistant' and is_active);

  perform enqueue_email_for_profiles(
    p_requisition_id, 'accounting_submitted', v_finance_ids,
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'requester_name', (select full_name from profiles where id = r.requester_id),
      'amount', r.amount,
      'currency', r.currency,
      'requisition_link', requisition_link(p_requisition_id)
    )
  );
end;
$$;

grant execute on function submit_requisition_accounting(uuid, uuid) to authenticated;

create function review_requisition_accounting(
  p_requisition_id uuid,
  p_actor_id uuid,
  p_approve boolean,
  p_comments text default null,
  p_shortfall_note text default null
)
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
    raise exception 'Actor % is not permitted to review an accounting submission', p_actor_id;
  end if;

  select * into r from requisitions where id = p_requisition_id;

  if r.status <> 'accounting_review' then
    raise exception 'Requisition % has no accounting submission awaiting review (status: %)', p_requisition_id, r.status;
  end if;

  if p_approve then
    -- Approving the accounting *is* the closing act for a Fund
    -- requisition — there's nothing further to post once it's reconciled.
    update requisitions
      set status = 'posted_and_closed',
          accounting_shortfall_note = coalesce(p_shortfall_note, accounting_shortfall_note)
      where id = p_requisition_id;

    insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
    values (p_requisition_id, 'payment', p_actor_id, 'accounting_approved', p_comments);

    perform notify_requester(p_requisition_id, 'accounting_approved', p_comments);
  else
    update requisitions set status = 'paid_posted' where id = p_requisition_id;

    insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
    values (p_requisition_id, 'payment', p_actor_id, 'accounting_returned', p_comments);

    perform notify_requester(p_requisition_id, 'accounting_returned', p_comments);
  end if;
end;
$$;

grant execute on function review_requisition_accounting(uuid, uuid, boolean, text, text) to authenticated;

insert into email_templates (key, subject, html_body) values
('accounting_submitted', 'Expenditure accounting submitted for requisition {{requisition_number}}', $html$
<p>Hi {{recipient_name}},</p>
<p>{{requester_name}} submitted their expenditure accounting for requisition <strong>{{requisition_number}}</strong>
(<strong>{{currency}} {{amount}}</strong>) — it's ready for your review.</p>
<p><a href="{{requisition_link}}" class="btn">Review accounting</a></p>
$html$),
('accounting_approved', 'Requisition {{requisition_number}} accounting approved — closed', $html$
<p>Hi {{recipient_name}},</p>
<p>Your expenditure accounting for requisition <strong>{{requisition_number}}</strong> was approved. It's now
posted and closed.</p>
{{#comments}}<blockquote>{{comments}}</blockquote>{{/comments}}
<p><a href="{{requisition_link}}" class="btn">View requisition</a></p>
$html$),
('accounting_returned', 'Requisition {{requisition_number}} accounting needs correction', $html$
<p>Hi {{recipient_name}},</p>
<p>Finance sent your expenditure accounting for requisition <strong>{{requisition_number}}</strong> back for
correction:</p>
<blockquote>{{comments}}</blockquote>
<p><a href="{{requisition_link}}" class="btn">Update accounting</a></p>
$html$)
on conflict (key) do nothing;
