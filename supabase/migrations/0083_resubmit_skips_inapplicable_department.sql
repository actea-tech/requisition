-- A returned requisition restarted "from the top" always went back through
-- the department stage - even when that stage doesn't apply because the
-- requester is the department head, or the requisition is Individual (no
-- department). It would land on "Department Review" (or "Procurement -
-- Department Review") with nobody able to act on it. Applies to Payment
-- and Fund requisitions as much as Product/Service ones.
--
-- Now a restart goes where a fresh submission would (the same routing as
-- submit_requisition): no department stage -> straight to Finance. Also:
--   * "return to the previous stage" from Finance, where there is no
--     department stage, becomes a return to the requester;
--   * resubmitting an already-returned requisition whose recorded restart
--     point is an inapplicable department stage is corrected at resubmit
--     time, so ones already sitting returned are fixed too.

-- Whether this requisition has a department review stage at all: a
-- Departmental requisition not raised by its own department head.
create function department_stage_applies(p_requisition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select r.requisition_type = 'departmental'
         and not exists (
           select 1 from department_heads dh
            where dh.department_id = r.department_id and dh.user_id = r.requester_id
         )
    from requisitions r
   where r.id = p_requisition_id;
$$;

-- The status a fresh (re)start from the top lands in - mirrors
-- submit_requisition's routing. p_pre_invoice: a Product/Service requisition
-- that hasn't reached the invoice stage yet uses its procurement_* statuses.
create function restart_status_for(p_requisition_id uuid, p_pre_invoice boolean)
returns requisition_status
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_type requisition_scope;
  v_requester_id uuid;
  v_requester_role user_role;
  v_assistant_routing text;
begin
  select requisition_type, requester_id into v_type, v_requester_id
    from requisitions where id = p_requisition_id;

  if v_type = 'finance_direct' then
    select role into v_requester_role from profiles where id = v_requester_id;
    select value into v_assistant_routing from app_settings where key = 'assistant_finance_direct_routing';
    if v_requester_role = 'finance_assistant'
       and coalesce(v_assistant_routing, 'requires_accountant_approval') <> 'direct' then
      return 'finance_review'::requisition_status;
    end if;
    return 'director_review'::requisition_status;
  end if;

  if department_stage_applies(p_requisition_id) then
    return case when p_pre_invoice then 'procurement_dept_review'::requisition_status else 'dept_review'::requisition_status end;
  end if;
  return case when p_pre_invoice then 'procurement_finance_review'::requisition_status else 'finance_review'::requisition_status end;
end;
$$;

-- evaluate_stage: only the "returned" restart/previous-stage targets change.
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

    -- "Return to the previous stage" from Finance means the Department
    -- Head - which doesn't exist for this requisition if it has no
    -- department stage (individual, or raised by the department head).
    -- Treat that as a return to the requester instead.
    if new.stage_key = 'finance' and v_return_to = 'previous_stage'
       and not department_stage_applies(new.requisition_id) then
      v_return_to := 'requester';
      update requisitions set return_to = 'requester' where id = new.requisition_id;
    end if;

    v_target_status := case
      when new.stage_key = 'finance' and v_return_to = 'previous_stage' then
        (case
          when v_current_status = 'procurement_finance_review' then 'procurement_dept_review'::requisition_status
          else 'dept_review'::requisition_status
        end)
      when new.stage_key = 'director' and v_return_to = 'previous_stage' then 'finance_review'::requisition_status
      -- Restarting "from the top" starts where a fresh submission would for
      -- this requisition - not always the department stage.
      when v_requires_reapproval then
        restart_status_for(
          new.requisition_id,
          v_current_status in ('procurement_dept_review', 'procurement_finance_review')
        )
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

    -- At authorization, "everyone selected must approve" counts all the
    -- selected authorizers - not just whoever is currently eligible, which
    -- in sequential mode is only the next one in line.
    if new.stage_key = 'director' then
      v_eligible_count := (select count(*) from director_authorizer_candidates(new.requisition_id));
    else
      v_eligible_count := (select count(*) from get_eligible_approver_ids(new.requisition_id, new.stage_key));
    end if;
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
    elsif new.stage_key = 'director'
          and (select authorizers_ordered from requisitions where id = new.requisition_id) then
      -- Sequential authorization: this one's done, so the next in line is
      -- only now notified (and able to authorize).
      perform notify_authorizers(
        new.requisition_id,
        array(select get_eligible_approver_ids(new.requisition_id, 'director'))
      );
    end if;
  end if;

  return new;
end;
$$;

-- Same as 0081, plus: if the recorded restart point is a department stage
-- that doesn't apply to this requisition, restart where a fresh submission
-- would instead.
create or replace function resubmit_requisition(p_requisition_id uuid, p_actor_id uuid, p_comments text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_returned_from requisition_status;
  v_target requisition_status;
begin
  select status, returned_from_stage into v_status, v_returned_from
    from requisitions where id = p_requisition_id;

  if v_status <> 'returned' or v_returned_from is null then
    raise exception 'Requisition % is not returned (status: %)', p_requisition_id, v_status;
  end if;

  v_target := v_returned_from;
  if v_returned_from in ('dept_review', 'procurement_dept_review')
     and not department_stage_applies(p_requisition_id) then
    v_target := restart_status_for(p_requisition_id, v_returned_from = 'procurement_dept_review');
  end if;

  update requisitions
    set status = v_target, returned_from_stage = null, return_reason = null, stage_entered_at = now()
    where id = p_requisition_id;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
  values (
    p_requisition_id,
    stage_key_for_status(v_target),
    p_actor_id,
    'submitted',
    nullif(btrim(p_comments), '')
  );
end;
$$;
