-- Bug: a CASE expression whose branches are all plain string literals
-- resolves to type `text` (Postgres's default for otherwise-untyped
-- literals), not to the enum inferred from context — unlike a bare literal
-- assigned directly to an enum column/variable, which does get the free
-- "unknown"-type coercion. Assigning that `text` result to an enum column
-- then fails with "column ... is of type X but expression is of type
-- text". Every CASE branch that produces a requisition_status or
-- approval_stage_key value introduced by the procurement migrations needs
-- an explicit cast at each literal.

create or replace function submit_requisition(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition_type requisition_scope;
  v_requisition_kind text;
  v_department_id uuid;
  v_is_test boolean;
  v_stage_key approval_stage_key;
  v_status requisition_status;
  v_requester_is_dept_head boolean;
  v_actor_role user_role;
  v_assistant_routing text;
begin
  select requisition_type, requisition_kind, department_id, is_test
    into v_requisition_type, v_requisition_kind, v_department_id, v_is_test
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
    v_status := case
      when v_requisition_kind = 'procurement' then 'procurement_finance_review'::requisition_status
      else 'finance_review'::requisition_status
    end;
  else
    if not exists (select 1 from department_heads where department_id = v_department_id) then
      raise exception 'This department has no department head assigned — raise this as an Individual requisition instead.';
    end if;
    v_stage_key := 'department';
    v_status := case
      when v_requisition_kind = 'procurement' then 'procurement_dept_review'::requisition_status
      else 'dept_review'::requisition_status
    end;
  end if;

  update requisitions
    set status = v_status,
        stage_entered_at = now(),
        submitted_at = coalesce(submitted_at, now()),
        requisition_number = coalesce(requisition_number, next_requisition_number(v_is_test))
    where id = p_requisition_id;

  if v_stage_key = 'director' then
    perform auto_seed_director_authorizer(p_requisition_id);
  end if;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision)
  values (p_requisition_id, v_stage_key, p_actor_id, 'submitted');
end;
$$;

create or replace function advance_stage(p_requisition_id uuid, p_from_stage approval_stage_key)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_min_authorizers int;
  v_current_count int;
  v_status requisition_status;
begin
  select status into v_status from requisitions where id = p_requisition_id;

  case p_from_stage
    when 'department' then
      update requisitions
        set status = case
              when v_status = 'procurement_dept_review' then 'procurement_finance_review'::requisition_status
              else 'finance_review'::requisition_status
            end,
            stage_entered_at = now()
        where id = p_requisition_id;
      perform notify_role_group(p_requisition_id, 'finance', 'dept_approved');

    when 'finance' then
      if v_status = 'procurement_finance_review' then
        update requisitions set status = 'awaiting_invoice', finance_cleared = true, stage_entered_at = now()
          where id = p_requisition_id;
        perform notify_requester(p_requisition_id, 'awaiting_invoice');
      elsif requisition_requires_director(p_requisition_id) then
        perform auto_seed_director_authorizer(p_requisition_id);

        select coalesce(value::int, 2) into v_min_authorizers from app_settings where key = 'min_authorizer_count';
        select count(*) into v_current_count from requisition_authorizers where requisition_id = p_requisition_id;
        if v_current_count < v_min_authorizers then
          raise exception 'Select at least % authorizer(s) before clearing this requisition for authorization', v_min_authorizers;
        end if;

        update requisitions set status = 'director_review', finance_cleared = true, stage_entered_at = now()
          where id = p_requisition_id;
        perform notify_role_group(p_requisition_id, 'director', 'finance_cleared');
      else
        update requisitions set status = 'approved_for_payment', finance_cleared = true, stage_entered_at = now()
          where id = p_requisition_id;
        perform notify_finance_cleared_no_director(p_requisition_id);
      end if;

    when 'director' then
      update requisitions
        set status = 'approved_for_payment', director_decision = 'approved', stage_entered_at = now()
        where id = p_requisition_id;
      perform notify_director_approved(p_requisition_id);

    else
      null;
  end case;
end;
$$;

create or replace function submit_procurement_invoice(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition requisitions;
  v_requester_is_dept_head boolean;
  v_target_status requisition_status;
  v_target_stage_key approval_stage_key;
begin
  select * into v_requisition from requisitions where id = p_requisition_id;

  if v_requisition.requisition_kind <> 'procurement' then
    raise exception 'Requisition % is not a Product/Service Requisition', p_requisition_id;
  end if;
  if v_requisition.status <> 'awaiting_invoice' then
    raise exception 'Requisition % is not awaiting an invoice (status: %)', p_requisition_id, v_requisition.status;
  end if;
  if p_actor_id <> v_requisition.requester_id
     and not exists (select 1 from profiles where id = p_actor_id and role = 'admin') then
    raise exception 'Actor % is not permitted to submit the invoice for requisition %', p_actor_id, p_requisition_id;
  end if;

  if v_requisition.requires_full_reapproval then
    v_requester_is_dept_head := exists (
      select 1 from department_heads
       where department_id = v_requisition.department_id and user_id = v_requisition.requester_id
    );
    v_target_status := case
      when v_requisition.requisition_type = 'individual' or v_requester_is_dept_head then 'procurement_finance_review'::requisition_status
      else 'procurement_dept_review'::requisition_status
    end;
    v_target_stage_key := case
      when v_target_status = 'procurement_dept_review' then 'department'::approval_stage_key
      else 'finance'::approval_stage_key
    end;

    update requisitions
      set status = v_target_status, invoice_submitted_at = now(), stage_entered_at = now()
      where id = p_requisition_id;

    perform notify_role_group(p_requisition_id, v_target_stage_key, 'dept_approved');
  else
    update requisitions
      set status = 'finance_review', invoice_submitted_at = now(), stage_entered_at = now()
      where id = p_requisition_id;
    perform notify_role_group(p_requisition_id, 'finance', 'dept_approved');
  end if;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision)
  values (p_requisition_id, 'finance', p_actor_id, 'invoice_submitted');
end;
$$;

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
      when new.stage_key = 'finance' and v_return_to = 'previous_stage' then
        (case
          when v_current_status = 'procurement_finance_review' then 'procurement_dept_review'::requisition_status
          else 'dept_review'::requisition_status
        end)
      when new.stage_key = 'director' and v_return_to = 'previous_stage' then 'finance_review'::requisition_status
      when v_requires_reapproval then
        (case
          when v_current_status in ('procurement_dept_review', 'procurement_finance_review') then 'procurement_dept_review'::requisition_status
          else 'dept_review'::requisition_status
        end)
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
