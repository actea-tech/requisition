-- Full delegation (migration 0042) already lets a forwarded Assistant see
-- and use the "Requires authorization?" control in the app (page.tsx's
-- canSetDirectorAuthorization), but the RPC it calls still only checked
-- for role in ('finance_accountant', 'admin') — so the click reached the
-- server and was rejected with "Actor <id> is not permitted to set
-- Director authorization requirement." Broaden it to also accept the
-- specific assistant this requisition is currently forwarded to, matching
-- canSetDirectorAuthorization's own scoping exactly.
create or replace function set_requires_director_authorization(p_requisition_id uuid, p_actor_id uuid, p_value yes_no)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
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

-- Same gap, same "full delegation" fix, for managing who else reviews at
-- Finance: canManageFinanceGroup already includes the forwarded Assistant
-- (migration prior to this one), but finance_approver_group_write was never
-- updated to match, so the click would have reached the server and been
-- silently blocked by RLS instead of raising a clear error like the RPC
-- above did.
drop policy finance_approver_group_write on finance_approver_group;
create policy finance_approver_group_write on finance_approver_group for all to authenticated
  using (auth_role() = 'finance_accountant' or auth_is_admin() or auth_is_forwarded_assistant(requisition_id))
  with check (auth_role() = 'finance_accountant' or auth_is_admin() or auth_is_forwarded_assistant(requisition_id));
