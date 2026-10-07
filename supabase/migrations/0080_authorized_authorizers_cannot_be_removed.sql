-- An authorizer who has already authorized (in the current round) stays:
-- from then on only authorizers who haven't authorized yet can be removed
-- or reordered. Adding more is still allowed at any time (it reopens a
-- fully-authorized requisition until they've authorized too).

-- True when this person has authorized in the current round and the
-- requisition is out for authorization or already at Payment Processing.
-- (Earlier rounds don't count: stage_entered_at moves on when a requisition
-- comes back through Finance.)
create function authorizer_has_authorized(p_requisition_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from requisitions r
      join approval_actions aa on aa.requisition_id = r.id
     where r.id = p_requisition_id
       and r.status in ('director_review', 'approved_for_payment')
       and aa.stage_key = 'director'
       and aa.decision = 'approved'
       and aa.actor_id = p_user_id
       and aa.created_at >= r.stage_entered_at
  );
$$;

-- The database refuses it however the delete is attempted. A requisition
-- being deleted cascades to its authorizers; by then its row is gone, so
-- this correctly doesn't apply.
create function prevent_removing_authorized_authorizer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if authorizer_has_authorized(old.requisition_id, old.user_id) then
    raise exception 'An authorizer who has already authorized can''t be removed';
  end if;
  return old;
end;
$$;

create trigger requisition_authorizers_keep_authorized
  before delete on requisition_authorizers
  for each row execute function prevent_removing_authorized_authorizer();

-- Same function as 0079, with a friendlier up-front refusal.
create or replace function remove_requisition_authorizer(p_requisition_id uuid, p_actor_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_stage_entered_at timestamptz;
  v_ordered boolean;
  v_candidate_count int;
  v_approved_count int;
  v_next_before uuid;
  v_next_after uuid;
begin
  if not exists (
    select 1 from profiles
     where id = p_actor_id and is_active and role in ('finance_accountant', 'finance_assistant', 'admin')
  ) then
    raise exception 'Actor % is not permitted to manage authorizers', p_actor_id;
  end if;
  if not finance_assistant_may_act(p_requisition_id, p_actor_id) then
    raise exception 'You can only manage authorizers on requisitions you can act on';
  end if;
  if authorizer_has_authorized(p_requisition_id, p_user_id) then
    raise exception 'An authorizer who has already authorized can''t be removed';
  end if;

  v_next_before := next_ordered_authorizer(p_requisition_id);

  delete from requisition_authorizers where requisition_id = p_requisition_id and user_id = p_user_id;

  select status, stage_entered_at, authorizers_ordered
    into v_status, v_stage_entered_at, v_ordered
    from requisitions where id = p_requisition_id;
  if v_status <> 'director_review' then
    return;
  end if;

  v_candidate_count := (select count(*) from director_authorizer_candidates(p_requisition_id));
  select count(distinct actor_id) into v_approved_count
    from approval_actions
   where requisition_id = p_requisition_id
     and stage_key = 'director'
     and decision = 'approved'
     and created_at >= v_stage_entered_at;

  if v_candidate_count > 0 and v_approved_count >= v_candidate_count then
    perform advance_stage(p_requisition_id, 'director');
  elsif v_ordered then
    v_next_after := next_ordered_authorizer(p_requisition_id);
    if v_next_after is not null and v_next_after is distinct from v_next_before then
      perform notify_authorizers(p_requisition_id, array[v_next_after]);
    end if;
  end if;
end;
$$;
