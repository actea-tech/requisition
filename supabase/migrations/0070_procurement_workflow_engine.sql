-- Product/Service (procurement) requisitions get their own, distinctly-
-- named department/finance review (procurement_dept_review /
-- procurement_finance_review) before an invoice exists. Once Finance
-- clears the budget-availability check, the requisition moves to
-- awaiting_invoice; once the requester submits the real invoice/amount, it
-- proceeds into the *ordinary* finance_review — identical in every way to
-- a Payment requisition's own finance_review, including the Director-
-- required decision and everything after it.

-- procurement_dept_review/procurement_finance_review map to the same
-- stage_keys as dept_review/finance_review — record_approval_action's
-- eligibility check and get_pending_approval_requisition_ids both depend
-- on this returning non-null for the new statuses.
create or replace function stage_key_for_status(p_status requisition_status)
returns approval_stage_key
language sql
immutable
as $$
  select case p_status
    when 'dept_review' then 'department'::approval_stage_key
    when 'procurement_dept_review' then 'department'::approval_stage_key
    when 'finance_review' then 'finance'::approval_stage_key
    when 'procurement_finance_review' then 'finance'::approval_stage_key
    when 'director_review' then 'director'::approval_stage_key
    when 'approved_for_payment' then 'payment'::approval_stage_key
    else null
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
    v_status := case when v_requisition_kind = 'procurement' then 'procurement_finance_review' else 'finance_review' end;
  else
    if not exists (select 1 from department_heads where department_id = v_department_id) then
      raise exception 'This department has no department head assigned — raise this as an Individual requisition instead.';
    end if;
    v_stage_key := 'department';
    v_status := case when v_requisition_kind = 'procurement' then 'procurement_dept_review' else 'dept_review' end;
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

-- advance_stage now reads the row's own current status to tell a
-- procurement requisition's first pass through 'department'/'finance'
-- apart from a Payment/Fund requisition's (or a procurement requisition's
-- own *second*, ordinary finance_review pass, post-invoice) — stage_key
-- alone can no longer disambiguate, since procurement_dept_review/
-- procurement_finance_review map to the same stage_keys as dept_review/
-- finance_review.
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
        set status = case when v_status = 'procurement_dept_review' then 'procurement_finance_review' else 'finance_review' end,
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

insert into email_templates (key, subject, html_body) values
('awaiting_invoice', 'Requisition {{requisition_number}} — add the invoice to continue', $html$
<p>Hi {{recipient_name}},</p>
<p>Department and Finance have approved requisition <strong>{{requisition_number}}</strong> for budget availability. Once you have the actual invoice, add it along with the final amount and payee to continue toward payment.</p>
<p><a href="{{requisition_link}}" class="btn">Add invoice</a></p>
$html$)
on conflict (key) do nothing;

-- Bespoke side-flow RPC, mirroring submit_requisition_accounting's
-- precedent — not routed through record_approval_action/evaluate_stage.
create function submit_procurement_invoice(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition requisitions;
  v_requester_is_dept_head boolean;
  v_target_status requisition_status;
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
      when v_requisition.requisition_type = 'individual' or v_requester_is_dept_head then 'procurement_finance_review'
      else 'procurement_dept_review'
    end;

    update requisitions
      set status = v_target_status, invoice_submitted_at = now(), stage_entered_at = now()
      where id = p_requisition_id;

    perform notify_role_group(
      p_requisition_id,
      case when v_target_status = 'procurement_dept_review' then 'department' else 'finance' end,
      'dept_approved'
    );
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

grant execute on function submit_procurement_invoice(uuid, uuid) to authenticated;

-- requires_full_reapproval is a workflow-control flag, not plain content —
-- deliberately not column-granted to authenticated (matching this app's
-- existing convention for status/finance_cleared/director_decision/etc.);
-- only settable through this function, by Finance, only while the
-- requisition is at its first (budget-availability) procurement review.
create function set_requisition_requires_full_reapproval(p_requisition_id uuid, p_actor_id uuid, p_value boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from requisitions where id = p_requisition_id and status = 'procurement_finance_review'
  ) then
    raise exception 'Requisition % is not at Procurement — Finance Review', p_requisition_id;
  end if;
  if not exists (
    select 1 from profiles where id = p_actor_id and is_active and (role in ('finance_accountant', 'finance_assistant') or role = 'admin')
  ) then
    raise exception 'Actor % is not permitted to set this', p_actor_id;
  end if;

  update requisitions set requires_full_reapproval = p_value where id = p_requisition_id;
end;
$$;

grant execute on function set_requisition_requires_full_reapproval(uuid, uuid, boolean) to authenticated;
