-- Director becomes a singleton role, enforced at the DB level: at most one
-- active Director profile can exist at a time.
create unique index profiles_single_active_director on profiles ((true)) where role = 'director' and is_active;

-- Everyone else who can be selected as a per-requisition authorizer —
-- internal staff keeping their existing role/department, or a `board`
-- member — needs to be explicitly granted that responsibility here. This
-- is a *global* pool (who CAN be picked), separate from the per-requisition
-- selection below (who WAS picked for this one).
create table authorizer_pool (
  user_id uuid primary key references profiles (id),
  added_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

alter table authorizer_pool enable row level security;

create policy authorizer_pool_select on authorizer_pool for select to authenticated using (true);
create policy authorizer_pool_write on authorizer_pool for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());

grant select, insert, delete on authorizer_pool to authenticated;

-- Per-requisition authorizer selection — same shape as finance_approver_group.
-- Write is broadened to finance_assistant alongside finance_accountant
-- (unlike finance_approver_group, which stays Accountant-only) so whoever
-- is handling a Finance-direct requisition can pick authorizers themselves.
create table requisition_authorizers (
  requisition_id uuid not null references requisitions (id) on delete cascade,
  user_id uuid not null references profiles (id),
  added_by uuid references profiles (id),
  created_at timestamptz not null default now(),
  primary key (requisition_id, user_id)
);

create function enforce_requisition_authorizers_cap()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from requisition_authorizers where requisition_id = new.requisition_id) >= 4 then
    raise exception 'A requisition can have at most 4 authorizers selected';
  end if;
  return new;
end;
$$;

create trigger requisition_authorizers_cap
  before insert on requisition_authorizers
  for each row execute function enforce_requisition_authorizers_cap();

alter table requisition_authorizers enable row level security;

create function auth_is_requisition_authorizer(p_requisition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from requisition_authorizers where requisition_id = p_requisition_id and user_id = auth.uid()
  );
$$;

grant execute on function auth_is_requisition_authorizer(uuid) to authenticated;

create policy requisition_authorizers_select on requisition_authorizers for select to authenticated
  using (auth_is_finance() or auth_is_admin() or user_id = auth.uid());
create policy requisition_authorizers_write on requisition_authorizers for all to authenticated
  using (auth_role() = 'finance_accountant' or auth_role() = 'finance_assistant' or auth_is_admin())
  with check (auth_role() = 'finance_accountant' or auth_role() = 'finance_assistant' or auth_is_admin());

grant select, insert, delete on requisition_authorizers to authenticated;

-- Auto-seeds the current Director (if any) as an authorizer whenever
-- selection becomes relevant — "by default the Director is an authorizer."
-- The Accountant can still remove them for a specific requisition; if they
-- do, notify_role_group()'s 'director' branch (below) still keeps the
-- Director in the loop with an FYI.
create function auto_seed_director_authorizer(p_requisition_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_director_id uuid;
begin
  select id into v_director_id from profiles where role = 'director' and is_active limit 1;
  if v_director_id is not null then
    insert into requisition_authorizers (requisition_id, user_id, added_by)
    values (p_requisition_id, v_director_id, null)
    on conflict (requisition_id, user_id) do nothing;
  end if;
end;
$$;

-- Admin-managed list of "how was this authorized" options (Signed Cheque,
-- Approved Online Transaction, ...), picked by each authorizer when they
-- approve — see record_approval_action() below.
create table authorization_methods (
  id uuid primary key default gen_random_uuid(),
  label text not null unique,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

alter table authorization_methods enable row level security;

create policy authorization_methods_select on authorization_methods for select to authenticated using (true);
create policy authorization_methods_write on authorization_methods for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());

grant select, insert, update, delete on authorization_methods to authenticated;

insert into authorization_methods (label, sort_order) values
  ('Signed Cheque', 1),
  ('Approved Online Transaction', 2)
on conflict (label) do nothing;

-- Minimum number of authorizers the Accountant must select before Finance
-- can clear a requisition into director_review (enforced in advance_stage,
-- below, for the normal Finance->Director transition).
insert into app_settings (key, value) values ('min_authorizer_count', '2')
  on conflict (key) do nothing;

alter table approval_actions add column authorization_method text;

-- director's branch is now purely table-driven (requisition_authorizers) —
-- no more blanket "anyone with role='director'" fallback. Eligibility flows
-- entirely through auto-seeding (above) and explicit selection.
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

  union

  select p.id
    from profiles p, requisitions r
   where p_stage_key = 'finance' and p.is_active and p.role = 'finance_accountant'
     and r.id = p_requisition_id and p.id <> r.requester_id

  union

  select p.id
    from profiles p, requisitions r
   where p_stage_key = 'finance' and p.is_active and p.role = 'finance_assistant'
     and r.id = p_requisition_id and p.id <> r.requester_id
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

  union

  select ra.user_id
    from requisition_authorizers ra
    join profiles p on p.id = ra.user_id and p.is_active
    join requisitions r on r.id = ra.requisition_id
   where p_stage_key = 'director' and ra.requisition_id = p_requisition_id
     and ra.user_id <> r.requester_id;
$$;

create or replace function notify_role_group(
  p_requisition_id uuid,
  p_stage_key approval_stage_key,
  p_template_key text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_payload jsonb;
begin
  select * into r from requisitions where id = p_requisition_id;
  v_payload := jsonb_build_object(
    'requisition_number', r.requisition_number,
    'requester_name', (select full_name from profiles where id = r.requester_id),
    'department_name', (select name from departments where id = r.department_id),
    'amount', r.amount,
    'currency', r.currency,
    'purpose', r.purpose,
    'requisition_link', requisition_link(r.id)
  );

  perform enqueue_email_for_profiles(
    p_requisition_id,
    p_template_key,
    array(select get_eligible_approver_ids(p_requisition_id, p_stage_key)),
    v_payload
  );

  if p_stage_key = 'finance' then
    perform enqueue_email_for_profiles(
      p_requisition_id,
      'finance_assistant_no_action_needed',
      array(
        select p.id from profiles p
         where p.role = 'finance_assistant' and p.is_active and p.id <> r.requester_id
           and p.id not in (select get_eligible_approver_ids(p_requisition_id, 'finance'))
      ),
      v_payload
    );
  elsif p_stage_key = 'director' then
    perform enqueue_email_for_profiles(
      p_requisition_id,
      'director_fyi_no_action_needed',
      array(
        select p.id from profiles p
         where p.role = 'director' and p.is_active and p.id <> r.requester_id
           and p.id not in (select get_eligible_approver_ids(p_requisition_id, 'director'))
      ),
      v_payload
    );
  end if;
end;
$$;

insert into email_templates (key, subject, html_body) values
('director_fyi_no_action_needed', 'Requisition {{requisition_number}} — no action needed from you', $html$
<p>Hi {{recipient_name}},</p>
<p>Requisition <strong>{{requisition_number}}</strong> from {{requester_name}} ({{department_name}}) for <strong>{{currency}} {{amount}}</strong> has reached authorization. You weren't selected as an authorizer for this one, so no action is needed from you at this time — you're being kept in the loop as Director.</p>
<p><a href="{{requisition_link}}" class="btn">View requisition</a></p>
$html$)
on conflict (key) do nothing;

-- Auto-seed the Director the moment a requisition needs authorizers.
create or replace function advance_stage(p_requisition_id uuid, p_from_stage approval_stage_key)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_min_authorizers int;
  v_current_count int;
begin
  case p_from_stage
    when 'department' then
      update requisitions set status = 'finance_review', stage_entered_at = now()
        where id = p_requisition_id;
      perform notify_role_group(p_requisition_id, 'finance', 'dept_approved');

    when 'finance' then
      if requisition_requires_director(p_requisition_id) then
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

-- Adds the 'director' sibling to the existing finance_approver_group-driven
-- "all eligible must approve" arm: whenever a requisition has any selected
-- authorizers (it always will once auto-seeded), all of them — not a
-- quorum of some larger pool — must approve before it clears. The
-- pre-existing approval_stage_config mode/quorum row for 'director' no
-- longer has any effect (its Settings card is removed separately).
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

-- record_approval_action gains an authorization-method param — Postgres
-- treats a changed parameter list as a new overload, so the old signature
-- must be dropped explicitly or both would coexist ambiguously.
drop function record_approval_action(uuid, uuid, approval_decision, text, text, boolean);

create function record_approval_action(
  p_requisition_id uuid,
  p_actor_id uuid,
  p_decision approval_decision,
  p_comments text default null,
  p_return_to text default 'requester',
  p_requires_reapproval boolean default true,
  p_authorization_method text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_stage_key approval_stage_key;
begin
  select status into v_status from requisitions where id = p_requisition_id;
  v_stage_key := stage_key_for_status(v_status);

  if v_stage_key is null then
    raise exception 'Requisition % is not awaiting approval (status: %)', p_requisition_id, v_status;
  end if;

  if p_decision = 'completed' then
    if v_stage_key <> 'payment' then
      raise exception 'Requisition % is not ready for payment completion', p_requisition_id;
    end if;
    if not exists (
      select 1 from profiles where id = p_actor_id and is_active and role in ('finance_accountant', 'admin')
    ) then
      raise exception 'Actor % is not permitted to complete payment processing', p_actor_id;
    end if;
  end if;

  if p_decision = 'returned' and p_return_to = 'previous_stage' and v_stage_key = 'department' then
    raise exception 'There is no earlier stage to return to from department review';
  end if;

  if p_decision in ('approved', 'returned', 'rejected')
     and not exists (
       select 1 from get_eligible_approver_ids(p_requisition_id, v_stage_key) id where id = p_actor_id
     )
     and not exists (
       select 1 from profiles where id = p_actor_id and is_active and role = 'admin'
     ) then
    raise exception 'Actor % is not an eligible approver for requisition % at stage %', p_actor_id, p_requisition_id, v_stage_key;
  end if;

  if p_decision = 'approved' and v_stage_key = 'director' and p_authorization_method is null then
    raise exception 'An authorization method must be selected';
  end if;

  if p_decision = 'returned' then
    update requisitions set return_to = p_return_to, requires_reapproval = p_requires_reapproval
      where id = p_requisition_id;
  end if;

  if v_stage_key = 'finance' then
    update requisitions
      set finance_accountant_id = p_actor_id
      where id = p_requisition_id
        and finance_accountant_id is null
        and exists (select 1 from profiles where id = p_actor_id and role = 'finance_accountant');
  elsif v_stage_key = 'director' then
    update requisitions
      set director_id = p_actor_id
      where id = p_requisition_id and director_id is null;
  end if;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments, authorization_method)
  values (p_requisition_id, v_stage_key, p_actor_id, p_decision, p_comments, p_authorization_method);
end;
$$;

grant execute on function record_approval_action(uuid, uuid, approval_decision, text, text, boolean, text) to authenticated;

-- enforce_field_write_scope: same director_comments gate, plus the new
-- per-requisition authorizer check alongside the Director's existing
-- blanket clause (left unchanged).
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
    old.purpose is distinct from new.purpose or
    old.activity_project is distinct from new.activity_project or
    old.payee_name is distinct from new.payee_name or
    old.payee_contact is distinct from new.payee_contact or
    old.amount is distinct from new.amount or
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
       or (old.requester_id = auth.uid() and old.status in ('draft', 'returned'))
       or (auth_is_finance() and old.status = 'finance_review')
       or (auth_is_dept_head_of(old.department_id) and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage = 'dept_review')
       or (auth_is_finance() and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage = 'finance_review')
     ) then
    raise exception 'Not permitted to change request/payment/budget fields on requisition % in status %', old.id, old.status;
  end if;

  if finance_review_fields_changed
     and not (
       auth_is_admin()
       or (auth_is_finance() and old.status = 'finance_review')
       or (auth_is_finance() and old.status = 'returned' and old.return_to = 'previous_stage' and old.returned_from_stage = 'finance_review')
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
       or (old.status = 'approved_for_payment' and old.finance_accountant_id = auth.uid())
     ) then
    raise exception 'Not permitted to change Final Processing fields on requisition % in status %', old.id, old.status;
  end if;

  return new;
end;
$$;

-- RLS: the Director's existing blanket auth_role() = 'director' clauses on
-- every one of these stay exactly as they are (full visibility/edit,
-- matching their special status) — what's added is auth_is_requisition_
-- authorizer(...) alongside, so board/other authorizer_pool members see
-- only requisitions they're actually selected on, not everything.
drop policy requisitions_select on requisitions;
create policy requisitions_select on requisitions for select to authenticated
  using (
    requester_id = auth.uid()
    or auth_is_admin()
    or auth_is_finance()
    or auth_role() = 'director'
    or auth_is_dept_head_of(department_id)
    or auth_is_finance_group_member(id)
    or auth_is_requisition_authorizer(id)
  );

drop policy requisitions_update on requisitions;
create policy requisitions_update on requisitions for update to authenticated
  using (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_is_requisition_authorizer(id) and status = 'director_review')
    or (auth_is_dept_head_of(department_id) and status = 'dept_review')
    or (auth_is_finance_group_member(id) and status = 'finance_review')
    or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'dept_review')
    or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
    or (auth_is_finance_group_member(id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
  )
  with check (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_is_requisition_authorizer(id) and status = 'director_review')
    or (auth_is_dept_head_of(department_id) and status = 'dept_review')
    or (auth_is_finance_group_member(id) and status = 'finance_review')
    or (auth_is_dept_head_of(department_id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'dept_review')
    or (auth_is_finance() and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
    or (auth_is_finance_group_member(id) and status = 'returned' and return_to = 'previous_stage' and returned_from_stage = 'finance_review')
  );

drop policy requisition_attachments_select on requisition_attachments;
create policy requisition_attachments_select on requisition_attachments for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = requisition_attachments.requisition_id
         and (
           r.requester_id = auth.uid()
           or auth_is_admin() or auth_is_finance() or auth_role() = 'director'
           or auth_is_dept_head_of(r.department_id)
           or auth_is_finance_group_member(r.id)
           or auth_is_requisition_authorizer(r.id)
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
           r.requester_id = auth.uid()
           or auth_is_admin() or auth_is_finance() or auth_role() = 'director'
           or auth_is_dept_head_of(r.department_id)
           or auth_is_finance_group_member(r.id)
           or auth_is_requisition_authorizer(r.id)
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
           r.requester_id = auth.uid()
           or auth_is_admin() or auth_is_finance() or auth_role() = 'director'
           or (auth_role() = 'dept_head' and auth_is_dept_head_of(r.department_id))
           or auth_is_requisition_authorizer(r.id)
         )
    )
  );
