-- Lets an admin pause new requisitions platform-wide (e.g. during
-- maintenance, or to get key approvers set up before intake reopens),
-- without touching anything already in flight. On by default so nothing
-- changes until an admin explicitly turns it off from
-- Settings > Approval Rules. Admins can still raise requisitions while
-- it's off, so they can verify setup before reopening intake to everyone
-- else.
insert into app_settings (key, value) values ('new_requisitions_enabled', 'yes')
  on conflict (key) do nothing;

create function app_new_requisitions_enabled()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select value from app_settings where key = 'new_requisitions_enabled') = 'yes', true);
$$;

grant execute on function app_new_requisitions_enabled() to authenticated;

-- Defense in depth alongside the app layer (the New Requisition page shows
-- a maintenance message instead of creating a draft): the matching
-- server-side check so the insert can't be done directly, bypassing the UI.
drop policy requisitions_insert on requisitions;
create policy requisitions_insert on requisitions for insert to authenticated
  with check (
    requester_id = auth.uid()
    and department_id is not distinct from auth_department_id()
    and status = 'draft'
    and (auth_is_admin() or app_new_requisitions_enabled())
  );
