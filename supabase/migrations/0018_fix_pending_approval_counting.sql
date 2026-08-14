-- PENDING_APPROVAL_OR_FILTER (lib/requisition-status.ts) only ever checked
-- requisitions.status, which doesn't change until a stage is FULLY
-- resolved (see evaluate_stage()'s all_approvers/quorum handling in
-- 0007/0016). So once one eligible approver at a multi-approver stage
-- (several department heads, an all_approvers/quorum-mode stage, more than
-- one director, or an ad-hoc finance_approver_group) approved, the
-- requisition kept showing as "pending my approval" for that same person,
-- since status hadn't moved on yet.
--
-- This function additionally requires the caller to be an eligible
-- approver for the requisition's *current* stage and to not already have
-- an 'approved' action recorded for it this round.
create function get_pending_approval_requisition_ids(p_user_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  -- Active review stages (department/finance/director): pending only if
  -- eligible and not already approved since the stage was entered.
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

  -- Payment processing: a single-actor step (the accountant it's assigned
  -- to, or an admin) rather than a multi-approver stage — matches
  -- canEditFinalProcessing, not the broader "any finance role" RLS grant
  -- get_eligible_approver_ids doesn't cover this stage at all.
  select r.id
    from requisitions r
   where r.requester_id <> p_user_id
     and r.status = 'approved_for_payment'
     and (
       r.finance_accountant_id = p_user_id
       or exists (select 1 from profiles where id = p_user_id and is_active and role = 'admin')
     )

  union

  -- Returned to a previous stage: pending for that stage's eligible
  -- approvers until it's resubmitted+decided (no per-round exclusion here —
  -- this is a fresh decision point, not a resumption of one already voted on).
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

grant execute on function get_pending_approval_requisition_ids(uuid) to authenticated;
