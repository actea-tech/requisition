-- The app already decided (migration 0042 and later) that any active
-- Finance Assistant — not just whoever it was delegated to, or who
-- happened to clear Finance — can work Payment Processing and Fund
-- accounting review: record_approval_action, get_pending_approval_
-- requisition_ids, and canEditFinalProcessing/canReviewAccounting are all
-- already "any active accountant/assistant." These RLS policies were never
-- updated to match — a non-delegated Assistant still can't even SELECT
-- the row at approved_for_payment/accounting_review, so she never reaches
-- those buttons. Broaden (auth_role() = 'finance_assistant' and
-- finance_accountant_id = auth.uid()) to (auth_role() = 'finance_assistant'
-- and status in (...)) at exactly those stages — auth_is_forwarded_
-- assistant(...) and the finance_review-stage threshold/forwarding
-- restriction elsewhere are untouched.

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
        or (auth_role() = 'finance_assistant' and status in ('approved_for_payment', 'accounting_review'))
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
        (requester_id = auth.uid() and status in ('draft', 'returned'))
        or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
        or (auth_role() = 'director' and status = 'director_review')
        or (auth_is_requisition_authorizer(id) and status = 'director_review')
        or (auth_is_dept_head_of(department_id) and status = 'dept_review')
        or (auth_is_finance_group_member(id) and status = 'finance_review')
        or (auth_is_forwarded_assistant(id) and status in ('finance_review', 'approved_for_payment'))
        or (auth_role() = 'finance_assistant' and status = 'approved_for_payment')
        or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'dept_review')
        or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
        or (auth_is_finance_group_member(id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
      )
    )
  )
  with check (
    auth_is_admin()
    or (
      is_test = auth_is_test_user()
      and (
        (requester_id = auth.uid() and status in ('draft', 'returned'))
        or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
        or (auth_role() = 'director' and status = 'director_review')
        or (auth_is_requisition_authorizer(id) and status = 'director_review')
        or (auth_is_dept_head_of(department_id) and status = 'dept_review')
        or (auth_is_finance_group_member(id) and status = 'finance_review')
        or (auth_is_forwarded_assistant(id) and status in ('finance_review', 'approved_for_payment'))
        or (auth_role() = 'finance_assistant' and status = 'approved_for_payment')
        or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'dept_review')
        or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
        or (auth_is_finance_group_member(id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
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
               or (auth_role() = 'finance_assistant' and r.status in ('approved_for_payment', 'accounting_review'))
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
               or (auth_role() = 'finance_assistant' and r.status = 'approved_for_payment')
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
               or (auth_role() = 'finance_assistant' and r.status in ('approved_for_payment', 'accounting_review'))
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
               or (auth_role() = 'finance_assistant' and r.status in ('approved_for_payment', 'accounting_review'))
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
               or (auth_role() = 'finance_assistant' and r.status = 'approved_for_payment')
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
               or (auth_role() = 'finance_assistant' and r.status in ('paid_posted', 'accounting_review'))
             )
           )
         )
    )
  );
