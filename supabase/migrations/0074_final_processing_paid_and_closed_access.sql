-- Three related gaps reported from live testing:
--
-- 1. A Finance Assistant marking a requisition Paid got a 404 right after
--    the action succeeded — requisitions_select (and every attachments/
--    approval_actions/expenditures policy keyed the same way) only
--    recognized a non-delegated Assistant at
--    status in ('approved_for_payment', 'accounting_review'). The RPCs
--    themselves (complete_payment_processing, mark_posted_and_closed) are
--    security definer and already accept "any active Assistant," so the
--    mutation succeeds, but the very next read of the row — now at
--    paid_posted — comes back empty under RLS, which the page renders as
--    404. The same gap hid Paid requisitions from them entirely, so they
--    could never reach "Mark posted and closed" either.
-- 2. Final Processing (payment_voucher_number/qbo_posting_reference)
--    should stay editable through Paid and Posted & Closed, not just
--    while still at approved_for_payment — enforce_field_write_scope()
--    only allowed it at that one status.
--
-- Broaden every place gated on finance_assistant's status list (and
-- auth_is_finance()'s update/write-scope status list) to also cover
-- paid_posted/posted_and_closed. auth_is_finance() (accountant/reviewer)
-- was already status-unrestricted for SELECT, so only UPDATE and the
-- write-scope trigger needed the same statuses added there.

drop policy requisitions_select on requisitions;
create policy requisitions_select on requisitions for select to authenticated
  using (
    auth_is_admin()
    or (
      is_test = auth_is_test_user()
      and (
        requester_id = auth.uid()
        or auth_is_finance()
        or auth_role() = 'director'
        or auth_is_dept_head_of(department_id)
        or auth_is_finance_group_member(id)
        or auth_is_requisition_authorizer(id)
        or auth_is_forwarded_assistant(id)
        or (auth_role() = 'finance_assistant' and status in ('approved_for_payment', 'accounting_review', 'paid_posted', 'posted_and_closed'))
      )
    )
  );

drop policy requisitions_update on requisitions;
create policy requisitions_update on requisitions for update to authenticated
  using (
    auth_is_admin()
    or (
      is_test = auth_is_test_user()
      and (
        (requester_id = auth.uid() and status in ('draft', 'returned', 'awaiting_invoice'))
        or (auth_is_finance() and status in ('finance_review', 'procurement_finance_review', 'approved_for_payment', 'paid_posted', 'posted_and_closed'))
        or (auth_role() = 'director' and status = 'director_review')
        or (auth_is_requisition_authorizer(id) and status = 'director_review')
        or (auth_is_dept_head_of(department_id) and status in ('dept_review', 'procurement_dept_review'))
        or (auth_is_finance_group_member(id) and status in ('finance_review', 'procurement_finance_review'))
        or (auth_is_forwarded_assistant(id) and status in ('finance_review', 'approved_for_payment'))
        or (auth_role() = 'finance_assistant' and status in ('approved_for_payment', 'paid_posted', 'posted_and_closed'))
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
        or (auth_is_finance() and status in ('finance_review', 'procurement_finance_review', 'approved_for_payment', 'paid_posted', 'posted_and_closed'))
        or (auth_role() = 'director' and status = 'director_review')
        or (auth_is_requisition_authorizer(id) and status = 'director_review')
        or (auth_is_dept_head_of(department_id) and status in ('dept_review', 'procurement_dept_review'))
        or (auth_is_finance_group_member(id) and status in ('finance_review', 'procurement_finance_review'))
        or (auth_is_forwarded_assistant(id) and status in ('finance_review', 'approved_for_payment'))
        or (auth_role() = 'finance_assistant' and status in ('approved_for_payment', 'paid_posted', 'posted_and_closed'))
        or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage in ('dept_review', 'procurement_dept_review'))
        or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage in ('finance_review', 'procurement_finance_review'))
        or (auth_is_finance_group_member(id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage in ('finance_review', 'procurement_finance_review'))
      )
    )
  );

drop policy requisition_attachments_select on requisition_attachments;
create policy requisition_attachments_select on requisition_attachments for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = requisition_attachments.requisition_id
         and (
           auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               r.requester_id = auth.uid()
               or auth_is_finance() or auth_role() = 'director'
               or auth_is_dept_head_of(r.department_id)
               or auth_is_finance_group_member(r.id)
               or auth_is_requisition_authorizer(r.id)
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status in ('approved_for_payment', 'accounting_review', 'paid_posted', 'posted_and_closed'))
             )
           )
         )
    )
  );

drop policy requisition_attachments_insert on requisition_attachments;
create policy requisition_attachments_insert on requisition_attachments for insert to authenticated
  with check (
    uploaded_by = auth.uid()
    and exists (
      select 1 from requisitions r
       where r.id = requisition_attachments.requisition_id
         and (
           auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               r.requester_id = auth.uid()
               or auth_is_finance()
               or auth_is_finance_group_member(r.id)
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status in ('approved_for_payment', 'paid_posted', 'posted_and_closed'))
             )
           )
         )
    )
  );

drop policy approval_actions_select on approval_actions;
create policy approval_actions_select on approval_actions for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = approval_actions.requisition_id
         and (
           auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               r.requester_id = auth.uid()
               or auth_is_finance() or auth_role() = 'director'
               or auth_is_dept_head_of(r.department_id)
               or auth_is_finance_group_member(r.id)
               or auth_is_requisition_authorizer(r.id)
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status in ('approved_for_payment', 'accounting_review', 'paid_posted', 'posted_and_closed'))
             )
           )
         )
    )
  );

drop policy requisition_attachments_storage_select on storage.objects;
create policy requisition_attachments_storage_select on storage.objects for select to authenticated
  using (
    bucket_id = 'requisition-attachments'
    and exists (
      select 1 from requisitions r
       where r.id::text = (storage.foldername(name))[1]
         and (
           auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               r.requester_id = auth.uid()
               or auth_is_finance() or auth_role() = 'director'
               or (auth_role() = 'dept_head' and auth_is_dept_head_of(r.department_id))
               or auth_is_requisition_authorizer(r.id)
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status in ('approved_for_payment', 'accounting_review', 'paid_posted', 'posted_and_closed'))
             )
           )
         )
    )
  );

drop policy requisition_attachments_storage_insert on storage.objects;
create policy requisition_attachments_storage_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'requisition-attachments'
    and exists (
      select 1 from requisitions r
       where r.id::text = (storage.foldername(name))[1]
         and (
           auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               r.requester_id = auth.uid()
               or auth_is_finance()
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status in ('approved_for_payment', 'paid_posted', 'posted_and_closed'))
             )
           )
         )
    )
  );

drop policy requisition_expenditures_select on requisition_expenditures;
create policy requisition_expenditures_select on requisition_expenditures for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = requisition_expenditures.requisition_id
         and (
           auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               r.requester_id = auth.uid()
               or auth_is_finance()
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status in ('paid_posted', 'accounting_review', 'posted_and_closed'))
             )
           )
         )
    )
  );

-- Final Processing fields stay editable through Paid and Posted & Closed,
-- not just while still at approved_for_payment.
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
       or (old.status in ('approved_for_payment', 'paid_posted', 'posted_and_closed') and (old.finance_accountant_id = auth.uid() or auth_role() = 'finance_assistant'))
     ) then
    raise exception 'Not permitted to change Final Processing fields on requisition % in status %', old.id, old.status;
  end if;

  return new;
end;
$$;
