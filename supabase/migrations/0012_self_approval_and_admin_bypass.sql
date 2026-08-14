-- A department head (or finance/director) can raise their own requisition.
-- Previously they could then approve/clear/authorize their own request,
-- since eligibility only checked department_heads/role membership, not
-- "are you the requester". Exclude the requester from the normal eligible
-- set at every stage. Kept out of the eligible-count used for quorum math
-- (see below) rather than special-cased, so "lone head = auto-approve"
-- still works correctly for everyone else.
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

  union

  select p.id
    from profiles p, requisitions r
   where p_stage_key = 'finance' and p.is_active and p.role = 'finance_accountant'
     and r.id = p_requisition_id and p.id <> r.requester_id

  union

  select fag.user_id
    from finance_approver_group fag
    join profiles p on p.id = fag.user_id and p.is_active
    join requisitions r on r.id = fag.requisition_id
   where p_stage_key = 'finance' and fag.requisition_id = p_requisition_id
     and fag.user_id <> r.requester_id

  union

  select p.id
    from profiles p, requisitions r
   where p_stage_key = 'director' and p.is_active and p.role = 'director'
     and r.id = p_requisition_id and p.id <> r.requester_id;
$$;

-- Admins were shown "Approve/Return/Reject" in the UI at every stage but
-- record_approval_action had no admin bypass, so the call would fail
-- server-side with "not an eligible approver" — this closes that gap, and
-- doubles as the escalation path for a lone department head who raised
-- their own requisition (self-excluded above, leaving zero eligible peers).
create or replace function record_approval_action(
  p_requisition_id uuid,
  p_actor_id uuid,
  p_decision approval_decision,
  p_comments text default null
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
      select 1 from profiles where id = p_actor_id and is_active and role in ('finance_accountant', 'admin')
    ) then
      raise exception 'Actor % is not permitted to complete payment processing', p_actor_id;
    end if;
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

  if v_stage_key = 'finance' then
    update requisitions
      set finance_accountant_id = p_actor_id
      where id = p_requisition_id
        and finance_accountant_id is null
        and exists (select 1 from profiles where id = p_actor_id and role = 'finance_accountant');
  elsif v_stage_key = 'director' then
    update requisitions
      set director_id = p_actor_id
      where id = p_requisition_id and director_id is null;
  end if;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
  values (p_requisition_id, v_stage_key, p_actor_id, p_decision, p_comments);
end;
$$;
