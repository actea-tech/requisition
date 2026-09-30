-- Every place that gates on the literal status 'dept_review'/'finance_review'
-- (not just role/membership) needs the procurement equivalent added
-- alongside it — get_eligible_approver_ids/auth_is_dept_head_of/etc. all
-- key off stage_key already and need no changes.

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
     and r.status in ('dept_review', 'finance_review', 'director_review', 'procurement_dept_review', 'procurement_finance_review')
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
     and exists (select 1 from profiles me where me.id = p_user_id and me.is_test_user = r.is_test)
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
     and exists (select 1 from profiles me where me.id = p_user_id and me.is_test_user = r.is_test)
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

drop policy requisitions_update on requisitions;
create policy requisitions_update on requisitions for update to authenticated
  using (
    auth_is_admin()
    or (
      is_test = auth_is_test_user()
      and (
        (requester_id = auth.uid() and status in ('draft', 'returned', 'awaiting_invoice'))
        or (auth_is_finance() and status in ('finance_review', 'procurement_finance_review', 'approved_for_payment'))
        or (auth_role() = 'director' and status = 'director_review')
        or (auth_is_requisition_authorizer(id) and status = 'director_review')
        or (auth_is_dept_head_of(department_id) and status in ('dept_review', 'procurement_dept_review'))
        or (auth_is_finance_group_member(id) and status in ('finance_review', 'procurement_finance_review'))
        or (auth_is_forwarded_assistant(id) and status in ('finance_review', 'approved_for_payment'))
        or (auth_role() = 'finance_assistant' and status = 'approved_for_payment')
        or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage in ('dept_review', 'procurement_dept_review'))
        or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage in ('finance_review', 'procurement_finance_review'))
        or (auth_is_finance_group_member(id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage in ('finance_review', 'procurement_finance_review'))
      )
    )
  )
  with check (
    auth_is_admin()
    or (
      is_test = auth_is_test_user()
      and (
        (requester_id = auth.uid() and status in ('draft', 'returned', 'awaiting_invoice'))
        or (auth_is_finance() and status in ('finance_review', 'procurement_finance_review', 'approved_for_payment'))
        or (auth_role() = 'director' and status = 'director_review')
        or (auth_is_requisition_authorizer(id) and status = 'director_review')
        or (auth_is_dept_head_of(department_id) and status in ('dept_review', 'procurement_dept_review'))
        or (auth_is_finance_group_member(id) and status in ('finance_review', 'procurement_finance_review'))
        or (auth_is_forwarded_assistant(id) and status in ('finance_review', 'approved_for_payment'))
        or (auth_role() = 'finance_assistant' and status = 'approved_for_payment')
        or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage in ('dept_review', 'procurement_dept_review'))
        or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage in ('finance_review', 'procurement_finance_review'))
        or (auth_is_finance_group_member(id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage in ('finance_review', 'procurement_finance_review'))
      )
    )
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
    old.requisition_type is distinct from new.requisition_type or
    old.requisition_kind is distinct from new.requisition_kind or
    old.purpose is distinct from new.purpose or
    old.activity_project is distinct from new.activity_project or
    old.payee_name is distinct from new.payee_name or
    old.payee_contact is distinct from new.payee_contact or
    old.amount is distinct from new.amount or
    old.currency is distinct from new.currency or
    old.payment_mode is distinct from new.payment_mode or
    old.payment_mode_details is distinct from new.payment_mode_details or
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
       or (old.requester_id = auth.uid() and old.status in ('draft', 'returned', 'awaiting_invoice'))
       or (auth_is_finance() and old.status in ('finance_review', 'procurement_finance_review'))
       or (auth_is_dept_head_of(old.department_id) and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage in ('dept_review', 'procurement_dept_review'))
       or (auth_is_finance() and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage in ('finance_review', 'procurement_finance_review'))
     ) then
    raise exception 'Not permitted to change request/payment/budget fields on requisition % in status %', old.id, old.status;
  end if;

  if finance_review_fields_changed
     and not (
       auth_is_admin()
       or (auth_is_finance() and old.status in ('finance_review', 'procurement_finance_review'))
       or (auth_is_finance() and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage in ('finance_review', 'procurement_finance_review'))
     ) then
    raise exception 'Not permitted to change Finance Review fields on requisition % in status %', old.id, old.status;
  end if;

  if director_fields_changed
     and not (
       auth_is_admin()
       or (auth_role() = 'director' and old.status = 'director_review')
       or (auth_is_requisition_authorizer(old.id) and old.status = 'director_review')
     ) then
    raise exception 'Not permitted to change Director fields on requisition % in status %', old.id, old.status;
  end if;

  if final_processing_fields_changed
     and not (
       auth_is_admin()
       or (old.status = 'approved_for_payment' and (old.finance_accountant_id = auth.uid() or auth_role() = 'finance_assistant'))
     ) then
    raise exception 'Not permitted to change Final Processing fields on requisition % in status %', old.id, old.status;
  end if;

  return new;
end;
$$;

-- evaluate_stage's 'returned' branch: stage_key = 'finance' now covers two
-- distinct statuses for a procurement requisition (its own first-pass
-- procurement_finance_review, and the ordinary finance_review post-
-- invoice) — check the row's actual current status to pick the right
-- "previous stage"/reapproval target. Once a procurement item is back at
-- the *ordinary* finance_review, it's treated exactly like a Payment
-- requisition (targets plain dept_review) — see plan notes on this corner.
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
  v_req_type requisition_scope;
  v_requester_id uuid;
begin
  if new.decision = 'submitted' then
    case new.stage_key
      when 'department' then perform notify_role_group(new.requisition_id, 'department', 'submitted');
      when 'finance' then
        select requisition_type, department_id, requester_id
          into v_req_type, v_department_id, v_requester_id
          from requisitions where id = new.requisition_id;
        perform notify_role_group(
          new.requisition_id, 'finance',
          case
            when v_req_type in ('individual', 'finance_direct') then 'individual_submitted'
            when v_req_type = 'departmental'
                 and exists (select 1 from department_heads where department_id = v_department_id and user_id = v_requester_id)
              then 'individual_submitted'
            else 'dept_approved'
          end
        );
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

    v_target_status := case
      when new.stage_key = 'finance' and v_return_to = 'previous_stage' then
        (case when v_current_status = 'procurement_finance_review' then 'procurement_dept_review' else 'dept_review' end)
      when new.stage_key = 'director' and v_return_to = 'previous_stage' then 'finance_review'
      when v_requires_reapproval then
        (case when v_current_status in ('procurement_dept_review', 'procurement_finance_review') then 'procurement_dept_review' else 'dept_review' end)
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
      when new.stage_key = 'finance'
           and exists (select 1 from finance_approver_group where requisition_id = new.requisition_id)
        then v_approved_count >= v_eligible_count
      when new.stage_key = 'director'
           and exists (select 1 from requisition_authorizers where requisition_id = new.requisition_id)
        then v_approved_count >= v_eligible_count
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
