-- requires_full_reapproval previously restarted the requisition at
-- procurement_dept_review/procurement_finance_review — the exact same
-- statuses as the original pre-invoice pass. Two problems with that:
-- 1. Finance re-approving that redo at procurement_finance_review sent it
--    back to awaiting_invoice again (advance_stage's 'finance' case keys
--    purely off the status, with no way to tell the redo apart from the
--    original pass) — asking for the invoice a second time even though
--    it already exists.
-- 2. It displayed as "Procurement — X Review" again, reading as if the
--    invoice/estimate step was being redone, when it's actually reviewing
--    the real, final numbers.
--
-- Reapproval now targets the plain dept_review/finance_review statuses
-- instead — the exact same ones an ordinary Payment requisition uses —
-- so it reads as a normal "Department Review" positioned after Awaiting
-- Invoice, and advance_stage's existing (unchanged) logic naturally falls
-- through to the ordinary finance_review once that's cleared, with no
-- special-casing needed there at all. A requester with no department
-- head to re-approve (individual, or departmental where the requester is
-- the department head) has nothing to redo, so reapproval is a no-op for
-- them — straight to finance_review, same as when it's unchecked.
--
-- This also happens to remove the only call site that needed the
-- enum-cast workaround from the previous version of this migration — the
-- case expression it was wrapped around no longer exists.
create or replace function submit_procurement_invoice(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition requisitions;
  v_requester_is_dept_head boolean;
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

  v_requester_is_dept_head := exists (
    select 1 from department_heads
     where department_id = v_requisition.department_id and user_id = v_requisition.requester_id
  );

  if v_requisition.requires_full_reapproval
     and v_requisition.requisition_type = 'departmental'
     and not v_requester_is_dept_head then
    update requisitions
      set status = 'dept_review', invoice_submitted_at = now(), stage_entered_at = now()
      where id = p_requisition_id;
    perform notify_role_group(p_requisition_id, 'department', 'dept_approved');
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
