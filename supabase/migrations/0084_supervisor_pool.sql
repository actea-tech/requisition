-- Supervisors: for the exception where a requester wants someone to review
-- their requisition before Finance — mainly Individual requisitions (no
-- department head), and department heads who want a supervisor's input
-- (their own requisitions skip department review).
--
--   * Admins build a pool of supervisors (any active user), like the
--     authorizer pool.
--   * The requester can pick one or more from the pool (never themselves).
--     Optional: with none picked, routing is exactly as before.
--   * When picked, the requisition goes to those supervisors first, in the
--     department-review position, then on to Finance. All of them must
--     approve. They can approve, return or reject like a department head.
--   * Only used where there's no regular department review: a Departmental
--     requisition from an ordinary staff member still goes to their
--     department head, whatever's picked.

create table supervisor_pool (
  user_id uuid primary key references profiles (id) on delete cascade,
  added_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

alter table supervisor_pool enable row level security;
-- Everyone can read the pool (requesters pick from it); only admins change it.
create policy supervisor_pool_select on supervisor_pool for select to authenticated using (true);
create policy supervisor_pool_write on supervisor_pool for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());
grant select, insert, delete on supervisor_pool to authenticated;

create table requisition_supervisors (
  requisition_id uuid not null references requisitions (id) on delete cascade,
  user_id uuid not null references profiles (id),
  added_by uuid references profiles (id),
  created_at timestamptz not null default now(),
  primary key (requisition_id, user_id)
);

alter table requisition_supervisors enable row level security;
-- Visible to whoever can see the requisition. Written only through
-- set_requisition_supervisors() below.
create policy requisition_supervisors_select on requisition_supervisors for select to authenticated
  using (exists (select 1 from requisitions r where r.id = requisition_supervisors.requisition_id));
grant select on requisition_supervisors to authenticated;

-- Whether the picked supervisors actually take part: only where there's no
-- regular department review (Individual, or raised by the department head),
-- and never for Finance-direct.
create function requisition_uses_supervisors(p_requisition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    r.requisition_type <> 'finance_direct'
    and exists (select 1 from requisition_supervisors rs where rs.requisition_id = r.id)
    and not (
      r.requisition_type = 'departmental'
      and not exists (select 1 from department_heads dh where dh.department_id = r.department_id and dh.user_id = r.requester_id)
    ),
    false
  )
  from requisitions r
  where r.id = p_requisition_id;
$$;

create function auth_is_requisition_supervisor(p_requisition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- Only while the supervisors actually take part (a leftover pick on a
  -- requisition that no longer uses them grants nothing).
  select requisition_uses_supervisors(p_requisition_id)
         and exists (
           select 1 from requisition_supervisors where requisition_id = p_requisition_id and user_id = auth.uid()
         );
$$;

grant execute on function auth_is_requisition_supervisor(uuid) to authenticated;

-- A department stage now also applies when supervisors were picked.
create or replace function department_stage_applies(p_requisition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      r.requisition_type = 'departmental'
      and not exists (
        select 1 from department_heads dh
         where dh.department_id = r.department_id and dh.user_id = r.requester_id
      )
    ),
    false
  ) or requisition_uses_supervisors(p_requisition_id)
  from requisitions r
  where r.id = p_requisition_id;
$$;

-- The requester sets (replaces) their supervisors while they can still edit
-- the requisition. Anyone from the pool except themselves.
create function set_requisition_supervisors(p_requisition_id uuid, p_user_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition requisitions;
  v_ids uuid[] := coalesce((select array_agg(distinct u) from unnest(p_user_ids) u), '{}');
begin
  select * into v_requisition from requisitions where id = p_requisition_id;
  if v_requisition.id is null then
    raise exception 'Requisition not found';
  end if;
  if not (v_requisition.requester_id = auth.uid() or auth_is_admin()) then
    raise exception 'Only the requester can choose supervisors';
  end if;
  if not (
    v_requisition.status = 'draft'
    or (v_requisition.status = 'returned' and v_requisition.return_to is distinct from 'previous_stage')
  ) then
    raise exception 'Supervisors can only be changed while the requisition is a draft or returned to you';
  end if;
  if v_requisition.requisition_type = 'finance_direct' and cardinality(v_ids) > 0 then
    raise exception 'Supervisors are not used for Finance requisitions';
  end if;
  if cardinality(v_ids) > 5 then
    raise exception 'Choose at most 5 supervisors';
  end if;
  if v_requisition.requester_id = any(v_ids) then
    raise exception 'You can''t select yourself as a supervisor';
  end if;
  if exists (
    select 1 from unnest(v_ids) u
     where not exists (
       select 1 from supervisor_pool sp
         join profiles p on p.id = sp.user_id and p.is_active and p.is_test_user = v_requisition.is_test
        where sp.user_id = u
     )
  ) then
    raise exception 'Supervisors must be chosen from the supervisor list';
  end if;

  delete from requisition_supervisors where requisition_id = p_requisition_id;
  insert into requisition_supervisors (requisition_id, user_id, added_by)
  select p_requisition_id, u, auth.uid() from unnest(v_ids) u;
end;
$$;

grant execute on function set_requisition_supervisors(uuid, uuid[]) to authenticated;

insert into email_templates (key, subject, html_body) values
('supervisor_review_requested', 'Requisition {{requisition_number}} needs your review as supervisor', $html$
<p>Hello,</p>
<p><strong>{{requester_name}}</strong> asked for you to review requisition <strong>{{requisition_number}}</strong> for <strong>{{currency}} {{amount}}</strong> as their supervisor, before it goes to Finance.</p>
<p>Purpose: {{purpose}}</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$)
on conflict (key) do nothing;

-- Department stage eligibility: the picked supervisors (instead of the department head).
create or replace function get_eligible_approver_ids(p_requisition_id uuid, p_stage_key approval_stage_key)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select dh.user_id
    from requisitions r
    join department_heads dh on dh.department_id = r.department_id
    join profiles p on p.id = dh.user_id and p.is_active
   where r.id = p_requisition_id and p_stage_key = 'department'
     and dh.user_id <> r.requester_id
     and p.is_test_user = r.is_test
     and not requisition_uses_supervisors(r.id)

  union

  -- Supervisors the requester chose stand in for the department head.
  select rs.user_id
    from requisition_supervisors rs
    join profiles p on p.id = rs.user_id and p.is_active
    join requisitions r on r.id = rs.requisition_id
   where p_stage_key = 'department' and rs.requisition_id = p_requisition_id
     and rs.user_id <> r.requester_id
     and p.is_test_user = r.is_test
     and requisition_uses_supervisors(r.id)

  union

  select p.id
    from profiles p, requisitions r
   where p_stage_key = 'finance' and p.is_active and p.role = 'finance_accountant'
     and r.id = p_requisition_id and p.id <> r.requester_id
     and p.is_test_user = r.is_test

  union

  select p.id
    from profiles p, requisitions r
   where p_stage_key = 'finance' and p.is_active and p.role = 'finance_assistant'
     and r.id = p_requisition_id and p.id <> r.requester_id
     and p.is_test_user = r.is_test
     and (
       exists (
         select 1 from finance_assistant_thresholds fat
          where fat.currency = r.currency and r.amount <= fat.threshold_amount
       )
       or exists (
         select 1 from finance_assistant_forwards faf
          where faf.requisition_id = r.id and faf.assistant_id = p.id
       )
     )

  union

  select fag.user_id
    from finance_approver_group fag
    join profiles p on p.id = fag.user_id and p.is_active
    join requisitions r on r.id = fag.requisition_id
   where p_stage_key = 'finance' and fag.requisition_id = p_requisition_id
     and fag.user_id <> r.requester_id
     and p.is_test_user = r.is_test

  union

  select c.user_id
    from director_authorizer_candidates(p_requisition_id) c
    join requisitions r on r.id = p_requisition_id
   where p_stage_key = 'director'
     and (not r.authorizers_ordered or c.user_id = next_ordered_authorizer(p_requisition_id));
$$;

-- evaluate_stage: supervisor notification template, and all picked supervisors must approve.
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
      when 'department' then
        perform notify_role_group(
          new.requisition_id, 'department',
          case when requisition_uses_supervisors(new.requisition_id) then 'supervisor_review_requested' else 'submitted' end
        );
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
      -- Supervisors the requester chose: all of them must approve.
      when new.stage_key = 'department' and requisition_uses_supervisors(new.requisition_id)
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

-- submit_requisition: picked supervisors route to the department-review position first.
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
  elsif requisition_uses_supervisors(p_requisition_id) then
    -- The requester chose supervisors to review it first.
    v_stage_key := 'department';
    v_status := case
      when v_requisition_kind = 'procurement' then 'procurement_dept_review'::requisition_status
      else 'dept_review'::requisition_status
    end;
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

-- Supervisors can see the requisitions they review.
drop policy requisitions_select on requisitions;
create policy requisitions_select on requisitions for select to authenticated
  using (
    auth_is_admin()
    or (
      is_test = auth_is_test_user()
      and (
        requester_id = auth.uid()
        or auth_is_finance()
        or auth_role() = 'director'
        or auth_is_dept_head_of(department_id)
        or auth_is_finance_group_member(id)
        or auth_is_requisition_authorizer(id)
        or auth_is_requisition_supervisor(id)
        or auth_is_forwarded_assistant(id)
        or (auth_role() = 'finance_assistant' and status <> 'draft')
      )
    )
  );

drop policy requisition_attachments_select on requisition_attachments;
create policy requisition_attachments_select on requisition_attachments for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = requisition_attachments.requisition_id
         and (
           auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               r.requester_id = auth.uid()
               or auth_is_finance() or auth_role() = 'director'
               or auth_is_dept_head_of(r.department_id)
               or auth_is_finance_group_member(r.id)
               or auth_is_requisition_authorizer(r.id)
               or auth_is_requisition_supervisor(r.id)
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status <> 'draft')
             )
           )
         )
    )
  );

drop policy approval_actions_select on approval_actions;
create policy approval_actions_select on approval_actions for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = approval_actions.requisition_id
         and (
           auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               r.requester_id = auth.uid()
               or auth_is_finance() or auth_role() = 'director'
               or auth_is_dept_head_of(r.department_id)
               or auth_is_finance_group_member(r.id)
               or auth_is_requisition_authorizer(r.id)
               or auth_is_requisition_supervisor(r.id)
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status <> 'draft')
             )
           )
         )
    )
  );

drop policy requisition_attachments_storage_select on storage.objects;
create policy requisition_attachments_storage_select on storage.objects for select to authenticated
  using (
    bucket_id = 'requisition-attachments'
    and exists (
      select 1 from requisitions r
       where r.id::text = (storage.foldername(name))[1]
         and (
           auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               r.requester_id = auth.uid()
               or auth_is_finance() or auth_role() = 'director'
               or (auth_role() = 'dept_head' and auth_is_dept_head_of(r.department_id))
               or auth_is_requisition_authorizer(r.id)
               or auth_is_requisition_supervisor(r.id)
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status <> 'draft')
             )
           )
         )
    )
  );

