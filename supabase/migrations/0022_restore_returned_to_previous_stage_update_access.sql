-- 0019 rewrote requisitions_update from 0015's body to add the
-- finance_approver_group branch, but 0015 predates 0016's "let the
-- 'return to previous stage' target actually edit + resubmit" branches —
-- so 0019 silently dropped those two conditions again. This mattered here:
-- handleDecision() runs updateRequisitionFields() (a direct client update)
-- before resubmit_requisition() while status is still 'returned', so a
-- dept head or finance user acting on a requisition returned to their
-- stage couldn't save field edits at that moment. Restoring both, plus the
-- finance_approver_group equivalent for parity with the rest of 0019.
drop policy requisitions_update on requisitions;
create policy requisitions_update on requisitions for update to authenticated
  using (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_is_dept_head_of(department_id) and status = 'dept_review')
    or (auth_is_finance_group_member(id) and status = 'finance_review')
    or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'dept_review')
    or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
    or (auth_is_finance_group_member(id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
  )
  with check (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_is_dept_head_of(department_id) and status = 'dept_review')
    or (auth_is_finance_group_member(id) and status = 'finance_review')
    or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'dept_review')
    or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
    or (auth_is_finance_group_member(id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
  );
