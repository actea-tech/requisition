-- 1. Dynamic "return to" target + re-approval choice ------------------------
alter table requisitions add column return_to text not null default 'requester'
  check (return_to in ('requester', 'previous_stage'));
alter table requisitions add column requires_reapproval boolean not null default true;

-- 2. Per-recipient email dispatch (fixes generic "Hello," with no name: one
-- email_outbox row per recipient now, each with its own recipient_name,
-- instead of one row with every recipient crammed into `to_emails` sharing
-- one greeting and seeing each other's addresses).
create function enqueue_email_for_profiles(
  p_requisition_id uuid,
  p_template_key text,
  p_profile_ids uuid[],
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
begin
  for rec in select id, email, full_name from profiles where id = any(p_profile_ids) and is_active loop
    perform enqueue_email(
      p_requisition_id, p_template_key, array[rec.email],
      p_payload || jsonb_build_object('recipient_name', rec.full_name)
    );
  end loop;
end;
$$;

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
begin
  select * into r from requisitions where id = p_requisition_id;
  perform enqueue_email_for_profiles(
    p_requisition_id,
    p_template_key,
    array(select get_eligible_approver_ids(p_requisition_id, p_stage_key)),
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'requester_name', (select full_name from profiles where id = r.requester_id),
      'department_name', (select name from departments where id = r.department_id),
      'amount', r.amount,
      'currency', r.currency,
      'purpose', r.purpose,
      'requisition_link', requisition_link(r.id)
    )
  );
end;
$$;

create or replace function notify_director_approved(p_requisition_id uuid)
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
  v_ids := case
    when r.finance_accountant_id is not null then array[r.finance_accountant_id]
    else array(select id from profiles where role = 'finance_accountant' and is_active)
  end;

  perform enqueue_email_for_profiles(
    p_requisition_id, 'director_approved', v_ids,
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'requester_name', (select full_name from profiles where id = r.requester_id),
      'requisition_link', requisition_link(r.id)
    )
  );
end;
$$;

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
      'requisition_link', requisition_link(r.id)
    )
  );
end;
$$;

-- notify_requester already targets exactly one person; just add
-- recipient_name so its templates can use the same {{recipient_name}}
-- placeholder as the group ones.
create or replace function notify_requester(
  p_requisition_id uuid,
  p_template_key text,
  p_comments text default null,
  p_extra_to_emails text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_to_emails text[];
  v_requester_name text;
begin
  select * into r from requisitions where id = p_requisition_id;
  select full_name into v_requester_name from profiles where id = r.requester_id;
  select array_append(p_extra_to_emails, email) into v_to_emails from profiles where id = r.requester_id;

  perform enqueue_email(
    p_requisition_id,
    p_template_key,
    v_to_emails,
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'requester_name', v_requester_name,
      'recipient_name', v_requester_name,
      'department_name', (select name from departments where id = r.department_id),
      'amount', r.amount,
      'currency', r.currency,
      'purpose', r.purpose,
      'comments', p_comments,
      'requisition_link', requisition_link(r.id)
    )
  );
end;
$$;

update email_templates set html_body = replace(html_body, '<p>Hello,</p>', '<p>Hi {{recipient_name}},</p>')
  where key in ('submitted', 'dept_approved', 'finance_cleared', 'director_approved');
update email_templates set html_body = replace(html_body, '<p>Hi {{requester_name}},</p>', '<p>Hi {{recipient_name}},</p>')
  where key = 'paid_posted';

insert into email_templates (key, subject, html_body) values
('stage_returned', 'Requisition {{requisition_number}} sent back to you for correction', $html$
<p>Hi {{recipient_name}},</p>
<p>Requisition <strong>{{requisition_number}}</strong> from {{requester_name}} was sent back to you for correction before it can continue.</p>
{{#comments}}<blockquote>{{comments}}</blockquote>{{/comments}}
<p><a href="{{requisition_link}}" class="btn">Review and resubmit</a></p>
$html$),
('return_fyi', 'Requisition {{requisition_number}} returned for correction', $html$
<p>Hi {{recipient_name}},</p>
<p>Requisition <strong>{{requisition_number}}</strong> from {{requester_name}} was returned for correction. No action is needed from you right now.</p>
{{#comments}}<blockquote>{{comments}}</blockquote>{{/comments}}
$html$)
on conflict (key) do update set subject = excluded.subject, html_body = excluded.html_body;

-- 3. Dynamic return target + re-approval logic -------------------------------
drop function record_approval_action(uuid, uuid, approval_decision, text);

create function record_approval_action(
  p_requisition_id uuid,
  p_actor_id uuid,
  p_decision approval_decision,
  p_comments text default null,
  p_return_to text default 'requester',
  p_requires_reapproval boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_stage_key approval_stage_key;
begin
  select status into v_status from requisitions where id = p_requisition_id;
  v_stage_key := stage_key_for_status(v_status);

  if v_stage_key is null then
    raise exception 'Requisition % is not awaiting approval (status: %)', p_requisition_id, v_status;
  end if;

  if p_decision = 'completed' then
    if v_stage_key <> 'payment' then
      raise exception 'Requisition % is not ready for payment completion', p_requisition_id;
    end if;
    if not exists (
      select 1 from profiles where id = p_actor_id and is_active and role in ('finance_accountant', 'admin')
    ) then
      raise exception 'Actor % is not permitted to complete payment processing', p_actor_id;
    end if;
  end if;

  if p_decision = 'returned' and p_return_to = 'previous_stage' and v_stage_key = 'department' then
    raise exception 'There is no earlier stage to return to from department review';
  end if;

  if p_decision in ('approved', 'returned', 'rejected')
     and not exists (
       select 1 from get_eligible_approver_ids(p_requisition_id, v_stage_key) id where id = p_actor_id
     )
     and not exists (
       select 1 from profiles where id = p_actor_id and is_active and role = 'admin'
     ) then
    raise exception 'Actor % is not an eligible approver for requisition % at stage %', p_actor_id, p_requisition_id, v_stage_key;
  end if;

  if p_decision = 'returned' then
    update requisitions set return_to = p_return_to, requires_reapproval = p_requires_reapproval
      where id = p_requisition_id;
  end if;

  if v_stage_key = 'finance' then
    update requisitions
      set finance_accountant_id = p_actor_id
      where id = p_requisition_id
        and finance_accountant_id is null
        and exists (select 1 from profiles where id = p_actor_id and role = 'finance_accountant');
  elsif v_stage_key = 'director' then
    update requisitions
      set director_id = p_actor_id
      where id = p_requisition_id and director_id is null;
  end if;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
  values (p_requisition_id, v_stage_key, p_actor_id, p_decision, p_comments);
end;
$$;

grant execute on function record_approval_action(uuid, uuid, approval_decision, text, text, boolean) to authenticated;

create or replace function evaluate_stage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eligible_count int;
  v_approved_count int;
  v_mode approval_mode;
  v_quorum int;
  v_department_id uuid;
  v_stage_entered_at timestamptz;
  v_resolved boolean;
  v_return_to text;
  v_requires_reapproval boolean;
  v_current_status requisition_status;
  v_target_status requisition_status;
begin
  if new.decision = 'submitted' then
    case new.stage_key
      when 'department' then perform notify_role_group(new.requisition_id, 'department', 'submitted');
      when 'finance' then perform notify_role_group(new.requisition_id, 'finance', 'dept_approved');
      when 'director' then perform notify_role_group(new.requisition_id, 'director', 'finance_cleared');
      else null;
    end case;
    return new;
  end if;

  if new.decision = 'rejected' then
    update requisitions set status = 'rejected' where id = new.requisition_id;
    perform notify_requester(
      new.requisition_id,
      case new.stage_key
        when 'department' then 'dept_rejected'
        when 'finance' then 'finance_rejected'
        when 'director' then 'director_rejected'
      end,
      new.comments
    );
    return new;
  end if;

  if new.decision = 'returned' then
    select return_to, requires_reapproval, status into v_return_to, v_requires_reapproval, v_current_status
      from requisitions where id = new.requisition_id;

    -- "Return to previous stage" always lands on that specific stage.
    -- Otherwise (back to the requester), "requires re-approval" sends it
    -- all the way to department review; unchecked, it resumes at the same
    -- stage that returned it (today's original behavior) rather than
    -- re-collecting approvals that already happened.
    v_target_status := case
      when new.stage_key = 'finance' and v_return_to = 'previous_stage' then 'dept_review'
      when new.stage_key = 'director' and v_return_to = 'previous_stage' then 'finance_review'
      when v_requires_reapproval then 'dept_review'
      else v_current_status
    end;

    update requisitions
      set returned_from_stage = v_target_status, status = 'returned', return_reason = new.comments
      where id = new.requisition_id;

    if v_return_to = 'previous_stage' and new.stage_key = 'finance' then
      perform notify_role_group(new.requisition_id, 'department', 'stage_returned');
      perform notify_requester(new.requisition_id, 'return_fyi', new.comments);
    elsif v_return_to = 'previous_stage' and new.stage_key = 'director' then
      perform notify_role_group(new.requisition_id, 'finance', 'stage_returned');
      perform notify_requester(new.requisition_id, 'return_fyi', new.comments);
    else
      perform notify_requester(
        new.requisition_id,
        case new.stage_key
          when 'department' then 'dept_returned'
          when 'finance' then 'finance_returned'
          when 'director' then 'director_returned'
        end,
        new.comments
      );
      if new.stage_key in ('finance', 'director') then
        perform notify_role_group(new.requisition_id, 'department', 'return_fyi');
      end if;
      if new.stage_key = 'director' then
        perform notify_role_group(new.requisition_id, 'finance', 'return_fyi');
      end if;
    end if;

    return new;
  end if;

  if new.decision = 'completed' then
    update requisitions set status = 'paid_posted' where id = new.requisition_id;
    perform notify_paid_posted(new.requisition_id);
    return new;
  end if;

  if new.decision = 'approved' then
    select department_id, stage_entered_at into v_department_id, v_stage_entered_at
      from requisitions where id = new.requisition_id;

    v_eligible_count := (select count(*) from get_eligible_approver_ids(new.requisition_id, new.stage_key));
    select mode, quorum_count into v_mode, v_quorum from get_stage_mode(v_department_id, new.stage_key);

    select count(distinct actor_id) into v_approved_count
      from approval_actions
     where requisition_id = new.requisition_id
       and stage_key = new.stage_key
       and decision = 'approved'
       and created_at >= v_stage_entered_at;

    v_resolved := case
      when v_eligible_count <= 1 then true
      when v_mode = 'first_approver' then true
      when v_mode = 'all_approvers' then v_approved_count >= v_eligible_count
      when v_mode = 'quorum' then v_approved_count >= coalesce(v_quorum, v_eligible_count)
      else true
    end;

    if v_resolved then
      perform advance_stage(new.requisition_id, new.stage_key);
    end if;
  end if;

  return new;
end;
$$;

-- 4. Let the "return to previous stage" target actually edit + resubmit -----
drop policy requisitions_update on requisitions;
create policy requisitions_update on requisitions for update to authenticated
  using (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_is_dept_head_of(department_id) and status = 'dept_review')
    or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'dept_review')
    or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
  )
  with check (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_is_dept_head_of(department_id) and status = 'dept_review')
    or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'dept_review')
    or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
  );

create or replace function enforce_field_write_scope()
returns trigger
language plpgsql
as $$
declare
  requester_fields_changed boolean;
  finance_review_fields_changed boolean;
  director_fields_changed boolean;
  final_processing_fields_changed boolean;
begin
  requester_fields_changed := (
    old.purpose is distinct from new.purpose or
    old.activity_project is distinct from new.activity_project or
    old.payee_name is distinct from new.payee_name or
    old.payee_contact is distinct from new.payee_contact or
    old.amount is distinct from new.amount or
    old.currency is distinct from new.currency or
    old.payment_mode is distinct from new.payment_mode or
    old.budget_line is distinct from new.budget_line or
    old.account_code is distinct from new.account_code or
    old.project_fund_class_code is distinct from new.project_fund_class_code or
    old.donor_grant_source is distinct from new.donor_grant_source or
    old.budgeted is distinct from new.budgeted or
    old.procurement_required is distinct from new.procurement_required or
    old.donor_restriction is distinct from new.donor_restriction or
    old.outstanding_advance is distinct from new.outstanding_advance
  );

  finance_review_fields_changed := (
    old.finance_comments is distinct from new.finance_comments or
    old.budget_available is distinct from new.budget_available
  );

  director_fields_changed := old.director_comments is distinct from new.director_comments;

  final_processing_fields_changed := (
    old.payment_voucher_number is distinct from new.payment_voucher_number or
    old.qbo_posting_reference is distinct from new.qbo_posting_reference or
    old.payment_status is distinct from new.payment_status
  );

  if requester_fields_changed
     and not (
       auth_is_admin()
       or (old.requester_id = auth.uid() and old.status in ('draft', 'returned'))
       or (auth_is_finance() and old.status = 'finance_review')
       or (auth_is_dept_head_of(old.department_id) and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage = 'dept_review')
       or (auth_is_finance() and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage = 'finance_review')
     ) then
    raise exception 'Not permitted to change request/payment/budget fields on requisition % in status %', old.id, old.status;
  end if;

  if finance_review_fields_changed
     and not (
       auth_is_admin()
       or (auth_is_finance() and old.status = 'finance_review')
       or (auth_is_finance() and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage = 'finance_review')
     ) then
    raise exception 'Not permitted to change Finance Review fields on requisition % in status %', old.id, old.status;
  end if;

  if director_fields_changed
     and not (auth_is_admin() or (auth_role() = 'director' and old.status = 'director_review')) then
    raise exception 'Not permitted to change Director fields on requisition % in status %', old.id, old.status;
  end if;

  if final_processing_fields_changed
     and not (
       auth_is_admin()
       or (old.status = 'approved_for_payment' and old.finance_accountant_id = auth.uid())
     ) then
    raise exception 'Not permitted to change Final Processing fields on requisition % in status %', old.id, old.status;
  end if;

  return new;
end;
$$;
