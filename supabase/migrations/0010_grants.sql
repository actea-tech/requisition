-- Recent Supabase projects default to NOT auto-exposing new tables/views/
-- functions to the Data API (anon/authenticated/service_role) without an
-- explicit GRANT (see the auto_expose_new_tables note in supabase/config.toml).
-- RLS policies alone don't help if the role has no grant to reach the table
-- or call the function in the first place, so state every grant explicitly
-- rather than depend on which default is active for this project.
grant usage on schema public to anon, authenticated, service_role;

grant select on departments, department_heads, approval_stage_config, form_field_config, app_settings
  to authenticated;

grant select, insert, update, delete on finance_approver_group to authenticated;
grant select, insert, delete on requisition_attachments to authenticated;
grant select on approval_actions to authenticated;
grant select, insert, update, delete on email_templates to authenticated;
grant select on email_outbox to authenticated;

-- RLS policies call these directly as the querying role (not from inside an
-- already-elevated function), so `authenticated` needs EXECUTE on them.
grant execute on function auth_role() to authenticated;
grant execute on function auth_department_id() to authenticated;
grant execute on function auth_is_admin() to authenticated;
grant execute on function auth_is_finance() to authenticated;
grant execute on function auth_is_dept_head_of(uuid) to authenticated;

-- App-facing entry points into the workflow engine.
grant execute on function submit_requisition(uuid, uuid) to authenticated;
grant execute on function resubmit_requisition(uuid, uuid) to authenticated;
grant execute on function record_approval_action(uuid, uuid, approval_decision, text) to authenticated;
grant execute on function complete_payment_processing(uuid, uuid, text) to authenticated;

-- Called by the admin invite Server Action via the service-role client. In
-- most Supabase projects service_role already gets this by default, but
-- state it explicitly rather than depend on that.
grant execute on function enqueue_email(uuid, text, text[], jsonb, text[]) to service_role;
