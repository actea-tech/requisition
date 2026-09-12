-- Root cause of "neither Accountant nor Assistant can do anything at
-- Payment Processing": finance_accountant_id (which canEditFinalProcessing
-- keys off) was only ever assigned when the actor's role was exactly
-- 'finance_accountant' — whenever an Assistant cleared Finance instead
-- (under threshold, or forwarded), it stayed null forever, locking out
-- everyone but admin, including the real Accountant.
alter table requisition_attachments add column description text;

create or replace function record_approval_action(
  p_requisition_id uuid,
  p_actor_id uuid,
  p_decision approval_decision,
  p_comments text default null,
  p_return_to text default 'requester',
  p_requires_reapproval boolean default true,
  p_authorization_method text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_stage_key approval_stage_key;
begin
  select status into v_status from requisitions where id = p_requisition_id;
  v_stage_key := stage_key_for_status(v_status);

  if v_stage_key is null then
    raise exception 'Requisition % is not awaiting approval (status: %)', p_requisition_id, v_status;
  end if;

  if p_decision = 'completed' then
    if v_stage_key <> 'payment' then
      raise exception 'Requisition % is not ready for payment completion', p_requisition_id;
    end if;
    if not exists (
      select 1 from profiles where id = p_actor_id and is_active and role in ('finance_accountant', 'finance_assistant', 'admin')
    ) then
      raise exception 'Actor % is not permitted to complete payment processing', p_actor_id;
    end if;
  end if;

  if p_decision = 'returned' and p_return_to = 'previous_stage' and v_stage_key = 'department' then
    raise exception 'There is no earlier stage to return to from department review';
  end if;

  if p_decision in ('approved', 'returned', 'rejected')
     and not exists (
       select 1 from get_eligible_approver_ids(p_requisition_id, v_stage_key) id where id = p_actor_id
     )
     and not exists (
       select 1 from profiles where id = p_actor_id and is_active and role = 'admin'
     ) then
    raise exception 'Actor % is not an eligible approver for requisition % at stage %', p_actor_id, p_requisition_id, v_stage_key;
  end if;

  if p_decision = 'approved' and v_stage_key = 'director' and p_authorization_method is null then
    raise exception 'An authorization method must be selected';
  end if;

  if p_decision = 'returned' then
    update requisitions set return_to = p_return_to, requires_reapproval = p_requires_reapproval
      where id = p_requisition_id;
  end if;

  -- Whoever actually clears Finance — Accountant or Assistant — becomes
  -- responsible for Payment Processing; full delegation means the
  -- Assistant should be able to see it through to the end, same as the
  -- Accountant always could.
  if v_stage_key = 'finance' then
    update requisitions
      set finance_accountant_id = p_actor_id
      where id = p_requisition_id
        and finance_accountant_id is null
        and exists (select 1 from profiles where id = p_actor_id and role in ('finance_accountant', 'finance_assistant'));
  elsif v_stage_key = 'director' then
    update requisitions
      set director_id = p_actor_id
      where id = p_requisition_id and director_id is null;
  end if;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments, authorization_method)
  values (p_requisition_id, v_stage_key, p_actor_id, p_decision, p_comments, p_authorization_method);
end;
$$;

-- Matches the canEditFinalProcessing broadening below: any active
-- Accountant/Assistant should see a Payment-Processing requisition in
-- their Pending My Approval list, not only whoever happens to be recorded
-- in finance_accountant_id.
create or replace function get_pending_approval_requisition_ids(p_user_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select r.id
    from requisitions r
   where r.requester_id <> p_user_id
     and r.status in ('dept_review', 'finance_review', 'director_review')
     and exists (
       select 1 from get_eligible_approver_ids(r.id, stage_key_for_status(r.status)) eid where eid = p_user_id
     )
     and not exists (
       select 1 from approval_actions aa
        where aa.requisition_id = r.id
          and aa.stage_key = stage_key_for_status(r.status)
          and aa.actor_id = p_user_id
          and aa.decision = 'approved'
          and aa.created_at >= r.stage_entered_at
     )

  union

  select r.id
    from requisitions r
   where r.requester_id <> p_user_id
     and r.status = 'approved_for_payment'
     and (
       r.finance_accountant_id = p_user_id
       or exists (
         select 1 from profiles
          where id = p_user_id and is_active and role in ('admin', 'finance_accountant', 'finance_assistant')
       )
     )

  union

  select r.id
    from requisitions r
   where r.requester_id <> p_user_id
     and r.status = 'returned'
     and r.return_to = 'previous_stage'
     and r.returned_from_stage is not null
     and exists (
       select 1 from get_eligible_approver_ids(r.id, stage_key_for_status(r.returned_from_stage)) eid
        where eid = p_user_id
     );
$$;

-- Attachment RLS never learned about finance_assistant at all (only
-- auth_is_finance(), which is finance_accountant/finance_reviewer only) —
-- needed both for uploads at the Finance stage and the new Payment
-- documents panel below. Scoped to requisitions this specific assistant is
-- actually handling (forwarded, or the one who cleared Finance and is now
-- the assigned finance_accountant_id) — not a blanket grant over every
-- requisition, matching auth_is_forwarded_assistant's existing scoping.
drop policy requisition_attachments_insert on requisition_attachments;
create policy requisition_attachments_insert on requisition_attachments for insert to authenticated
  with check (
    uploaded_by = auth.uid()
    and exists (
      select 1 from requisitions r
       where r.id = requisition_attachments.requisition_id
         and (
           r.requester_id = auth.uid()
           or auth_is_finance()
           or auth_is_admin()
           or auth_is_finance_group_member(r.id)
           or auth_is_forwarded_assistant(r.id)
           or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
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
           or auth_is_finance()
           or auth_is_admin()
           or auth_is_forwarded_assistant(r.id)
           or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
         )
    )
  );

-- requisitions_update never let a finance_assistant touch the row at
-- Payment Processing at all (only auth_is_finance(), which excludes
-- finance_assistant) — the second half of the "nobody can do anything at
-- Process Payment" report. requisitions_select already covers the
-- forwarded case (auth_is_forwarded_assistant carries no status
-- restriction, so it persists past Finance into Payment), but not a
-- threshold-eligible assistant who cleared Finance without a forward —
-- add the finance_accountant_id-scoped clause to both for that case.
-- Same finance_accountant_id-scoped gap on attachments/history/storage
-- select: auth_is_forwarded_assistant(r.id) already persists into Payment
-- (no status restriction), but a threshold-eligible assistant who cleared
-- Finance without ever being forwarded had no clause at all.
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
           or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
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
           or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
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
           or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
         )
    )
  );

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
    or (auth_role() = 'finance_assistant' and finance_accountant_id = auth.uid())
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
    or (auth_is_forwarded_assistant(id) and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'finance_assistant' and finance_accountant_id = auth.uid() and status = 'approved_for_payment')
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
    or (auth_is_forwarded_assistant(id) and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'finance_assistant' and finance_accountant_id = auth.uid() and status = 'approved_for_payment')
    or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'dept_review')
    or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
    or (auth_is_finance_group_member(id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
  );
