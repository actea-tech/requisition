-- Visibility for department heads was gated on `auth_role() = 'dept_head'
-- AND auth_is_dept_head_of(...)`, but department_heads membership (set in
-- Settings > Departments) is the actual source of truth — the `role`
-- column is just a display label that can drift out of sync (e.g. an
-- admin later changes someone's role in Settings > Users without touching
-- their department_heads row). When it drifted, the head could no longer
-- see the requisition in RLS at all, regardless of membership. Drop the
-- redundant/incorrect role check; auth_is_dept_head_of already confirms
-- membership.
drop policy requisitions_select on requisitions;
create policy requisitions_select on requisitions for select to authenticated
  using (
    requester_id = auth.uid()
    or auth_is_admin()
    or auth_is_finance()
    or auth_role() = 'director'
    or auth_is_dept_head_of(department_id)
  );

drop policy requisitions_update on requisitions;
create policy requisitions_update on requisitions for update to authenticated
  using (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_is_dept_head_of(department_id) and status = 'dept_review')
  )
  with check (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_is_dept_head_of(department_id) and status = 'dept_review')
  );

drop policy requisition_attachments_select on requisition_attachments;
create policy requisition_attachments_select on requisition_attachments for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = requisition_attachments.requisition_id
         and (
           r.requester_id = auth.uid()
           or auth_is_admin() or auth_is_finance() or auth_role() = 'director'
           or auth_is_dept_head_of(r.department_id)
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
           or auth_is_admin() or auth_is_finance() or auth_role() = 'director'
           or auth_is_dept_head_of(r.department_id)
         )
    )
  );
