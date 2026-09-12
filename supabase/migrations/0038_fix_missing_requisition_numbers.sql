-- Regression: every rewrite of submit_requisition() since migration 0024
-- (individual requisitions, then 0027 dept-head-self-submission, then 0033
-- finance-direct routing) dropped the
-- `requisition_number = coalesce(requisition_number, next_requisition_number())`
-- assignment migration 0014 originally had — every requisition submitted
-- since has had a null requisition_number forever (the requisitions list
-- then mislabels these "Draft", since it assumes "no number" means "still
-- a draft").

-- 1. Backfill already-submitted requisitions still missing a number, in
-- submission order, so numbers come out in a sensible sequence.
do $$
declare
  r record;
begin
  for r in
    select id from requisitions
     where requisition_number is null and status <> 'draft'
     order by coalesce(submitted_at, created_at)
  loop
    update requisitions set requisition_number = next_requisition_number() where id = r.id;
  end loop;
end $$;

-- 2. Restore the assignment going forward.
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
    set status = v_status,
        stage_entered_at = now(),
        submitted_at = coalesce(submitted_at, now()),
        requisition_number = coalesce(requisition_number, next_requisition_number())
    where id = p_requisition_id;

  if v_stage_key = 'director' then
    perform auto_seed_director_authorizer(p_requisition_id);
  end if;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision)
  values (p_requisition_id, v_stage_key, p_actor_id, 'submitted');
end;
$$;
