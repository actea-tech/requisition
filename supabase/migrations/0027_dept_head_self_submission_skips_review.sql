-- get_eligible_approver_ids's department branch already excludes the
-- requester (dh.user_id <> r.requester_id) — so a lone department head
-- raising their own department's requisition had zero eligible dept-review
-- approvers and would sit stuck (only an admin override could move it).
-- Route it straight to finance_review instead, exactly like 'individual'
-- type — requisition_type stays 'departmental' for record-keeping/budget
-- purposes, only the routing changes. Checks department_heads membership,
-- not the bare profiles.role column, per the same drift lesson migration
-- 0015 already fixed elsewhere (role can lag behind actual membership).
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
begin
  select requisition_type, department_id into v_requisition_type, v_department_id
    from requisitions where id = p_requisition_id;

  v_requester_is_dept_head := exists (
    select 1 from department_heads where department_id = v_department_id and user_id = p_actor_id
  );

  if v_requisition_type = 'individual' or (v_requisition_type = 'departmental' and v_requester_is_dept_head) then
    v_stage_key := 'finance';
    v_status := 'finance_review';
  else
    v_stage_key := 'department';
    v_status := 'dept_review';
  end if;

  update requisitions
    set status = v_status, stage_entered_at = now(), submitted_at = coalesce(submitted_at, now())
    where id = p_requisition_id;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision)
  values (p_requisition_id, v_stage_key, p_actor_id, 'submitted');
end;
$$;

-- The 'individual_submitted' template's copy is reused for this case too
-- (also skipped department review) — drop the word "individual" so it's
-- accurate for both.
update email_templates set
  subject = 'New requisition {{requisition_number}} awaiting your review',
  html_body = $html$
<p>Hello,</p>
<p><strong>{{requester_name}}</strong> submitted requisition <strong>{{requisition_number}}</strong> for <strong>{{currency}} {{amount}}</strong>, going directly to Finance review.</p>
<p>Purpose: {{purpose}}</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$
where key = 'individual_submitted';

-- evaluate_stage()'s 'submitted' dispatch must pick the same template for
-- this case (previously it would have wrongly said "approved at department
-- level" — see 'dept_approved' template — for a department review that
-- never happened).
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
            when v_req_type = 'individual' then 'individual_submitted'
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
