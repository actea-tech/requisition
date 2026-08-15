-- Finance review group members were only granted RLS visibility/action
-- rights via their own profiles.role (auth_is_finance()), never via
-- finance_approver_group membership itself — the same role-vs-membership
-- gap 0015 fixed for department heads. get_eligible_approver_ids and
-- get_pending_approval_requisition_ids already treat group membership as
-- the source of truth for eligibility, but RLS didn't: a group member whose
-- profile role wasn't already finance_accountant/finance_reviewer/
-- director/admin/dept_head-of-that-department couldn't see the requisition
-- at all, regardless of what the eligibility functions said, so they
-- couldn't act on it and it never appeared in their Pending My Approval
-- list either (RLS silently filters rows out from underneath that RPC's
-- otherwise-correct id list).
--
-- Also: nothing ever notified a newly-added member. notify_role_group()
-- only fires once, when the requisition first enters finance_review, and
-- snapshots get_eligible_approver_ids at that instant — anyone added to
-- the group afterwards (the normal case, since the panel that adds them is
-- only shown once already in finance review) never got an email.

create function auth_is_finance_group_member(p_requisition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from finance_approver_group
     where requisition_id = p_requisition_id and user_id = auth.uid()
  );
$$;

grant execute on function auth_is_finance_group_member(uuid) to authenticated;

drop policy requisitions_select on requisitions;
create policy requisitions_select on requisitions for select to authenticated
  using (
    requester_id = auth.uid()
    or auth_is_admin()
    or auth_is_finance()
    or auth_role() = 'director'
    or auth_is_dept_head_of(department_id)
    or auth_is_finance_group_member(id)
  );

drop policy requisitions_update on requisitions;
create policy requisitions_update on requisitions for update to authenticated
  using (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_is_dept_head_of(department_id) and status = 'dept_review')
    or (auth_is_finance_group_member(id) and status = 'finance_review')
  )
  with check (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_is_dept_head_of(department_id) and status = 'dept_review')
    or (auth_is_finance_group_member(id) and status = 'finance_review')
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
         and (r.requester_id = auth.uid() or auth_is_finance() or auth_is_admin() or auth_is_finance_group_member(r.id))
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
         )
    )
  );

-- A group member should be able to see who else is in the group they're
-- part of (previously only finance/director/admin roles could).
drop policy finance_approver_group_select on finance_approver_group;
create policy finance_approver_group_select on finance_approver_group for select to authenticated
  using (auth_is_finance() or auth_role() = 'director' or auth_is_admin() or user_id = auth.uid());

insert into email_templates (key, subject, html_body) values
('finance_group_added', 'You''ve been added as a Finance reviewer for {{requisition_number}}', $html$
<p>Hi {{recipient_name}},</p>
<p>You've been added to the Finance review group for requisition <strong>{{requisition_number}}</strong> from {{requester_name}} ({{department_name}}), for <strong>{{currency}} {{amount}}</strong>.</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$)
on conflict (key) do nothing;

create function notify_finance_group_added()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
begin
  select * into r from requisitions where id = new.requisition_id;
  perform enqueue_email_for_profiles(
    new.requisition_id,
    'finance_group_added',
    array[new.user_id],
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'requester_name', (select full_name from profiles where id = r.requester_id),
      'department_name', (select name from departments where id = r.department_id),
      'amount', r.amount,
      'currency', r.currency,
      'requisition_link', requisition_link(r.id)
    )
  );
  return new;
end;
$$;

create trigger finance_approver_group_notify_added
  after insert on finance_approver_group
  for each row execute function notify_finance_group_added();
