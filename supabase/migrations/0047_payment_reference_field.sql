-- Optional field for the Accountant/Assistant to record how a payment was
-- actually executed once it's been sent (M-Pesa code, bank transfer
-- reference, cheque number, ...) — a single generic field rather than one
-- per payment mode, kept optional throughout.
alter table requisitions add column payment_reference text;
grant update (payment_reference) on requisitions to authenticated;

insert into form_field_config (section, field_key, label, help_text, is_required, sort_order) values
  ('final_processing', 'payment_reference', 'Payment reference',
   'Optional — e.g. M-Pesa code, bank transfer reference, or cheque number, whichever applies to this payment''s mode.',
   false, 4);

-- Found while adding the field above: enforce_field_write_scope() was
-- never updated for the "full delegation" broadening (migration 0042) that
-- let any active finance_accountant/finance_assistant use Final Processing
-- at the app/RLS layer — it still only accepted the specific
-- finance_accountant_id on the row (or admin), so a forwarded or
-- threshold-eligible Assistant who isn't that exact person could open the
-- panel but their save silently failed here. Same bug, same root cause
-- (auth_is_finance() excludes finance_assistant), on the Finance Review
-- and request/budget fields checks too — broadened all three while
-- rewriting this function, since a partial redefinition isn't possible.
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
    old.payment_status is distinct from new.payment_status or
    old.payment_reference is distinct from new.payment_reference
  );

  if requester_fields_changed
     and not (
       auth_is_admin()
       or (old.requester_id = auth.uid() and old.status in ('draft', 'returned'))
       or ((auth_is_finance() or auth_role() = 'finance_assistant') and old.status = 'finance_review')
       or (auth_is_dept_head_of(old.department_id) and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage = 'dept_review')
       or ((auth_is_finance() or auth_role() = 'finance_assistant') and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage = 'finance_review')
     ) then
    raise exception 'Not permitted to change request/payment/budget fields on requisition % in status %', old.id, old.status;
  end if;

  if finance_review_fields_changed
     and not (
       auth_is_admin()
       or ((auth_is_finance() or auth_role() = 'finance_assistant') and old.status = 'finance_review')
       or ((auth_is_finance() or auth_role() = 'finance_assistant') and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage = 'finance_review')
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
       or (old.status = 'approved_for_payment' and auth_role() in ('finance_accountant', 'finance_assistant'))
     ) then
    raise exception 'Not permitted to change Final Processing fields on requisition % in status %', old.id, old.status;
  end if;

  return new;
end;
$$;
