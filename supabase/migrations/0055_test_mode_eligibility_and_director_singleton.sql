-- Test mode, part 2: keep test-mode requisitions routing only to
-- test-mode people at every approval stage, and let a separate test
-- Director exist alongside the real one (one active Director per mode,
-- not one system-wide).

-- Director singleton becomes "one per mode."
drop index profiles_single_active_director;
create unique index profiles_single_active_director on profiles (is_test_user) where role = 'director' and is_active;

-- Every branch gains a same-mode check against the requisition its
-- eligibility is being computed for.
create or replace function get_eligible_approver_ids(p_requisition_id uuid, p_stage_key approval_stage_key)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select dh.user_id
    from requisitions r
    join department_heads dh on dh.department_id = r.department_id
    join profiles p on p.id = dh.user_id and p.is_active
   where r.id = p_requisition_id and p_stage_key = 'department'
     and dh.user_id <> r.requester_id
     and p.is_test_user = r.is_test

  union

  select p.id
    from profiles p, requisitions r
   where p_stage_key = 'finance' and p.is_active and p.role = 'finance_accountant'
     and r.id = p_requisition_id and p.id <> r.requester_id
     and p.is_test_user = r.is_test

  union

  select p.id
    from profiles p, requisitions r
   where p_stage_key = 'finance' and p.is_active and p.role = 'finance_assistant'
     and r.id = p_requisition_id and p.id <> r.requester_id
     and p.is_test_user = r.is_test
     and (
       exists (
         select 1 from finance_assistant_thresholds fat
          where fat.currency = r.currency and r.amount <= fat.threshold_amount
       )
       or exists (
         select 1 from finance_assistant_forwards faf
          where faf.requisition_id = r.id and faf.assistant_id = p.id
       )
     )

  union

  select fag.user_id
    from finance_approver_group fag
    join profiles p on p.id = fag.user_id and p.is_active
    join requisitions r on r.id = fag.requisition_id
   where p_stage_key = 'finance' and fag.requisition_id = p_requisition_id
     and fag.user_id <> r.requester_id
     and p.is_test_user = r.is_test

  union

  select ra.user_id
    from requisition_authorizers ra
    join profiles p on p.id = ra.user_id and p.is_active
    join requisitions r on r.id = ra.requisition_id
   where p_stage_key = 'director' and ra.requisition_id = p_requisition_id
     and ra.user_id <> r.requester_id
     and p.is_test_user = r.is_test;
$$;

-- Seeds the Director in the *same* mode as the requisition, not just any
-- active Director.
create or replace function auto_seed_director_authorizer(p_requisition_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_director_id uuid;
begin
  select id into v_director_id
    from profiles
   where role = 'director' and is_active
     and is_test_user = (select is_test from requisitions where id = p_requisition_id)
   limit 1;
  if v_director_id is not null then
    insert into requisition_authorizers (requisition_id, user_id, added_by)
    values (p_requisition_id, v_director_id, null)
    on conflict (requisition_id, user_id) do nothing;
  end if;
end;
$$;

-- get_pending_approval_requisition_ids: its department/finance/director and
-- returned-to-previous-stage branches already flow through
-- get_eligible_approver_ids (fixed above); the two branches that check role
-- membership directly (approved_for_payment, accounting_review) need their
-- own same-mode check added.
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
     and exists (select 1 from profiles me where me.id = p_user_id and me.is_test_user = r.is_test)
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
     and r.status = 'accounting_review'
     and exists (select 1 from profiles me where me.id = p_user_id and me.is_test_user = r.is_test)
     and exists (
       select 1 from profiles
        where id = p_user_id and is_active and role in ('admin', 'finance_accountant', 'finance_assistant')
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
