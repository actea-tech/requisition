-- 'finance_direct' requisitions (raised by Finance itself — e.g. monthly
-- payroll) skip both Department and Finance review, going straight to
-- director_review — Finance approving its own submission wouldn't mean
-- anything. The one exception: an Assistant Accountant's authority is
-- capped, so whether THEIR finance_direct submissions go straight through
-- or need the Accountant's own clearance first is admin-configurable.
insert into app_settings (key, value) values ('assistant_finance_direct_routing', 'requires_accountant_approval')
  on conflict (key) do nothing;

create or replace function submit_requisition(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition_type requisition_scope;
  v_department_id uuid;
  v_stage_key approval_stage_key;
  v_status requisition_status;
  v_requester_is_dept_head boolean;
  v_actor_role user_role;
  v_assistant_routing text;
begin
  select requisition_type, department_id into v_requisition_type, v_department_id
    from requisitions where id = p_requisition_id;

  select role into v_actor_role from profiles where id = p_actor_id;

  v_requester_is_dept_head := exists (
    select 1 from department_heads where department_id = v_department_id and user_id = p_actor_id
  );

  if v_requisition_type = 'finance_direct' then
    if v_actor_role = 'finance_assistant' then
      select value into v_assistant_routing from app_settings where key = 'assistant_finance_direct_routing';
      if coalesce(v_assistant_routing, 'requires_accountant_approval') = 'direct' then
        v_stage_key := 'director';
        v_status := 'director_review';
      else
        v_stage_key := 'finance';
        v_status := 'finance_review';
      end if;
    else
      v_stage_key := 'director';
      v_status := 'director_review';
    end if;
  elsif v_requisition_type = 'individual' or (v_requisition_type = 'departmental' and v_requester_is_dept_head) then
    v_stage_key := 'finance';
    v_status := 'finance_review';
  else
    v_stage_key := 'department';
    v_status := 'dept_review';
  end if;

  update requisitions
    set status = v_status, stage_entered_at = now(), submitted_at = coalesce(submitted_at, now())
    where id = p_requisition_id;

  -- Landing straight at director_review means nobody's eligible yet —
  -- seed the active Director the same way advance_stage() does for the
  -- normal Finance -> Director transition.
  if v_stage_key = 'director' then
    perform auto_seed_director_authorizer(p_requisition_id);
  end if;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision)
  values (p_requisition_id, v_stage_key, p_actor_id, 'submitted');
end;
$$;

-- 'finance_direct' also skipped department review — same accurate
-- "going directly to Finance review" copy as the individual/dept-head-self
-- cases, when routed there. The director_review case already has correct
-- copy via evaluate_stage()'s existing 'submitted'/'director' dispatch,
-- reused as-is now that submit_requisition can actually reach it.
create or replace function evaluate_stage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eligible_count int;
  v_approved_count int;
  v_mode approval_mode;
  v_quorum int;
  v_department_id uuid;
  v_stage_entered_at timestamptz;
  v_resolved boolean;
  v_return_to text;
  v_requires_reapproval boolean;
  v_current_status requisition_status;
  v_target_status requisition_status;
  v_req_type requisition_scope;
  v_requester_id uuid;
begin
  if new.decision = 'submitted' then
    case new.stage_key
      when 'department' then perform notify_role_group(new.requisition_id, 'department', 'submitted');
      when 'finance' then
        select requisition_type, department_id, requester_id
          into v_req_type, v_department_id, v_requester_id
          from requisitions where id = new.requisition_id;
        perform notify_role_group(
          new.requisition_id, 'finance',
          case
            when v_req_type in ('individual', 'finance_direct') then 'individual_submitted'
            when v_req_type = 'departmental'
                 and exists (select 1 from department_heads where department_id = v_department_id and user_id = v_requester_id)
              then 'individual_submitted'
            else 'dept_approved'
          end
        );
      when 'director' then perform notify_role_group(new.requisition_id, 'director', 'finance_cleared');
      else null;
    end case;
    return new;
  end if;

  if new.decision = 'rejected' then
    update requisitions set status = 'rejected' where id = new.requisition_id;
    perform notify_requester(
      new.requisition_id,
      case new.stage_key
        when 'department' then 'dept_rejected'
        when 'finance' then 'finance_rejected'
        when 'director' then 'director_rejected'
      end,
      new.comments
    );
    return new;
  end if;

  if new.decision = 'returned' then
    select return_to, requires_reapproval, status into v_return_to, v_requires_reapproval, v_current_status
      from requisitions where id = new.requisition_id;

    v_target_status := case
      when new.stage_key = 'finance' and v_return_to = 'previous_stage' then 'dept_review'
      when new.stage_key = 'director' and v_return_to = 'previous_stage' then 'finance_review'
      when v_requires_reapproval then 'dept_review'
      else v_current_status
    end;

    update requisitions
      set returned_from_stage = v_target_status, status = 'returned', return_reason = new.comments
      where id = new.requisition_id;

    if v_return_to = 'previous_stage' and new.stage_key = 'finance' then
      perform notify_role_group(new.requisition_id, 'department', 'stage_returned');
      perform notify_requester(new.requisition_id, 'return_fyi', new.comments);
    elsif v_return_to = 'previous_stage' and new.stage_key = 'director' then
      perform notify_role_group(new.requisition_id, 'finance', 'stage_returned');
      perform notify_requester(new.requisition_id, 'return_fyi', new.comments);
    else
      perform notify_requester(
        new.requisition_id,
        case new.stage_key
          when 'department' then 'dept_returned'
          when 'finance' then 'finance_returned'
          when 'director' then 'director_returned'
        end,
        new.comments
      );
      if new.stage_key in ('finance', 'director') then
        perform notify_role_group(new.requisition_id, 'department', 'return_fyi');
      end if;
      if new.stage_key = 'director' then
        perform notify_role_group(new.requisition_id, 'finance', 'return_fyi');
      end if;
    end if;

    return new;
  end if;

  if new.decision = 'completed' then
    update requisitions set status = 'paid_posted' where id = new.requisition_id;
    perform notify_paid_posted(new.requisition_id);
    return new;
  end if;

  if new.decision = 'approved' then
    select department_id, stage_entered_at into v_department_id, v_stage_entered_at
      from requisitions where id = new.requisition_id;

    v_eligible_count := (select count(*) from get_eligible_approver_ids(new.requisition_id, new.stage_key));
    select mode, quorum_count into v_mode, v_quorum from get_stage_mode(v_department_id, new.stage_key);

    select count(distinct actor_id) into v_approved_count
      from approval_actions
     where requisition_id = new.requisition_id
       and stage_key = new.stage_key
       and decision = 'approved'
       and created_at >= v_stage_entered_at;

    v_resolved := case
      when new.stage_key = 'finance'
           and exists (select 1 from finance_approver_group where requisition_id = new.requisition_id)
        then v_approved_count >= v_eligible_count
      when new.stage_key = 'director'
           and exists (select 1 from requisition_authorizers where requisition_id = new.requisition_id)
        then v_approved_count >= v_eligible_count
      when v_eligible_count <= 1 then true
      when v_mode = 'first_approver' then true
      when v_mode = 'all_approvers' then v_approved_count >= v_eligible_count
      when v_mode = 'quorum' then v_approved_count >= coalesce(v_quorum, v_eligible_count)
      else true
    end;

    if v_resolved then
      perform advance_stage(new.requisition_id, new.stage_key);
    end if;
  end if;

  return new;
end;
$$;
