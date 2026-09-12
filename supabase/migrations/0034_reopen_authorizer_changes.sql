-- Adding an authorizer after the stage already resolved (requisition is at
-- Payment Processing) reopens it for authorization — without touching
-- stage_entered_at or existing approval_actions rows, so prior authorizers'
-- approvals still count; only the newly-added one is missing from
-- v_approved_count vs. the now-larger v_eligible_count, so evaluate_stage()
-- naturally re-resolves once they approve. Replaces the plain insert the
-- app previously did directly against requisition_authorizers.
create function add_requisition_authorizer(p_requisition_id uuid, p_actor_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
begin
  if not exists (
    select 1 from profiles
     where id = p_actor_id and is_active and role in ('finance_accountant', 'finance_assistant', 'admin')
  ) then
    raise exception 'Actor % is not permitted to manage authorizers', p_actor_id;
  end if;

  select status into v_status from requisitions where id = p_requisition_id;
  if v_status = 'paid_posted' then
    raise exception 'Requisition % has already been paid/closed and can no longer be reopened for authorization', p_requisition_id;
  end if;

  insert into requisition_authorizers (requisition_id, user_id, added_by)
  values (p_requisition_id, p_user_id, p_actor_id)
  on conflict (requisition_id, user_id) do nothing;

  if v_status = 'approved_for_payment' then
    update requisitions set status = 'director_review' where id = p_requisition_id;
    perform notify_role_group(p_requisition_id, 'director', 'finance_cleared');
  end if;
end;
$$;

grant execute on function add_requisition_authorizer(uuid, uuid, uuid) to authenticated;

-- Covers "an authorizer can't access the platform, remove them" — if
-- whoever's left has already all approved (this round), resolve
-- immediately rather than waiting on a next approval event that may never
-- come.
create function remove_requisition_authorizer(p_requisition_id uuid, p_actor_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_stage_entered_at timestamptz;
  v_eligible_count int;
  v_approved_count int;
begin
  if not exists (
    select 1 from profiles
     where id = p_actor_id and is_active and role in ('finance_accountant', 'finance_assistant', 'admin')
  ) then
    raise exception 'Actor % is not permitted to manage authorizers', p_actor_id;
  end if;

  delete from requisition_authorizers where requisition_id = p_requisition_id and user_id = p_user_id;

  select status, stage_entered_at into v_status, v_stage_entered_at from requisitions where id = p_requisition_id;
  if v_status <> 'director_review' then
    return;
  end if;

  v_eligible_count := (select count(*) from get_eligible_approver_ids(p_requisition_id, 'director'));
  select count(distinct actor_id) into v_approved_count
    from approval_actions
   where requisition_id = p_requisition_id
     and stage_key = 'director'
     and decision = 'approved'
     and created_at >= v_stage_entered_at;

  if v_eligible_count > 0 and v_approved_count >= v_eligible_count then
    perform advance_stage(p_requisition_id, 'director');
  end if;
end;
$$;

grant execute on function remove_requisition_authorizer(uuid, uuid, uuid) to authenticated;
