-- Tighten test-mode isolation further: a requester's own past work is no
-- longer an unconditional exception. If someone raised requisitions while
-- in test mode and is later switched to production (or vice versa), they
-- should no longer see those old, now-other-mode requisitions either — visibility
-- always follows the viewer's *current* mode, with no exceptions except
-- admin. requester_id = auth.uid() (and the equivalent own-row checks on
-- membership tables) move from being unconditional to just one more
-- clause inside the existing mode-gated group.

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
        or (auth_role() = 'finance_assistant' and finance_accountant_id = auth.uid())
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
        or (auth_role() = 'finance_assistant' and finance_accountant_id = auth.uid() and status = 'approved_for_payment')
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
        or (auth_role() = 'finance_assistant' and finance_accountant_id = auth.uid() and status = 'approved_for_payment')
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
               or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
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
               or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
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
               or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
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
               or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
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
               or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
             )
           )
         )
    )
  );

drop policy finance_approver_group_select on finance_approver_group;
create policy finance_approver_group_select on finance_approver_group for select to authenticated
  using (
    auth_is_admin()
    or (
      exists (select 1 from requisitions r where r.id = finance_approver_group.requisition_id and r.is_test = auth_is_test_user())
      and (user_id = auth.uid() or auth_is_finance() or auth_role() = 'director')
    )
  );

drop policy requisition_authorizers_select on requisition_authorizers;
create policy requisition_authorizers_select on requisition_authorizers for select to authenticated
  using (
    auth_is_admin()
    or (
      exists (select 1 from requisitions r where r.id = requisition_authorizers.requisition_id and r.is_test = auth_is_test_user())
      and (user_id = auth.uid() or auth_is_finance())
    )
  );

drop policy finance_assistant_forwards_select on finance_assistant_forwards;
create policy finance_assistant_forwards_select on finance_assistant_forwards for select to authenticated
  using (
    auth_is_admin()
    or (
      exists (select 1 from requisitions r where r.id = finance_assistant_forwards.requisition_id and r.is_test = auth_is_test_user())
      and (assistant_id = auth.uid() or auth_is_finance())
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
               or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
             )
           )
         )
    )
  );

drop policy requisition_expenditures_insert on requisition_expenditures;
create policy requisition_expenditures_insert on requisition_expenditures for insert to authenticated
  with check (
    created_by = auth.uid()
    and exists (
      select 1 from requisitions r
       where r.id = requisition_expenditures.requisition_id
         and r.requester_id = auth.uid()
         and r.is_test = auth_is_test_user()
         and r.requisition_kind = 'fund'
         and r.status = 'paid_posted'
    )
  );

drop policy requisition_expenditures_delete on requisition_expenditures;
create policy requisition_expenditures_delete on requisition_expenditures for delete to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = requisition_expenditures.requisition_id
         and r.requester_id = auth.uid()
         and r.is_test = auth_is_test_user()
         and r.status = 'paid_posted'
    )
  );
