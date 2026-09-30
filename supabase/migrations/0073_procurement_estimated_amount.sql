-- The procurement stage reused "amount" for both the pre-invoice estimate
-- and the real invoice amount — editing an approved figure in place lost
-- the original estimate and gave Finance nothing to compare the real
-- invoice against. estimated_amount is now its own column: always optional,
-- editable only pre-invoice, and kept (locked) for reference afterward.
-- "amount" itself now stays empty until the real invoice exists and is
-- required to submit it (see submit_procurement_invoice below).
alter table requisitions add column estimated_amount numeric;

insert into form_field_config (section, field_key, label, help_text, is_required, sort_order) values
  ('payment_details', 'estimated_amount', 'Estimated amount', 'Approximate cost at the procurement stage — the real amount is added once the invoice is available.', false, 0)
on conflict (section, field_key) do nothing;

-- estimated_amount is a requester-facing field, edited the same way and on
-- the same schedule as the rest of Payment Details (payee_name/amount/etc)
-- — fold it into that existing changed-fields group rather than adding a
-- new one.
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
       or (old.status = 'approved_for_payment' and (old.finance_accountant_id = auth.uid() or auth_role() = 'finance_assistant'))
     ) then
    raise exception 'Not permitted to change Final Processing fields on requisition % in status %', old.id, old.status;
  end if;

  return new;
end;
$$;

-- Applying for payment (submitting the invoice) now requires a real amount
-- — the estimate alone was never meant to carry a requisition to payment.
create or replace function submit_procurement_invoice(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition requisitions;
  v_requester_is_dept_head boolean;
  v_target_status requisition_status;
begin
  select * into v_requisition from requisitions where id = p_requisition_id;

  if v_requisition.requisition_kind <> 'procurement' then
    raise exception 'Requisition % is not a Product/Service Requisition', p_requisition_id;
  end if;
  if v_requisition.status <> 'awaiting_invoice' then
    raise exception 'Requisition % is not awaiting an invoice (status: %)', p_requisition_id, v_requisition.status;
  end if;
  if p_actor_id <> v_requisition.requester_id
     and not exists (select 1 from profiles where id = p_actor_id and role = 'admin') then
    raise exception 'Actor % is not permitted to submit the invoice for requisition %', p_actor_id, p_requisition_id;
  end if;
  if v_requisition.amount is null then
    raise exception 'Enter the invoice amount before submitting.';
  end if;

  if v_requisition.requires_full_reapproval then
    v_requester_is_dept_head := exists (
      select 1 from department_heads
       where department_id = v_requisition.department_id and user_id = v_requisition.requester_id
    );
    v_target_status := case
      when v_requisition.requisition_type = 'individual' or v_requester_is_dept_head then 'procurement_finance_review'
      else 'procurement_dept_review'
    end;

    update requisitions
      set status = v_target_status, invoice_submitted_at = now(), stage_entered_at = now()
      where id = p_requisition_id;

    perform notify_role_group(
      p_requisition_id,
      case when v_target_status = 'procurement_dept_review' then 'department' else 'finance' end,
      'dept_approved'
    );
  else
    update requisitions
      set status = 'finance_review', invoice_submitted_at = now(), stage_entered_at = now()
      where id = p_requisition_id;
    perform notify_role_group(p_requisition_id, 'finance', 'dept_approved');
  end if;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision)
  values (p_requisition_id, 'finance', p_actor_id, 'invoice_submitted');
end;
$$;
