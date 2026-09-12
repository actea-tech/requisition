-- get_eligible_approver_ids/get_pending_approval_requisition_ids (both
-- security definer, bypass RLS) already correctly treat a forwarded
-- Assistant as eligible — that's why the requisition shows up in the
-- dashboard's raw pending count. But every actual row-fetch on
-- `requisitions` (the detail page, and /approvals' own follow-up select
-- after getting the id list from that same RPC) runs under the signed-in
-- user's session and is gated by requisitions_select, which never learned
-- about finance_assistant_forwards — so the forwarded Assistant satisfied
-- none of its clauses and the row silently disappeared everywhere except
-- that one raw count. Same gap on requisition_attachments/approval_actions/
-- Storage. Fixed the same way 0019/0031 added auth_is_finance_group_member/
-- auth_is_requisition_authorizer for the same class of bug.
create function auth_is_forwarded_assistant(p_requisition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from finance_assistant_forwards
     where requisition_id = p_requisition_id and assistant_id = auth.uid()
  );
$$;

grant execute on function auth_is_forwarded_assistant(uuid) to authenticated;

drop policy requisitions_select on requisitions;
create policy requisitions_select on requisitions for select to authenticated
  using (
    requester_id = auth.uid()
    or auth_is_admin()
    or auth_is_finance()
    or auth_role() = 'director'
    or auth_is_dept_head_of(department_id)
    or auth_is_finance_group_member(id)
    or auth_is_requisition_authorizer(id)
    or auth_is_forwarded_assistant(id)
  );

drop policy requisitions_update on requisitions;
create policy requisitions_update on requisitions for update to authenticated
  using (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_is_requisition_authorizer(id) and status = 'director_review')
    or (auth_is_dept_head_of(department_id) and status = 'dept_review')
    or (auth_is_finance_group_member(id) and status = 'finance_review')
    or (auth_is_forwarded_assistant(id) and status = 'finance_review')
    or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'dept_review')
    or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
    or (auth_is_finance_group_member(id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
  )
  with check (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_is_requisition_authorizer(id) and status = 'director_review')
    or (auth_is_dept_head_of(department_id) and status = 'dept_review')
    or (auth_is_finance_group_member(id) and status = 'finance_review')
    or (auth_is_forwarded_assistant(id) and status = 'finance_review')
    or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'dept_review')
    or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
    or (auth_is_finance_group_member(id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
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
           or auth_is_finance_group_member(r.id)
           or auth_is_requisition_authorizer(r.id)
           or auth_is_forwarded_assistant(r.id)
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
           or auth_is_finance_group_member(r.id)
           or auth_is_requisition_authorizer(r.id)
           or auth_is_forwarded_assistant(r.id)
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
           or auth_is_admin() or auth_is_finance() or auth_role() = 'director'
           or (auth_role() = 'dept_head' and auth_is_dept_head_of(r.department_id))
           or auth_is_requisition_authorizer(r.id)
           or auth_is_forwarded_assistant(r.id)
         )
    )
  );

-- forwardToAssistant() never notified anyone — plain table insert, no
-- email. New dedicated notification, called right after the insert
-- succeeds (app/(dashboard)/requisitions/[id]/actions.ts).
create function notify_assistant_forwarded(p_requisition_id uuid, p_assistant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
begin
  select * into r from requisitions where id = p_requisition_id;
  perform enqueue_email_for_profiles(
    p_requisition_id, 'finance_assistant_forwarded', array[p_assistant_id],
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'requester_name', (select full_name from profiles where id = r.requester_id),
      'department_name', (select name from departments where id = r.department_id),
      'amount', r.amount,
      'currency', r.currency,
      'requisition_link', requisition_link(r.id)
    )
  );
end;
$$;

grant execute on function notify_assistant_forwarded(uuid, uuid) to authenticated;

insert into email_templates (key, subject, html_body) values
('finance_assistant_forwarded', 'Requisition {{requisition_number}} forwarded to you for approval', $html$
<p>Hi {{recipient_name}},</p>
<p>The Finance Accountant forwarded requisition <strong>{{requisition_number}}</strong> from {{requester_name}} ({{department_name}}) for <strong>{{currency}} {{amount}}</strong> to you for approval — it's above the normal threshold, and they've asked you to review it.</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$)
on conflict (key) do nothing;
