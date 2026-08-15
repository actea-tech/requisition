-- Adding reviewers to finance_approver_group only ever made them *eligible*
-- to act (via get_eligible_approver_ids) — it never changed how many
-- approvals evaluate_stage() requires before advancing. Finance's global
-- approval_stage_config mode defaults to (and, absent an admin change,
-- stays) 'first_approver', whose branch below resolved unconditionally on
-- the first 'approved' action regardless of v_eligible_count. So a finance
-- accountant who added reviewers still saw the requisition advance to
-- director_review the moment they approved, before any added reviewer had
-- a chance to act — contradicting the Finance review group panel's own
-- copy ("Your approval alone clears this requisition unless you add others
-- below — then it follows the configured Finance approval rule").
--
-- Fix: at the finance stage specifically, if finance_approver_group has any
-- rows for this requisition, treat that as an explicit opt-in to requiring
-- every eligible approver's decision this round — same as 'all_approvers'
-- mode — regardless of what the org-wide Finance mode is otherwise
-- configured to. An admin-configured 'all_approvers'/'quorum' mode already
-- worked correctly and is unaffected.
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
begin
  if new.decision = 'submitted' then
    case new.stage_key
      when 'department' then perform notify_role_group(new.requisition_id, 'department', 'submitted');
      when 'finance' then perform notify_role_group(new.requisition_id, 'finance', 'dept_approved');
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

    -- "Return to previous stage" always lands on that specific stage.
    -- Otherwise (back to the requester), "requires re-approval" sends it
    -- all the way to department review; unchecked, it resumes at the same
    -- stage that returned it (today's original behavior) rather than
    -- re-collecting approvals that already happened.
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
      when new.stage_key = 'finance' and v_mode = 'first_approver'
           and exists (select 1 from finance_approver_group where requisition_id = new.requisition_id)
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
