-- Migration 0072 already fixed this exact enum-cast gotcha once — a CASE
-- expression whose every branch is a plain string literal resolves to
-- type text, not the enum type a function parameter expects — but
-- migration 0073 (adding the invoice-amount check) re-declared this whole
-- function from an older, unfixed copy and silently reintroduced it.
-- Reapplying 0072's casts: requisition_status for v_target_status, and
-- approval_stage_key inline in the notify_role_group call (only reached
-- when requires_full_reapproval is set, which is why this regression went
-- unnoticed until now — "function notify_role_group(uuid, text, unknown)
-- does not exist").
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
  if v_requisition.amount is null then
    raise exception 'Enter the invoice amount before submitting.';
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

    update requisitions
      set status = v_target_status, invoice_submitted_at = now(), stage_entered_at = now()
      where id = p_requisition_id;

    perform notify_role_group(
      p_requisition_id,
      case when v_target_status = 'procurement_dept_review' then 'department'::approval_stage_key else 'finance'::approval_stage_key end,
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
