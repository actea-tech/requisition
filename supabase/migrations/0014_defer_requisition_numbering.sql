-- Requisition numbers were assigned at draft-creation time, so abandoned
-- drafts burned a number and left permanent gaps in the sequence (e.g.
-- REQ-2026-0004 never existing because someone started, then dropped, a
-- draft). Numbers are now assigned only on first submit.
alter table requisitions alter column requisition_number drop not null;
alter table requisitions alter column requisition_number drop default;

create or replace function submit_requisition(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
begin
  select status into v_status from requisitions where id = p_requisition_id;

  if v_status <> 'draft' then
    raise exception 'Requisition % is not a draft (status: %)', p_requisition_id, v_status;
  end if;

  update requisitions
    set status = 'dept_review',
        stage_entered_at = now(),
        submitted_at = coalesce(submitted_at, now()),
        requisition_number = coalesce(requisition_number, next_requisition_number())
    where id = p_requisition_id;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision)
  values (p_requisition_id, 'department', p_actor_id, 'submitted');
end;
$$;
