-- Consolidated requisitions: Finance combines several requisitions that are
-- already approved and at Payment Processing into ONE requisition, so a
-- single bank transaction or cheque can pay them all.
--
--  * The combined requisition is a normal requisition of kind 'consolidated'
--    raised by Finance (Lead, Assistant or Admin). Its amount and payees are
--    worked out from the requisitions in it - nobody adds them up by hand.
--  * It follows the Finance-direct route: straight to Authorization, or
--    straight to Payment Processing when Finance sets "Requires
--    authorization?" to No (exactly the existing control).
--  * While it is open, the requisitions in it are locked: they can't be paid,
--    returned or cancelled on their own.
--  * Marking the consolidated requisition Paid pays every requisition in it
--    (same voucher / posting references, usual "paid" email); Posted & Closed
--    closes them too. If it is rejected or cancelled they are released.
--  * Consolidated requisitions are left out of the analytics totals (they are
--    the same money as the requisitions in them) and summarised separately.

alter table requisitions drop constraint requisitions_requisition_kind_check;
alter table requisitions add constraint requisitions_requisition_kind_check
  check (requisition_kind in ('payment', 'fund', 'procurement', 'consolidated'));

-- Which requisitions make up a consolidated one. A requisition can be in at
-- most one (requisition_id is unique); the rows are removed if the
-- consolidated requisition is rejected or cancelled.
create table requisition_consolidation_items (
  consolidated_id uuid not null references requisitions (id) on delete cascade,
  requisition_id uuid not null unique references requisitions (id) on delete cascade,
  added_by uuid references profiles (id),
  created_at timestamptz not null default now(),
  primary key (consolidated_id, requisition_id)
);

alter table requisition_consolidation_items enable row level security;
-- Visible to whoever can see the requisition. Written only through the
-- functions below.
create policy requisition_consolidation_items_select on requisition_consolidation_items for select to authenticated
  using (exists (select 1 from requisitions r where r.id = requisition_consolidation_items.requisition_id));
grant select on requisition_consolidation_items to authenticated;

-- True while a consolidated requisition is paying/closing the requisitions in
-- it, so those (otherwise locked) updates are allowed.
create function consolidation_cascade_active()
returns boolean
language sql
stable
as $$
  select coalesce(current_setting('app.consolidation_cascade', true), '') = 'on';
$$;

-- A requisition in a consolidated one can't leave Payment Processing on its
-- own - it is paid, closed or released together with the consolidated one.
create function guard_consolidation_member_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_number text;
begin
  if old.status = 'approved_for_payment' and not consolidation_cascade_active() then
    if exists (select 1 from requisition_consolidation_items where requisition_id = old.id) then
      select c.requisition_number into v_number
        from requisition_consolidation_items i
        join requisitions c on c.id = i.consolidated_id
       where i.requisition_id = old.id;
      raise exception 'This requisition is part of consolidated requisition % and is paid together with it. It can''t be paid, returned or cancelled on its own.',
        coalesce(v_number, '(not yet submitted)');
    end if;
  end if;
  return new;
end;
$$;

create trigger requisitions_guard_consolidation_member
  before update of status on requisitions
  for each row
  when (old.status is distinct from new.status)
  execute function guard_consolidation_member_status();

-- Final Processing fields can be copied from the consolidated requisition to
-- the ones in it whatever the person doing it normally may edit.
create or replace function enforce_field_write_scope()
returns trigger
language plpgsql
as $$
declare
  requester_fields_changed boolean;
  finance_review_fields_changed boolean;
  director_fields_changed boolean;
  final_processing_fields_changed boolean;
begin
  requester_fields_changed := (
    old.requisition_type is distinct from new.requisition_type or
    old.requisition_kind is distinct from new.requisition_kind or
    old.purpose is distinct from new.purpose or
    old.activity_project is distinct from new.activity_project or
    old.payee_name is distinct from new.payee_name or
    old.payee_contact is distinct from new.payee_contact or
    old.amount is distinct from new.amount or
    old.estimated_amount is distinct from new.estimated_amount or
    old.currency is distinct from new.currency or
    old.payment_mode is distinct from new.payment_mode or
    old.payment_mode_details is distinct from new.payment_mode_details or
    old.budget_line is distinct from new.budget_line or
    old.account_code is distinct from new.account_code or
    old.project_fund_class_code is distinct from new.project_fund_class_code or
    old.donor_grant_source is distinct from new.donor_grant_source or
    old.budgeted is distinct from new.budgeted or
    old.procurement_required is distinct from new.procurement_required or
    old.donor_restriction is distinct from new.donor_restriction or
    old.outstanding_advance is distinct from new.outstanding_advance
  );

  finance_review_fields_changed := (
    old.finance_comments is distinct from new.finance_comments or
    old.budget_available is distinct from new.budget_available
  );

  director_fields_changed := old.director_comments is distinct from new.director_comments;

  final_processing_fields_changed := (
    old.payment_voucher_number is distinct from new.payment_voucher_number or
    old.qbo_posting_reference is distinct from new.qbo_posting_reference or
    old.payment_status is distinct from new.payment_status
  );

  if requester_fields_changed
     and not (
       auth_is_admin()
       or (old.requester_id = auth.uid() and old.status in ('draft', 'returned', 'awaiting_invoice'))
       or (auth_is_finance() and old.status in ('finance_review', 'procurement_finance_review'))
       or (auth_is_dept_head_of(old.department_id) and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage in ('dept_review', 'procurement_dept_review'))
       or (auth_is_finance() and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage in ('finance_review', 'procurement_finance_review'))
     ) then
    raise exception 'Not permitted to change request/payment/budget fields on requisition % in status %', old.id, old.status;
  end if;

  if finance_review_fields_changed
     and not (
       auth_is_admin()
       or (auth_is_finance() and old.status in ('finance_review', 'procurement_finance_review'))
       or (auth_is_finance() and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage in ('finance_review', 'procurement_finance_review'))
     ) then
    raise exception 'Not permitted to change Finance Review fields on requisition % in status %', old.id, old.status;
  end if;

  if director_fields_changed
     and not (
       auth_is_admin()
       or (auth_role() = 'director' and old.status = 'director_review')
       or (auth_is_requisition_authorizer(old.id) and old.status = 'director_review')
     ) then
    raise exception 'Not permitted to change Director fields on requisition % in status %', old.id, old.status;
  end if;

  if final_processing_fields_changed
     and not (
       auth_is_admin()
       or consolidation_cascade_active()
       or (
         old.status in ('finance_review', 'procurement_finance_review', 'approved_for_payment', 'paid_posted', 'posted_and_closed')
         or (old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage in ('finance_review', 'procurement_finance_review'))
       )
       and (
         -- Any Finance Lead; an Assistant only when it's assigned to them.
         auth_role() = 'finance_accountant'
         or (auth_role() = 'finance_assistant' and finance_assistant_is_assigned(old.id, auth.uid()))
       )
     ) then
    raise exception 'Not permitted to change Final Processing fields on requisition % in status %', old.id, old.status;
  end if;

  return new;
end;
$$;

-- The payees of a consolidated requisition come from the requisitions in it,
-- so they can't be edited by hand.
create or replace function auth_can_edit_requisition_payees(p_requisition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from requisitions r
     where r.id = p_requisition_id
       and r.requisition_kind <> 'consolidated'
       and (
         auth_is_admin()
         or (
           r.is_test = auth_is_test_user()
           and (
             (r.requester_id = auth.uid() and r.status in ('draft', 'returned', 'awaiting_invoice'))
             or (auth_is_finance() and r.status in ('finance_review', 'procurement_finance_review'))
             or (auth_is_dept_head_of(r.department_id) and r.status = 'returned' and r.return_to = 'previous_stage' and r.returned_from_stage in ('dept_review', 'procurement_dept_review'))
             or (auth_is_finance() and r.status = 'returned' and r.return_to = 'previous_stage' and r.returned_from_stage in ('finance_review', 'procurement_finance_review'))
           )
         )
       )
  );
$$;

-- ---------------------------------------------------------------------------
-- Choosing the requisitions
-- ---------------------------------------------------------------------------

-- Checks the chosen requisitions can be combined and returns their currency.
create function consolidation_validate_members(p_ids uuid[], p_consolidated_id uuid, p_is_test boolean)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_bad text;
  v_currencies text[];
begin
  if cardinality(p_ids) < 2 then
    raise exception 'Choose at least 2 requisitions to combine';
  end if;
  if cardinality(p_ids) > 50 then
    raise exception 'A consolidated requisition can combine at most 50 requisitions';
  end if;
  if (select count(*) from requisitions where id = any(p_ids)) <> cardinality(p_ids) then
    raise exception 'One of the chosen requisitions no longer exists';
  end if;

  select string_agg(coalesce(r.requisition_number, r.id::text), ', ') into v_bad
    from requisitions r
   where r.id = any(p_ids)
     and (
       r.status <> 'approved_for_payment'
       or r.requisition_kind = 'consolidated'
       or r.is_test is distinct from p_is_test
       or coalesce(r.cancellation_status, '') = 'requested'
     );
  if v_bad is not null then
    raise exception 'These requisitions are not ready to be combined (they must be at Payment Processing, with no cancellation requested): %', v_bad;
  end if;

  select string_agg(coalesce(r.requisition_number, r.id::text), ', ') into v_bad
    from requisitions r
    join requisition_consolidation_items i on i.requisition_id = r.id
   where r.id = any(p_ids)
     and i.consolidated_id is distinct from p_consolidated_id;
  if v_bad is not null then
    raise exception 'These requisitions are already part of another consolidated requisition: %', v_bad;
  end if;

  select array_agg(distinct currency) into v_currencies from requisitions where id = any(p_ids);
  if cardinality(v_currencies) <> 1 or v_currencies[1] is null then
    raise exception 'All the requisitions in a consolidated requisition must be in the same currency';
  end if;
  return v_currencies[1];
end;
$$;

-- Replaces the requisitions in a consolidated requisition and rebuilds its
-- currency, payees (copied from each requisition - the total follows) and
-- purpose.
create function apply_consolidation_members(p_consolidated_id uuid, p_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[] := coalesce((select array_agg(distinct u) from unnest(p_ids) u), '{}');
  v_consolidated requisitions;
  v_currency text;
  v_numbers text;
begin
  select * into v_consolidated from requisitions where id = p_consolidated_id;
  v_currency := consolidation_validate_members(v_ids, p_consolidated_id, v_consolidated.is_test);

  delete from requisition_consolidation_items
   where consolidated_id = p_consolidated_id and not (requisition_id = any(v_ids));
  insert into requisition_consolidation_items (consolidated_id, requisition_id, added_by)
  select p_consolidated_id, u, auth.uid()
    from unnest(v_ids) u
   where not exists (
     select 1 from requisition_consolidation_items i
      where i.consolidated_id = p_consolidated_id and i.requisition_id = u
   );

  delete from requisition_payees where requisition_id = p_consolidated_id;
  insert into requisition_payees (requisition_id, sort_order, payee_name, payee_contact, amount, payment_mode, payment_mode_details)
  select p_consolidated_id,
         (row_number() over (order by x.requisition_number, x.sort_order, x.created_at) - 1)::int,
         x.payee_name, x.payee_contact, x.amount, x.payment_mode, x.payment_mode_details
    from (
      select r.requisition_number, p.sort_order, p.created_at,
             p.payee_name, p.payee_contact, p.amount, p.payment_mode, p.payment_mode_details
        from requisitions r
        join requisition_payees p on p.requisition_id = r.id
       where r.id = any(v_ids)
      union all
      -- A requisition with no payee rows still has to be paid.
      select r.requisition_number, 0, r.created_at,
             'Requisition ' || coalesce(r.requisition_number, ''), null, r.amount, null, null
        from requisitions r
       where r.id = any(v_ids)
         and not exists (select 1 from requisition_payees p where p.requisition_id = r.id)
    ) x;

  select string_agg(coalesce(requisition_number, ''), ', ' order by requisition_number) into v_numbers
    from requisitions where id = any(v_ids);

  update requisitions
     set currency = v_currency,
         purpose = case
           when purpose is null or purpose like 'Consolidated payment of %'
             then left('Consolidated payment of ' || cardinality(v_ids) || ' requisitions: ' || v_numbers, 500)
           else purpose
         end
   where id = p_consolidated_id;
end;
$$;

create function create_consolidated_requisition(p_requisition_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_id uuid;
begin
  select role::text into v_role from profiles where id = auth.uid() and is_active;
  if v_role is null or v_role not in ('finance_accountant', 'finance_assistant', 'admin') then
    raise exception 'Only Finance can combine requisitions';
  end if;

  insert into requisitions (requester_id, requisition_type, requisition_kind)
  values (auth.uid(), 'finance_direct', 'consolidated')
  returning id into v_id;

  perform apply_consolidation_members(v_id, p_requisition_ids);
  return v_id;
end;
$$;

grant execute on function create_consolidated_requisition(uuid[]) to authenticated;

-- Change which requisitions are in it, while it is still a draft (or returned
-- to Finance). Once submitted the list is fixed.
create function set_consolidation_members(p_consolidated_id uuid, p_requisition_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition requisitions;
begin
  select * into v_requisition from requisitions where id = p_consolidated_id;
  if v_requisition.id is null or v_requisition.requisition_kind <> 'consolidated' then
    raise exception 'Consolidated requisition not found';
  end if;
  if not (v_requisition.requester_id = auth.uid() or auth_is_admin()) then
    raise exception 'Only whoever raised this consolidated requisition can change what is in it';
  end if;
  if not (
    v_requisition.status = 'draft'
    or (v_requisition.status = 'returned' and v_requisition.return_to is distinct from 'previous_stage')
  ) then
    raise exception 'What is in a consolidated requisition can only be changed while it is a draft or returned to you';
  end if;

  perform apply_consolidation_members(p_consolidated_id, p_requisition_ids);
end;
$$;

grant execute on function set_consolidation_members(uuid, uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- Reading it back (for people who can see the consolidated requisition but
-- not necessarily the requisitions in it, e.g. an authorizer)
-- ---------------------------------------------------------------------------

create function get_consolidation_members(p_consolidated_id uuid)
returns table (
  requisition_id uuid,
  requisition_number text,
  purpose text,
  requester_name text,
  amount numeric,
  currency text,
  status text,
  payees jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c requisitions;
begin
  select * into c from requisitions where id = p_consolidated_id;
  if c.id is null or c.requisition_kind <> 'consolidated' then
    return;
  end if;
  if not (
    auth_is_admin()
    or (
      c.is_test = auth_is_test_user()
      and (
        c.requester_id = auth.uid()
        or auth_is_finance()
        or auth_role() in ('director', 'finance_assistant')
        or auth_is_requisition_authorizer(c.id)
        or auth_is_requisition_copied_in(c.id)
      )
    )
  ) then
    return;
  end if;

  return query
    select r.id, r.requisition_number, r.purpose, pr.full_name, r.amount, r.currency, r.status::text,
           coalesce(
             (select jsonb_agg(jsonb_build_object(
                       'payee_name', p.payee_name, 'amount', p.amount, 'payment_mode', p.payment_mode
                     ) order by p.sort_order, p.created_at)
                from requisition_payees p where p.requisition_id = r.id),
             '[]'::jsonb)
      from requisition_consolidation_items i
      join requisitions r on r.id = i.requisition_id
      left join profiles pr on pr.id = r.requester_id
     where i.consolidated_id = p_consolidated_id
     order by r.requisition_number;
end;
$$;

grant execute on function get_consolidation_members(uuid) to authenticated;

-- Which consolidated requisition (if any) a requisition has been combined into.
create function get_requisition_consolidation(p_requisition_id uuid)
returns table (consolidated_id uuid, requisition_number text, status text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m requisitions;
begin
  select * into m from requisitions where id = p_requisition_id;
  if m.id is null then
    return;
  end if;
  if not (
    auth_is_admin()
    or (
      m.is_test = auth_is_test_user()
      and (
        m.requester_id = auth.uid()
        or auth_is_finance()
        or auth_role() in ('director', 'finance_assistant')
        or auth_is_dept_head_of(m.department_id)
        or auth_is_requisition_copied_in(m.id)
      )
    )
  ) then
    return;
  end if;

  return query
    select c.id, c.requisition_number, c.status::text
      from requisition_consolidation_items i
      join requisitions c on c.id = i.consolidated_id
     where i.requisition_id = p_requisition_id;
end;
$$;

grant execute on function get_requisition_consolidation(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Routing
-- ---------------------------------------------------------------------------

-- "Requires authorization?" - the existing control, now also settable by
-- whoever is building a consolidated requisition (default Yes).
create or replace function set_requires_director_authorization(p_requisition_id uuid, p_actor_id uuid, p_value yes_no)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition requisitions;
begin
  select * into v_requisition from requisitions where id = p_requisition_id;

  if v_requisition.requisition_kind = 'consolidated' then
    if not (
      v_requisition.requester_id = p_actor_id
      or exists (select 1 from profiles where id = p_actor_id and is_active and role = 'admin')
    ) then
      raise exception 'Actor % is not permitted to set the authorization requirement for this requisition', p_actor_id;
    end if;
    update requisitions set requires_director_authorization = p_value
      where id = p_requisition_id and status in ('draft', 'returned');
    return;
  end if;

  if not exists (
    select 1 from profiles where id = p_actor_id and is_active and role in ('finance_accountant', 'admin')
  ) and not exists (
    select 1 from finance_assistant_forwards
     where requisition_id = p_requisition_id and assistant_id = p_actor_id
  ) then
    raise exception 'Actor % is not permitted to set Director authorization requirement', p_actor_id;
  end if;

  update requisitions set requires_director_authorization = p_value
    where id = p_requisition_id and status = 'finance_review';
end;
$$;

-- Submitting a consolidated requisition: to Authorization, or - when Finance
-- set "Requires authorization?" to No - straight to Payment Processing.
create function submit_consolidated_requisition(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_members int;
  v_ready int;
  v_direct boolean;
begin
  select * into r from requisitions where id = p_requisition_id;
  if r.requisition_kind <> 'consolidated' then
    raise exception 'Requisition % is not a consolidated requisition', p_requisition_id;
  end if;
  if r.status <> 'draft' then
    raise exception 'Requisition % has already been submitted (status: %)', p_requisition_id, r.status;
  end if;
  if p_actor_id <> r.requester_id
     and not exists (select 1 from profiles where id = p_actor_id and role = 'admin') then
    raise exception 'Actor % is not permitted to submit requisition %', p_actor_id, p_requisition_id;
  end if;

  select count(*), count(*) filter (where m.status = 'approved_for_payment')
    into v_members, v_ready
    from requisition_consolidation_items i
    join requisitions m on m.id = i.requisition_id
   where i.consolidated_id = p_requisition_id;
  if v_members < 2 then
    raise exception 'A consolidated requisition needs at least 2 requisitions in it';
  end if;
  if v_ready <> v_members then
    raise exception 'Some of the requisitions in this one are no longer at Payment Processing - rebuild it';
  end if;
  if coalesce(r.amount, 0) <= 0 then
    raise exception 'The total to pay must be more than zero';
  end if;

  v_direct := r.requires_director_authorization = 'no';

  update requisitions
    set status = case when v_direct then 'approved_for_payment'::requisition_status else 'director_review'::requisition_status end,
        finance_cleared = v_direct,
        stage_entered_at = now(),
        submitted_at = coalesce(submitted_at, now()),
        requisition_number = coalesce(requisition_number, next_requisition_number(r.is_test))
    where id = p_requisition_id;

  if not v_direct then
    perform auto_seed_director_authorizer(p_requisition_id);
  end if;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision)
  values (p_requisition_id, case when v_direct then 'payment'::approval_stage_key else 'director'::approval_stage_key end, p_actor_id, 'submitted');

  if v_direct then
    perform notify_finance_cleared_no_director(p_requisition_id);
  end if;
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

  if v_requisition_kind = 'consolidated' then
    perform submit_consolidated_requisition(p_requisition_id, p_actor_id);
    return;
  end if;

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

-- ---------------------------------------------------------------------------
-- Paying, closing and releasing the requisitions in it
-- ---------------------------------------------------------------------------

create function consolidated_cascade()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  m record;
  v_actor uuid := coalesce(auth.uid(), new.requester_id);
begin
  if new.requisition_kind <> 'consolidated' then
    return new;
  end if;

  perform set_config('app.consolidation_cascade', 'on', true);

  -- Voucher / posting references follow the consolidated requisition, whenever
  -- they are entered (often only after it is marked Paid).
  if new.status in ('approved_for_payment', 'paid_posted', 'posted_and_closed') then
    update requisitions mem
       set payment_voucher_number = new.payment_voucher_number,
           qbo_posting_reference = new.qbo_posting_reference,
           payment_reference = new.payment_reference
      from requisition_consolidation_items i
     where i.consolidated_id = new.id and i.requisition_id = mem.id
       and (mem.payment_voucher_number is distinct from new.payment_voucher_number
            or mem.qbo_posting_reference is distinct from new.qbo_posting_reference
            or mem.payment_reference is distinct from new.payment_reference);
  end if;

  if new.status is distinct from old.status then
    if new.status = 'paid_posted' then
      for m in
        select mem.id
          from requisition_consolidation_items i
          join requisitions mem on mem.id = i.requisition_id
         where i.consolidated_id = new.id and mem.status = 'approved_for_payment'
      loop
        -- The usual "completed" decision: marks it Paid and sends the paid email.
        insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
        values (m.id, 'payment', v_actor, 'completed',
                'Paid together with consolidated requisition ' || coalesce(new.requisition_number, ''));
      end loop;

    elsif new.status = 'posted_and_closed' then
      -- Fund requisitions are closed by their own accounting review instead.
      for m in
        select mem.id
          from requisition_consolidation_items i
          join requisitions mem on mem.id = i.requisition_id
         where i.consolidated_id = new.id and mem.status = 'paid_posted' and mem.requisition_kind <> 'fund'
      loop
        update requisitions set status = 'posted_and_closed' where id = m.id;
        insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
        values (m.id, 'payment', v_actor, 'posted_and_closed',
                'Closed together with consolidated requisition ' || coalesce(new.requisition_number, ''));
      end loop;

    elsif new.status in ('rejected', 'cancelled') then
      delete from requisition_consolidation_items where consolidated_id = new.id;
    end if;
  end if;

  perform set_config('app.consolidation_cascade', 'off', true);
  return new;
end;
$$;

create trigger requisitions_consolidated_cascade
  after update on requisitions
  for each row
  when (new.requisition_kind = 'consolidated')
  execute function consolidated_cascade();

-- Internal helpers only ever run from the functions/triggers above (as their
-- owner) - they must not be callable directly, since they don't check who is
-- asking.
revoke execute on function apply_consolidation_members(uuid, uuid[]) from public, anon, authenticated;
revoke execute on function consolidation_validate_members(uuid[], uuid, boolean) from public, anon, authenticated;
revoke execute on function submit_consolidated_requisition(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Analytics: consolidated requisitions are the same money as the requisitions
-- in them, so they are left out of the totals and summarised on their own.
-- ---------------------------------------------------------------------------

create or replace function get_dashboard_analytics(p_range text default 'all')
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_is_test boolean;
  v_roles text[];
  v_scope text;
  v_start timestamptz;
  v_overdue_days int;
  v_invoice_days int;
  v_result jsonb;
begin
  select role::text, is_test_user into v_role, v_is_test
    from profiles where id = v_uid and is_active;
  if v_role is null then
    return jsonb_build_object('allowed', false);
  end if;

  select array(select btrim(x) from unnest(string_to_array(coalesce(value, ''), ',')) x)
    into v_roles from app_settings where key = 'analytics_roles';
  v_roles := coalesce(v_roles, array['director', 'finance_accountant', 'board']);
  if v_role <> 'admin' and not (v_role = any(v_roles)) then
    return jsonb_build_object('allowed', false);
  end if;

  v_scope := case
    when v_role in ('admin', 'director', 'finance_accountant', 'board') then 'org'
    when v_role = 'dept_head' then 'department'
    when v_role = 'finance_assistant' then 'assigned'
    when v_role = 'finance_reviewer' then 'reviewer'
    else 'own'
  end;

  v_start := case p_range
    when 'month' then date_trunc('month', now())
    when 'quarter' then date_trunc('quarter', now())
    when 'year' then date_trunc('year', now())
    else null
  end;

  select coalesce((select case when value ~ '^\d+$' then value::int end from app_settings where key = 'analytics_overdue_days'), 5),
         coalesce((select case when value ~ '^\d+$' then value::int end from app_settings where key = 'analytics_invoice_overdue_days'), 30)
    into v_overdue_days, v_invoice_days;

  with base as (
    select r.id, r.status::text as status, r.requisition_kind, r.requisition_number, r.purpose,
           r.department_id, r.requester_id, r.currency,
           coalesce(r.amount, r.estimated_amount, 0) as amt,
           coalesce(r.submitted_at, r.created_at) as submitted_at,
           r.stage_entered_at
      from requisitions r
     where r.is_test = v_is_test
       and r.status <> 'draft'
       and (
         v_scope = 'org'
         or r.requester_id = v_uid
         or (v_scope = 'department'
             and r.department_id in (select dh.department_id from department_heads dh where dh.user_id = v_uid))
         or (v_scope = 'assigned' and finance_assistant_is_assigned(r.id, v_uid))
         or (v_scope = 'reviewer'
             and exists (select 1 from finance_approver_group g where g.requisition_id = r.id and g.user_id = v_uid))
       )
  ),
  scoped as (
    select * from base where requisition_kind is distinct from 'consolidated'
  ),
  cons as (
    select * from base where requisition_kind = 'consolidated' and status not in ('rejected', 'cancelled')
  ),
  in_range as (
    select * from scoped where v_start is null or submitted_at >= v_start
  ),
  paid as (
    select a.requisition_id, min(a.created_at) as paid_at
      from approval_actions a
     where a.decision = 'completed' and a.requisition_id in (select id from scoped)
     group by a.requisition_id
  ),
  returned_pause as (
    select a.requisition_id,
           sum(coalesce(
                 (select min(b.created_at) from approval_actions b
                   where b.requisition_id = a.requisition_id and b.decision = 'submitted' and b.created_at > a.created_at),
                 now()) - a.created_at) as pause
      from approval_actions a
     where a.decision = 'returned' and a.requisition_id in (select id from scoped)
     group by a.requisition_id
  ),
  invoice_pause as (
    select i.requisition_id,
           sum(i.created_at - coalesce(
                 (select max(p.created_at) from approval_actions p
                   where p.requisition_id = i.requisition_id and p.decision = 'approved'
                     and p.stage_key = 'finance' and p.created_at < i.created_at),
                 i.created_at)) as pause
      from approval_actions i
     where i.decision = 'invoice_submitted' and i.requisition_id in (select id from scoped)
     group by i.requisition_id
  ),
  turnaround as (
    select greatest(
             extract(epoch from (p.paid_at - s.submitted_at)
                                - coalesce(rp.pause, interval '0')
                                - coalesce(ip.pause, interval '0')),
             0) / 86400.0 as days
      from in_range s
      join paid p on p.requisition_id = s.id
      left join returned_pause rp on rp.requisition_id = s.id
      left join invoice_pause ip on ip.requisition_id = s.id
     where s.status in ('paid_posted', 'accounting_review', 'posted_and_closed')
  )
  select jsonb_build_object(
    'allowed', true,
    'scope', v_scope,
    'range', case when v_start is null then 'all' else p_range end,
    'overdue_days', v_overdue_days,
    'invoice_overdue_days', v_invoice_days,

    'consolidated', (
      select jsonb_build_object(
        'count', count(*),
        'amounts', coalesce(
          (select jsonb_agg(jsonb_build_object('currency', y.currency, 'amount', y.t) order by y.t desc)
             from (select c2.currency, sum(c2.amt) as t from cons c2
                    where v_start is null or c2.submitted_at >= v_start
                    group by c2.currency) y),
          '[]'::jsonb)
      ) from cons where v_start is null or submitted_at >= v_start
    ),

    'counts', (
      select jsonb_build_object(
        'total', count(*),
        'in_progress', count(*) filter (where status in ('dept_review', 'procurement_dept_review', 'procurement_finance_review', 'awaiting_invoice', 'finance_review', 'director_review', 'approved_for_payment')),
        'completed', count(*) filter (where status in ('paid_posted', 'accounting_review', 'posted_and_closed')),
        'returned', count(*) filter (where status = 'returned'),
        'rejected', count(*) filter (where status = 'rejected'),
        'cancelled', count(*) filter (where status = 'cancelled')
      ) from in_range
    ),

    'amounts', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'currency', currency, 'requisitioned', requisitioned, 'paid', paid_amt, 'pipeline', pipeline
             ) order by requisitioned desc), '[]'::jsonb)
        from (
          select currency,
                 coalesce(sum(amt) filter (where status not in ('rejected', 'cancelled')), 0) as requisitioned,
                 coalesce(sum(amt) filter (where status in ('paid_posted', 'accounting_review', 'posted_and_closed')), 0) as paid_amt,
                 coalesce(sum(amt) filter (where status in ('dept_review', 'procurement_dept_review', 'procurement_finance_review', 'awaiting_invoice', 'finance_review', 'director_review', 'approved_for_payment', 'returned')), 0) as pipeline
            from in_range
           group by currency
        ) x
    ),

    'turnaround', (
      select jsonb_build_object(
        'average_days', round(avg(days)::numeric, 1),
        'median_days', round((percentile_cont(0.5) within group (order by days))::numeric, 1),
        'sample', count(*)
      ) from turnaround
    ),

    -- "Right now" figures ignore the date filter.
    'overdue_count', (
      select count(*) from scoped
       where status in ('dept_review', 'procurement_dept_review', 'procurement_finance_review', 'finance_review', 'director_review', 'approved_for_payment')
         and stage_entered_at < now() - make_interval(days => v_overdue_days)
    ),

    'by_stage', (
      select coalesce(jsonb_agg(jsonb_build_object('status', status, 'count', n) order by n desc), '[]'::jsonb)
        from (
          select status, count(*) as n from scoped
           where status in ('dept_review', 'procurement_dept_review', 'procurement_finance_review', 'awaiting_invoice', 'finance_review', 'director_review', 'approved_for_payment', 'returned')
           group by status
        ) x
    ),

    'oldest', (
      select coalesce(jsonb_agg(row_to_json(o)::jsonb order by o.age_days desc), '[]'::jsonb)
        from (
          select s.id, s.requisition_number, s.purpose, s.status, s.currency, s.amt as amount,
                 pr.full_name as requester_name, d.name as department_name,
                 floor(extract(epoch from now() - s.submitted_at) / 86400)::int as age_days,
                 floor(extract(epoch from now() - s.stage_entered_at) / 86400)::int as days_in_stage
            from scoped s
            left join profiles pr on pr.id = s.requester_id
            left join departments d on d.id = s.department_id
           where s.status in ('dept_review', 'procurement_dept_review', 'procurement_finance_review', 'awaiting_invoice', 'finance_review', 'director_review', 'approved_for_payment', 'returned')
           order by s.submitted_at asc
           limit 5
        ) o
    ),

    'invoice_overdue', (
      select coalesce(jsonb_agg(row_to_json(o)::jsonb order by o.days_waiting desc), '[]'::jsonb)
        from (
          select s.id, s.requisition_number, s.purpose, s.currency, s.amt as amount,
                 pr.full_name as requester_name, d.name as department_name,
                 floor(extract(epoch from now() - s.stage_entered_at) / 86400)::int as days_waiting
            from scoped s
            left join profiles pr on pr.id = s.requester_id
            left join departments d on d.id = s.department_id
           where s.status = 'awaiting_invoice'
             and s.stage_entered_at < now() - make_interval(days => v_invoice_days)
           order by s.stage_entered_at asc
           limit 10
        ) o
    ),

    'awaiting_accounting', (
      select jsonb_build_object(
        'count', count(*),
        'amounts', coalesce(
          (select jsonb_agg(jsonb_build_object('currency', currency, 'amount', t) order by t desc)
             from (select currency, sum(amt) as t from scoped
                    where requisition_kind = 'fund' and status in ('paid_posted', 'accounting_review')
                    group by currency) y),
          '[]'::jsonb)
      ) from scoped where requisition_kind = 'fund' and status in ('paid_posted', 'accounting_review')
    ),

    -- Last 12 months, whatever the date filter says.
    'monthly', (
      select jsonb_agg(jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'submitted', sub, 'completed', done) order by m)
        from (
          select m,
                 (select count(*) from scoped s where date_trunc('month', s.submitted_at) = m) as sub,
                 (select count(*) from paid p where p.requisition_id in (select id from scoped) and date_trunc('month', p.paid_at) = m) as done
            from generate_series(date_trunc('month', now()) - interval '11 months', date_trunc('month', now()), interval '1 month') m
        ) z
    ),

    'by_department', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'department', department, 'currency', currency, 'total', total, 'count', n
             ) order by total desc), '[]'::jsonb)
        from (
          select coalesce(d.name, 'No department') as department, s.currency, sum(s.amt) as total, count(*) as n
            from in_range s
            left join departments d on d.id = s.department_id
           where s.status not in ('rejected', 'cancelled')
           group by coalesce(d.name, 'No department'), s.currency
           order by total desc
           limit 60
        ) x
    )
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function get_dashboard_analytics(text) to authenticated;
