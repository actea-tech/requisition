-- 1. Individual requisitions: a requester can mark a requisition 'individual'
-- at creation, routing it straight to Finance and skipping Department Head
-- review entirely. Defaults to 'departmental' so every existing row and
-- every new requisition behaves exactly as before unless someone actively
-- picks 'Individual'.
create type requisition_scope as enum ('departmental', 'individual');

alter table requisitions
  add column requisition_type requisition_scope not null default 'departmental',
  add column requires_director_authorization yes_no not null default 'yes';

grant insert (requisition_type) on requisitions to authenticated;
grant update (requisition_type) on requisitions to authenticated;
-- requires_director_authorization is deliberately NOT granted here — the
-- only write path is set_requires_director_authorization() below, which
-- checks the actor's role itself rather than relying on RLS/grants.

insert into form_field_config (section, field_key, label, help_text, is_required, sort_order) values
  ('request_details', 'requisition_type', 'Requisition type', 'Individual requisitions skip Department Head review and go straight to Finance.', true, 0);

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
     and not (auth_is_admin() or (auth_role() = 'director' and old.status = 'director_review')) then
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

create or replace function submit_requisition(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition_type requisition_scope;
  v_stage_key approval_stage_key;
  v_status requisition_status;
begin
  select requisition_type into v_requisition_type from requisitions where id = p_requisition_id;

  if v_requisition_type = 'individual' then
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

insert into email_templates (key, subject, html_body) values
('individual_submitted', 'New individual requisition {{requisition_number}} awaiting your review', $html$
<p>Hello,</p>
<p><strong>{{requester_name}}</strong> submitted an individual requisition <strong>{{requisition_number}}</strong> for <strong>{{currency}} {{amount}}</strong>, going directly to Finance review.</p>
<p>Purpose: {{purpose}}</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$)
on conflict (key) do nothing;

-- evaluate_stage()'s existing 'submitted' dispatch fires the Finance
-- notification for both paths (department-approved, or individual
-- submitted directly) — differentiate only the template used, since
-- get_eligible_approver_ids/RLS/get_pending_approval_requisition_ids are
-- already keyed on status/stage_key alone and need no changes.
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
begin
  if new.decision = 'submitted' then
    case new.stage_key
      when 'department' then perform notify_role_group(new.requisition_id, 'department', 'submitted');
      when 'finance' then
        select requisition_type into v_req_type from requisitions where id = new.requisition_id;
        perform notify_role_group(
          new.requisition_id, 'finance',
          case when v_req_type = 'individual' then 'individual_submitted' else 'dept_approved' end
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

-- 2. Configurable Director authorization: 'accountant_discretion' (Finance
-- Accountant decides per requisition, via requires_director_authorization
-- below) or 'amount_threshold' (per-currency amount, admin-configured).
-- Defaults to 'accountant_discretion' with every requisition defaulting to
-- 'yes' — i.e. nothing changes until an admin switches modes or an
-- accountant actively opts a requisition out.
insert into app_settings (key, value) values ('director_auth_mode', 'accountant_discretion')
  on conflict (key) do nothing;

create table director_auth_thresholds (
  currency text primary key,
  threshold_amount numeric(14,2) not null,
  updated_at timestamptz not null default now()
);

create trigger director_auth_thresholds_set_updated_at
  before update on director_auth_thresholds
  for each row execute function set_updated_at();

alter table director_auth_thresholds enable row level security;

create policy director_auth_thresholds_select on director_auth_thresholds for select to authenticated using (true);
create policy director_auth_thresholds_write on director_auth_thresholds for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());

grant select, insert, update, delete on director_auth_thresholds to authenticated;

create function requisition_requires_director(p_requisition_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_mode text;
  v_requisition requisitions;
  v_threshold numeric;
begin
  select value into v_mode from app_settings where key = 'director_auth_mode';
  select * into v_requisition from requisitions where id = p_requisition_id;

  if v_mode = 'amount_threshold' then
    select threshold_amount into v_threshold from director_auth_thresholds where currency = v_requisition.currency;
    if v_threshold is null then
      return true; -- no threshold configured for this currency: safe default
    end if;
    return v_requisition.amount >= v_threshold;
  else
    return coalesce(v_requisition.requires_director_authorization = 'yes', true);
  end if;
end;
$$;

create function notify_finance_cleared_no_director(p_requisition_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_ids uuid[];
begin
  select * into r from requisitions where id = p_requisition_id;
  v_ids := case
    when r.finance_accountant_id is not null then array[r.finance_accountant_id]
    else array(select id from profiles where role = 'finance_accountant' and is_active)
  end;

  perform enqueue_email_for_profiles(
    p_requisition_id, 'finance_cleared_no_director', v_ids,
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'requester_name', (select full_name from profiles where id = r.requester_id),
      'amount', r.amount,
      'currency', r.currency,
      'requisition_link', requisition_link(r.id)
    )
  );
end;
$$;

insert into email_templates (key, subject, html_body) values
('finance_cleared_no_director', 'Requisition {{requisition_number}} cleared — ready for payment', $html$
<p>Hello,</p>
<p>Finance cleared requisition <strong>{{requisition_number}}</strong> from {{requester_name}} for <strong>{{currency}} {{amount}}</strong>. No Director authorization is required for this requisition — it's ready for payment processing.</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$)
on conflict (key) do nothing;

create or replace function advance_stage(p_requisition_id uuid, p_from_stage approval_stage_key)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  case p_from_stage
    when 'department' then
      update requisitions set status = 'finance_review', stage_entered_at = now()
        where id = p_requisition_id;
      perform notify_role_group(p_requisition_id, 'finance', 'dept_approved');

    when 'finance' then
      if requisition_requires_director(p_requisition_id) then
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

-- Lets the Finance Accountant (or admin) set the per-requisition choice
-- under 'accountant_discretion' mode. A dedicated RPC rather than a
-- granted column, so only this role can ever write it — no RLS/grant
-- plumbing needed, mirrors record_approval_action's own-role-check style.
create function set_requires_director_authorization(p_requisition_id uuid, p_actor_id uuid, p_value yes_no)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from profiles where id = p_actor_id and is_active and role in ('finance_accountant', 'admin')
  ) then
    raise exception 'Actor % is not permitted to set Director authorization requirement', p_actor_id;
  end if;

  update requisitions set requires_director_authorization = p_value
    where id = p_requisition_id and status = 'finance_review';
end;
$$;

grant execute on function set_requires_director_authorization(uuid, uuid, yes_no) to authenticated;
