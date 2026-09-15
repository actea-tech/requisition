-- Second, separate step after marking a requisition Paid: the Accountant
-- may legitimately wait on further bank documents before actually posting
-- to QBO and closing it out, even for a plain Payment Requisition, so this
-- is its own explicit action rather than being folded into
-- complete_payment_processing's 'completed' decision.
create function mark_posted_and_closed(p_requisition_id uuid, p_actor_id uuid, p_comments text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from profiles where id = p_actor_id and is_active and role in ('finance_accountant', 'finance_assistant', 'admin')
  ) then
    raise exception 'Actor % is not permitted to mark a requisition posted and closed', p_actor_id;
  end if;

  update requisitions set status = 'posted_and_closed'
    where id = p_requisition_id and status = 'paid_posted';

  if not found then
    raise exception 'Requisition % is not ready to be posted and closed', p_requisition_id;
  end if;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
  values (p_requisition_id, 'payment', p_actor_id, 'posted_and_closed', p_comments);
end;
$$;

grant execute on function mark_posted_and_closed(uuid, uuid, text) to authenticated;
