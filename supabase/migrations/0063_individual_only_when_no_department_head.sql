-- A Departmental requisition needs somewhere to actually be reviewed at the
-- department stage. Someone with no department assigned, or whose
-- department has nobody set as its head, has nowhere for that stage to
-- route to — Individual is the only option that works for them.
--
-- department_id becomes nullable so a requester with no department at all
-- can still raise a requisition (previously blocked outright).
alter table requisitions alter column department_id drop not null;

-- Defense in depth alongside the app-layer restriction (which only offers
-- Individual as an option in that situation): submit_requisition refuses to
-- route into department review when the requisition's department has no
-- department_heads row, instead of silently leaving it stuck at dept_review
-- forever with zero eligible approvers.
create or replace function submit_requisition(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition_type requisition_scope;
  v_department_id uuid;
  v_is_test boolean;
  v_stage_key approval_stage_key;
  v_status requisition_status;
  v_requester_is_dept_head boolean;
  v_actor_role user_role;
  v_assistant_routing text;
begin
  select requisition_type, department_id, is_test into v_requisition_type, v_department_id, v_is_test
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
    if not exists (select 1 from department_heads where department_id = v_department_id) then
      raise exception 'This department has no department head assigned — raise this as an Individual requisition instead.';
    end if;
    v_stage_key := 'department';
    v_status := 'dept_review';
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
