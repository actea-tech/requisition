-- The column GRANTs in migration 0008 are necessarily broad — Postgres
-- GRANT has no per-row conditions, so `authenticated` holds UPDATE on
-- finance_comments/payment_voucher_number/etc. across the board, and the
-- requisitions_update RLS policy only checks "is this row touchable by
-- this role right now", not "which columns is this UPDATE actually
-- changing". Combined, a staff member could write into Finance's or the
-- Director's fields on their own draft row — not a workflow-bypass like
-- the status issue fixed in 0008, but a real data-integrity gap for a
-- finance app. This trigger closes it by checking OLD vs NEW per column
-- group against who's allowed to change that group, and when.
--
-- The workflow engine (advance_stage/record_approval_action) never touches
-- any of these columns directly — it only ever writes status,
-- finance_cleared, director_decision, finance_accountant_id, director_id,
-- stage_entered_at — so this trigger doesn't need to special-case it.
create function enforce_field_write_scope()
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
     ) then
    raise exception 'Not permitted to change request/payment/budget fields on requisition % in status %', old.id, old.status;
  end if;

  if finance_review_fields_changed
     and not (auth_is_admin() or (auth_is_finance() and old.status = 'finance_review')) then
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

create trigger requisitions_enforce_field_write_scope
  before update on requisitions
  for each row execute function enforce_field_write_scope();
