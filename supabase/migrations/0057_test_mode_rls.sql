-- Test mode, part 4: RLS. requester_id = auth.uid() and auth_is_admin()
-- stay unconditional everywhere (a requester always sees their own work
-- regardless of their current mode; admins already see across modes
-- elsewhere in this app) — every other, role-based clause is wrapped so it
-- only ever matches when the viewer's own mode equals the requisition's.

create function auth_is_test_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_test_user from profiles where id = auth.uid()), false);
$$;

drop policy requisitions_select on requisitions;
create policy requisitions_select on requisitions for select to authenticated
  using (
    requester_id = auth.uid()
    or auth_is_admin()
    or (
      is_test = auth_is_test_user()
      and (
        auth_is_finance()
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
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (
      is_test = auth_is_test_user()
      and (
        (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
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
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (
      is_test = auth_is_test_user()
      and (
        (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
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
           r.requester_id = auth.uid()
           or auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               auth_is_finance() or auth_role() = 'director'
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
           r.requester_id = auth.uid()
           or auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               auth_is_finance()
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
           r.requester_id = auth.uid()
           or auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               auth_is_finance() or auth_role() = 'director'
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
           r.requester_id = auth.uid()
           or auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               auth_is_finance() or auth_role() = 'director'
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
           r.requester_id = auth.uid()
           or auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               auth_is_finance()
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
             )
           )
         )
    )
  );

-- Membership/expenditure tables: none of these reference the parent
-- requisition's mode today. finance_approver_group_select and
-- requisition_authorizers_select keep their own-row escape hatch
-- (user_id = auth.uid()) unconditional for the same reason
-- requester_id = auth.uid() stays unconditional above.

drop policy finance_approver_group_select on finance_approver_group;
create policy finance_approver_group_select on finance_approver_group for select to authenticated
  using (
    user_id = auth.uid()
    or auth_is_admin()
    or (
      exists (select 1 from requisitions r where r.id = finance_approver_group.requisition_id and r.is_test = auth_is_test_user())
      and (auth_is_finance() or auth_role() = 'director')
    )
  );

drop policy finance_approver_group_write on finance_approver_group;
create policy finance_approver_group_write on finance_approver_group for all to authenticated
  using (
    auth_is_admin()
    or (
      exists (select 1 from requisitions r where r.id = finance_approver_group.requisition_id and r.is_test = auth_is_test_user())
      and (auth_role() = 'finance_accountant' or auth_is_forwarded_assistant(requisition_id))
    )
  )
  with check (
    auth_is_admin()
    or (
      exists (
        select 1 from requisitions r
        join profiles p on p.id = finance_approver_group.user_id
        where r.id = finance_approver_group.requisition_id and p.is_test_user = r.is_test
      )
      and (auth_role() = 'finance_accountant' or auth_is_forwarded_assistant(requisition_id))
    )
  );

drop policy requisition_authorizers_select on requisition_authorizers;
create policy requisition_authorizers_select on requisition_authorizers for select to authenticated
  using (
    user_id = auth.uid()
    or auth_is_admin()
    or (
      exists (select 1 from requisitions r where r.id = requisition_authorizers.requisition_id and r.is_test = auth_is_test_user())
      and auth_is_finance()
    )
  );

drop policy requisition_authorizers_write on requisition_authorizers;
create policy requisition_authorizers_write on requisition_authorizers for all to authenticated
  using (
    auth_is_admin()
    or (
      exists (select 1 from requisitions r where r.id = requisition_authorizers.requisition_id and r.is_test = auth_is_test_user())
      and (auth_role() = 'finance_accountant' or auth_role() = 'finance_assistant')
    )
  )
  with check (
    auth_is_admin()
    or (
      exists (
        select 1 from requisitions r
        join profiles p on p.id = requisition_authorizers.user_id
        where r.id = requisition_authorizers.requisition_id and p.is_test_user = r.is_test
      )
      and (auth_role() = 'finance_accountant' or auth_role() = 'finance_assistant')
    )
  );

drop policy finance_assistant_forwards_select on finance_assistant_forwards;
create policy finance_assistant_forwards_select on finance_assistant_forwards for select to authenticated
  using (
    assistant_id = auth.uid()
    or auth_is_admin()
    or (
      exists (select 1 from requisitions r where r.id = finance_assistant_forwards.requisition_id and r.is_test = auth_is_test_user())
      and auth_is_finance()
    )
  );

drop policy finance_assistant_forwards_write on finance_assistant_forwards;
create policy finance_assistant_forwards_write on finance_assistant_forwards for all to authenticated
  using (
    auth_is_admin()
    or (
      exists (select 1 from requisitions r where r.id = finance_assistant_forwards.requisition_id and r.is_test = auth_is_test_user())
      and auth_role() = 'finance_accountant'
    )
  )
  with check (
    auth_is_admin()
    or (
      exists (
        select 1 from requisitions r
        join profiles p on p.id = finance_assistant_forwards.assistant_id
        where r.id = finance_assistant_forwards.requisition_id and p.is_test_user = r.is_test
      )
      and auth_role() = 'finance_accountant'
    )
  );

drop policy requisition_expenditures_select on requisition_expenditures;
create policy requisition_expenditures_select on requisition_expenditures for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = requisition_expenditures.requisition_id
         and (
           r.requester_id = auth.uid()
           or auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               auth_is_finance()
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
             )
           )
         )
    )
  );
