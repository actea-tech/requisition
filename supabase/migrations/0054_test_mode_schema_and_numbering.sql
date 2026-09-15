-- Test mode: lets admins flag specific users as "test" so they can keep
-- exercising the live platform without any of it mixing with real
-- production data. A test user's requisitions route only to other test
-- users at every stage, stay out of production views, and get a visibly
-- distinct TST-<year>-<n> number drawn from a separate counter.

-- 1. Per-user flag. New users default to production (false).
alter table profiles add column is_test_user boolean not null default false;

-- 2. Per-requisition flag, stamped once at creation from the requester's
-- current mode and left untouched afterwards even if the requester's own
-- mode changes later.
alter table requisitions add column is_test boolean not null default false;

create function stamp_requisition_test_mode()
returns trigger
language plpgsql
as $$
begin
  new.is_test := coalesce((select is_test_user from profiles where id = new.requester_id), false);
  return new;
end;
$$;

create trigger requisitions_stamp_test_mode
  before insert on requisitions
  for each row execute function stamp_requisition_test_mode();

-- 3. Numbering: a genuinely separate per-mode counter, not a shared one
-- with a different prefix. TST-* and REQ-* sequences never interleave or
-- consume each other's values.
alter table requisition_number_counters drop constraint requisition_number_counters_pkey;
alter table requisition_number_counters add column is_test boolean not null default false;
alter table requisition_number_counters add primary key (year, is_test);

-- Replaced by the mode-aware version below (different argument list, so
-- `create or replace` would leave this one behind as dead code otherwise).
drop function next_requisition_number();

create function next_requisition_number(p_is_test boolean default false)
returns text
language plpgsql
as $$
declare
  v_year int := extract(year from now());
  v_next int;
begin
  insert into requisition_number_counters (year, is_test, last_value)
  values (v_year, p_is_test, 1)
  on conflict (year, is_test) do update set last_value = requisition_number_counters.last_value + 1
  returning last_value into v_next;

  return format('%s-%s-%s', case when p_is_test then 'TST' else 'REQ' end, v_year, lpad(v_next::text, 4, '0'));
end;
$$;

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
