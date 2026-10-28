-- Who may edit the Final Processing fields (payment voucher number, QBO
-- posting reference, payment status): any Finance Lead, and a Finance
-- Assistant when the requisition is assigned to them - raised by them,
-- cleared by them, forwarded to them, or theirs to review at Finance
-- (within their threshold). Previously, from Payment Processing on, only the
-- one Lead recorded on the requisition (or any Assistant) could.
create function finance_assistant_is_assigned(p_requisition_id uuid, p_actor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from requisitions r
     where r.id = p_requisition_id
       and (
         r.requester_id = p_actor_id
         or r.finance_accountant_id = p_actor_id
         or exists (select 1 from finance_assistant_forwards f where f.requisition_id = r.id and f.assistant_id = p_actor_id)
         or p_actor_id in (select get_eligible_approver_ids(r.id, 'finance'))
       )
  );
$$;

grant execute on function finance_assistant_is_assigned(uuid, uuid) to authenticated;

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
    old.estimated_amount is distinct from new.estimated_amount or
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
       or (
         old.status in ('finance_review', 'procurement_finance_review', 'approved_for_payment', 'paid_posted', 'posted_and_closed')
         or (old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage in ('finance_review', 'procurement_finance_review'))
       )
       and (
         -- Any Finance Lead; an Assistant only when it's assigned to them.
         auth_role() = 'finance_accountant'
         or (auth_role() = 'finance_assistant' and finance_assistant_is_assigned(old.id, auth.uid()))
       )
     ) then
    raise exception 'Not permitted to change Final Processing fields on requisition % in status %', old.id, old.status;
  end if;

  return new;
end;
$$;
