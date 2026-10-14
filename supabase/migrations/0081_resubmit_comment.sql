-- The person resubmitting a returned requisition can add an (optional)
-- comment, which is recorded on the 'submitted' entry in the audit trail
-- (where approvers see it alongside why it was returned).
--
-- Drop the old two-argument version first: leaving both would make a call
-- with just the two original arguments ambiguous between the overloads.
drop function resubmit_requisition(uuid, uuid);

create function resubmit_requisition(p_requisition_id uuid, p_actor_id uuid, p_comments text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_returned_from requisition_status;
begin
  select status, returned_from_stage into v_status, v_returned_from
    from requisitions where id = p_requisition_id;

  if v_status <> 'returned' or v_returned_from is null then
    raise exception 'Requisition % is not returned (status: %)', p_requisition_id, v_status;
  end if;

  update requisitions
    set status = v_returned_from, returned_from_stage = null, return_reason = null, stage_entered_at = now()
    where id = p_requisition_id;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
  values (
    p_requisition_id,
    stage_key_for_status(v_returned_from),
    p_actor_id,
    'submitted',
    nullif(btrim(p_comments), '')
  );
end;
$$;

grant execute on function resubmit_requisition(uuid, uuid, text) to authenticated;
