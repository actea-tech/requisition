-- Two Finance requests:
--
-- 1. Finance Assistants can see every submitted requisition (Audit Trail
--    and the requisition itself, with its documents/history/payees), like
--    the Finance Lead - but still only *act* where they already could
--    (within their threshold, when forwarded, from Payment Processing on).
--    Unsubmitted drafts stay private to their requester. The app and the
--    authorizer RPCs below enforce the "act" side; this only widens
--    read access.
--
-- 2. Authorizers can be required to authorize in order. Per requisition,
--    Finance switches "authorize in sequence" on (default off = anyone
--    selected, all notified at once, as before). The order authorizers
--    were added in is the sequence (reorderable until they've authorized);
--    only the next one in line is eligible and notified, and the stage
--    resolves once all of them have approved in turn.
--
--    No one is pre-selected any more: Finance picks every authorizer,
--    including the Director (auto_seed_director_authorizer is now a no-op).

-- ===== 1. Finance Assistant: read access to all submitted requisitions =====

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
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status <> 'draft')
             )
           )
         )
    )
  );

drop policy requisition_expenditures_select on requisition_expenditures;
create policy requisition_expenditures_select on requisition_expenditures for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = requisition_expenditures.requisition_id
         and (
           auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               r.requester_id = auth.uid()
               or auth_is_finance()
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status <> 'draft')
             )
           )
         )
    )
  );

drop policy finance_approver_group_select on finance_approver_group;
create policy finance_approver_group_select on finance_approver_group for select to authenticated
  using (
    auth_is_admin()
    or (
      exists (select 1 from requisitions r where r.id = finance_approver_group.requisition_id and r.is_test = auth_is_test_user())
      and (user_id = auth.uid() or auth_is_finance() or auth_role() = 'director' or auth_role() = 'finance_assistant')
    )
  );

drop policy requisition_authorizers_select on requisition_authorizers;
create policy requisition_authorizers_select on requisition_authorizers for select to authenticated
  using (
    auth_is_admin()
    or (
      exists (select 1 from requisitions r where r.id = requisition_authorizers.requisition_id and r.is_test = auth_is_test_user())
      and (user_id = auth.uid() or auth_is_finance() or auth_role() = 'finance_assistant')
    )
  );

drop policy finance_assistant_forwards_select on finance_assistant_forwards;
create policy finance_assistant_forwards_select on finance_assistant_forwards for select to authenticated
  using (
    auth_is_admin()
    or (
      exists (select 1 from requisitions r where r.id = finance_assistant_forwards.requisition_id and r.is_test = auth_is_test_user())
      and (assistant_id = auth.uid() or auth_is_finance() or auth_role() = 'finance_assistant')
    )
  );

-- ===== 2. Ordered authorization =====

alter table requisitions add column authorizers_ordered boolean not null default false;

alter table requisition_authorizers add column sort_order int not null default 0;

update requisition_authorizers ra
   set sort_order = x.rn
  from (
    select requisition_id, user_id,
           row_number() over (partition by requisition_id order by created_at, user_id) as rn
      from requisition_authorizers
  ) x
 where ra.requisition_id = x.requisition_id and ra.user_id = x.user_id;

-- New authorizers join the end of the sequence.
create function set_requisition_authorizer_sort_order()
returns trigger
language plpgsql
as $$
begin
  if new.sort_order is null or new.sort_order = 0 then
    new.sort_order := coalesce(
      (select max(sort_order) from requisition_authorizers where requisition_id = new.requisition_id), 0
    ) + 1;
  end if;
  return new;
end;
$$;

create trigger requisition_authorizers_sort_order
  before insert on requisition_authorizers
  for each row execute function set_requisition_authorizer_sort_order();

-- Everyone selected as an authorizer who can actually authorize this
-- requisition (active, same mode, not the requester) - the previous
-- 'director' branch of get_eligible_approver_ids, now reusable.
create function director_authorizer_candidates(p_requisition_id uuid)
returns table (user_id uuid, sort_order int)
language sql
stable
security definer
set search_path = public
as $$
  select ra.user_id, ra.sort_order
    from requisition_authorizers ra
    join profiles p on p.id = ra.user_id and p.is_active
    join requisitions r on r.id = ra.requisition_id
   where ra.requisition_id = p_requisition_id
     and ra.user_id <> r.requester_id
     and p.is_test_user = r.is_test;
$$;

-- In sequential mode: the first selected authorizer (by order) who hasn't
-- yet approved in the current round.
create function next_ordered_authorizer(p_requisition_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select c.user_id
    from director_authorizer_candidates(p_requisition_id) c
    join requisitions r on r.id = p_requisition_id
   where not exists (
     select 1 from approval_actions aa
      where aa.requisition_id = p_requisition_id
        and aa.stage_key = 'director'
        and aa.decision = 'approved'
        and aa.actor_id = c.user_id
        and aa.created_at >= r.stage_entered_at
   )
   order by c.sort_order, c.user_id
   limit 1;
$$;

-- Director branch now honours sequential mode; everything else is unchanged.
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

-- Approving at authorization counts every selected authorizer, and in
-- sequential mode hands over to the next one. Otherwise unchanged.
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

-- No one is pre-selected as an authorizer any more.
create or replace function auto_seed_director_authorizer(p_requisition_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  null;
end;
$$;

-- Emails the authorization request to specific people (used for "the next
-- one in line" and for someone added later).
create function notify_authorizers(p_requisition_id uuid, p_user_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
begin
  if p_user_ids is null or coalesce(array_length(p_user_ids, 1), 0) = 0 then
    return;
  end if;
  select * into r from requisitions where id = p_requisition_id;
  perform enqueue_email_for_profiles(
    p_requisition_id,
    'finance_cleared',
    p_user_ids,
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'requester_name', (select full_name from profiles where id = r.requester_id),
      'department_name', (select name from departments where id = r.department_id),
      'amount', r.amount,
      'currency', r.currency,
      'purpose', r.purpose,
      'requisition_link', requisition_link(r.id)
    )
  );
end;
$$;

-- Finance Leads and Admins always; a Finance Assistant only where they can
-- act on the requisition: they raised it, cleared Finance on it, it was
-- forwarded to them, it's within their threshold, or it's at Payment
-- Processing or later.
create function finance_assistant_may_act(p_requisition_id uuid, p_actor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when (select role from profiles where id = p_actor_id) <> 'finance_assistant' then true
    else exists (
      select 1 from requisitions r
       where r.id = p_requisition_id
         and (
           r.requester_id = p_actor_id
           or r.finance_accountant_id = p_actor_id
           or exists (select 1 from finance_assistant_forwards f where f.requisition_id = r.id and f.assistant_id = p_actor_id)
           or p_actor_id in (select get_eligible_approver_ids(r.id, 'finance'))
           or r.status in ('approved_for_payment', 'paid_posted', 'accounting_review', 'posted_and_closed')
         )
    )
  end;
$$;

-- Adding someone later still reopens a fully-authorized requisition (see
-- migration 0034). New: an authorizer added while it's out for
-- authorization is notified straight away - if it's their turn.
create or replace function add_requisition_authorizer(p_requisition_id uuid, p_actor_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
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

  select status into v_status from requisitions where id = p_requisition_id;
  if v_status = 'paid_posted' then
    raise exception 'Requisition % has already been paid/closed and can no longer be reopened for authorization', p_requisition_id;
  end if;

  insert into requisition_authorizers (requisition_id, user_id, added_by)
  values (p_requisition_id, p_user_id, p_actor_id)
  on conflict (requisition_id, user_id) do nothing;

  if v_status = 'approved_for_payment' then
    update requisitions set status = 'director_review' where id = p_requisition_id;
    perform notify_role_group(p_requisition_id, 'director', 'finance_cleared');
  elsif v_status = 'director_review' then
    perform notify_authorizers(
      p_requisition_id,
      array(select e from get_eligible_approver_ids(p_requisition_id, 'director') e where e = p_user_id)
    );
  end if;
end;
$$;

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

-- Whether the authorizers must authorize one after another. Decided at
-- Finance review (or while at authorization, until someone has authorized).
create function set_authorizers_ordered(p_requisition_id uuid, p_actor_id uuid, p_ordered boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_stage_entered_at timestamptz;
  v_was_ordered boolean;
  v_next_before uuid;
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

  select status, stage_entered_at, authorizers_ordered
    into v_status, v_stage_entered_at, v_was_ordered
    from requisitions where id = p_requisition_id;

  if v_status not in ('finance_review', 'procurement_finance_review', 'director_review') then
    raise exception 'The authorization order can only be changed at Finance review or while out for authorization';
  end if;
  if v_status = 'director_review' and exists (
    select 1 from approval_actions
     where requisition_id = p_requisition_id and stage_key = 'director'
       and decision = 'approved' and created_at >= v_stage_entered_at
  ) then
    raise exception 'The authorization order can''t be changed once an authorizer has authorized';
  end if;

  if v_was_ordered is not distinct from p_ordered then
    return;
  end if;

  v_next_before := next_ordered_authorizer(p_requisition_id);
  update requisitions set authorizers_ordered = p_ordered where id = p_requisition_id;

  -- Switching to "anyone, in any order" while it's out for authorization:
  -- everyone but the person already notified is notified now.
  if v_status = 'director_review' and not p_ordered then
    perform notify_authorizers(
      p_requisition_id,
      array(select e from get_eligible_approver_ids(p_requisition_id, 'director') e where e is distinct from v_next_before)
    );
  end if;
end;
$$;

-- Moves an authorizer up (-1) or down (+1) in the sequence - only among
-- authorizers who haven't authorized yet.
create function move_requisition_authorizer(p_requisition_id uuid, p_actor_id uuid, p_user_id uuid, p_direction int)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_stage_entered_at timestamptz;
  v_ordered boolean;
  v_my_order int;
  v_other_user uuid;
  v_other_order int;
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
  if p_direction not in (-1, 1) then
    raise exception 'Direction must be -1 (up) or 1 (down)';
  end if;

  select status, stage_entered_at, authorizers_ordered
    into v_status, v_stage_entered_at, v_ordered
    from requisitions where id = p_requisition_id;
  if v_status not in ('finance_review', 'procurement_finance_review', 'director_review') then
    raise exception 'The authorization order can only be changed at Finance review or while out for authorization';
  end if;

  select sort_order into v_my_order
    from requisition_authorizers where requisition_id = p_requisition_id and user_id = p_user_id;
  if v_my_order is null then
    raise exception 'That person is not an authorizer on this requisition';
  end if;

  select user_id, sort_order into v_other_user, v_other_order
    from requisition_authorizers
   where requisition_id = p_requisition_id
     and ((p_direction = -1 and sort_order < v_my_order) or (p_direction = 1 and sort_order > v_my_order))
   order by case when p_direction = -1 then sort_order end desc, case when p_direction = 1 then sort_order end asc
   limit 1;
  if v_other_user is null then
    return;
  end if;

  -- An authorizer who has already authorized keeps their place.
  if v_status = 'director_review' and exists (
    select 1 from approval_actions
     where requisition_id = p_requisition_id and stage_key = 'director' and decision = 'approved'
       and created_at >= v_stage_entered_at and actor_id in (p_user_id, v_other_user)
  ) then
    raise exception 'The order can only be changed for authorizers who haven''t authorized yet';
  end if;

  v_next_before := next_ordered_authorizer(p_requisition_id);

  update requisition_authorizers set sort_order = v_other_order
   where requisition_id = p_requisition_id and user_id = p_user_id;
  update requisition_authorizers set sort_order = v_my_order
   where requisition_id = p_requisition_id and user_id = v_other_user;

  if v_ordered and v_status = 'director_review' then
    v_next_after := next_ordered_authorizer(p_requisition_id);
    if v_next_after is not null and v_next_after is distinct from v_next_before then
      perform notify_authorizers(p_requisition_id, array[v_next_after]);
    end if;
  end if;
end;
$$;

grant execute on function set_authorizers_ordered(uuid, uuid, boolean) to authenticated;
grant execute on function move_requisition_authorizer(uuid, uuid, uuid, int) to authenticated;
