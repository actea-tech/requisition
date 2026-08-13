-- Security-definer helpers so policies can check the caller's role/department
-- without recursively hitting RLS on `profiles` (definer functions run as
-- the table owner, which isn't subject to its own RLS unless FORCE ROW
-- LEVEL SECURITY is set — it isn't here).
create function auth_role()
returns user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from profiles where id = auth.uid();
$$;

create function auth_department_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select department_id from profiles where id = auth.uid();
$$;

create function auth_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(auth_role() = 'admin', false);
$$;

create function auth_is_finance()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(auth_role() in ('finance_accountant', 'finance_reviewer'), false);
$$;

create function auth_is_dept_head_of(p_department_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from department_heads where department_id = p_department_id and user_id = auth.uid()
  );
$$;

alter table departments enable row level security;
alter table profiles enable row level security;
alter table department_heads enable row level security;
alter table approval_stage_config enable row level security;
alter table form_field_config enable row level security;
alter table requisitions enable row level security;
alter table finance_approver_group enable row level security;
alter table requisition_attachments enable row level security;
alter table approval_actions enable row level security;
alter table email_templates enable row level security;
alter table email_outbox enable row level security;
alter table app_settings enable row level security;

-- departments: everyone signed in can read (needed for the submission
-- form's department picker); only admins manage them.
create policy departments_select on departments for select to authenticated using (true);
create policy departments_write on departments for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());

-- profiles: broad read (colleagues' names/roles aren't sensitive in an
-- internal tool and are needed everywhere approver names are shown);
-- a user may update their own non-role fields, admins manage everyone.
create policy profiles_select on profiles for select to authenticated using (true);
create policy profiles_update_self on profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid() and role = auth_role() and department_id is not distinct from auth_department_id());
create policy profiles_admin_write on profiles for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());

-- Role/department reassignment is deliberately NOT reachable via the
-- browser's authenticated client, even for admins — the Settings > Users
-- admin UI performs those through a Server Action using the service-role
-- client (lib/supabase/admin.ts), which bypasses RLS and grants entirely.
-- This keeps "who can grant roles" auditable at the app layer rather than
-- relying solely on an RLS predicate.
-- full_name is the only column a user may ever touch on their own row —
-- notably NOT is_active: if it were grantable, a user an admin just
-- deactivated could simply set it back to true themselves.
revoke all on profiles from authenticated;
grant select on profiles to authenticated;
grant update (full_name) on profiles to authenticated;

create policy department_heads_select on department_heads for select to authenticated using (true);
create policy department_heads_write on department_heads for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());

create policy approval_stage_config_select on approval_stage_config for select to authenticated using (true);
create policy approval_stage_config_write on approval_stage_config for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());

create policy form_field_config_select on form_field_config for select to authenticated using (true);
create policy form_field_config_write on form_field_config for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());

create policy app_settings_select on app_settings for select to authenticated using (true);
create policy app_settings_write on app_settings for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());

-- requisitions: the core access-control rule from the requirements doc —
-- staff submit/view their own, dept heads see their department's requests
-- once submitted, Finance/Director/Admin see everything from the point
-- it's relevant to them onward (kept simple as "see everything" for those
-- three roles rather than re-deriving per-stage visibility, since they're
-- also the audit/export roles).
create policy requisitions_select on requisitions for select to authenticated
  using (
    requester_id = auth.uid()
    or auth_is_admin()
    or auth_is_finance()
    or auth_role() = 'director'
    or (auth_role() = 'dept_head' and auth_is_dept_head_of(department_id))
  );

create policy requisitions_insert on requisitions for insert to authenticated
  with check (
    requester_id = auth.uid()
    and department_id is not distinct from auth_department_id()
    and status = 'draft'
  );

-- Row-level gating below is only half the story: `status`, `finance_cleared`,
-- `director_decision`, `finance_accountant_id`, `director_id`, and the
-- other workflow-control columns are deliberately left out of the column
-- GRANTs further down, so only the SECURITY DEFINER engine functions
-- (record_approval_action / submit_requisition / advance_stage / ...) can
-- ever change them — a direct client-side UPDATE naming those columns is
-- rejected by Postgres before RLS even runs. Without that, a Finance user
-- could otherwise set status straight from 'finance_review' to
-- 'approved_for_payment' in one UPDATE, skipping Director authorization
-- entirely, since both values satisfy this row policy.
create policy requisitions_update on requisitions for update to authenticated
  using (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_role() = 'dept_head' and auth_is_dept_head_of(department_id) and status = 'dept_review')
  )
  with check (
    (requester_id = auth.uid() and status in ('draft', 'returned'))
    or auth_is_admin()
    or (auth_is_finance() and status in ('finance_review', 'approved_for_payment'))
    or (auth_role() = 'director' and status = 'director_review')
    or (auth_role() = 'dept_head' and auth_is_dept_head_of(department_id) and status = 'dept_review')
  );

create policy requisitions_delete on requisitions for delete to authenticated
  using (requester_id = auth.uid() and status = 'draft');

-- Column-level grants: the actual field-level firewall referenced above.
-- Table-wide privileges (SELECT/INSERT/UPDATE/DELETE) still apply and are
-- combined with these — Postgres requires both a column grant AND a
-- passing RLS policy for a write to succeed.
revoke all on requisitions from authenticated;
grant select, delete on requisitions to authenticated;
grant insert (
  requester_id, department_id, purpose, activity_project,
  payee_name, payee_contact, amount, currency, payment_mode,
  budget_line, account_code, project_fund_class_code, donor_grant_source, budgeted,
  procurement_required, donor_restriction, outstanding_advance
) on requisitions to authenticated;
grant update (
  purpose, activity_project,
  payee_name, payee_contact, amount, currency, payment_mode,
  budget_line, account_code, project_fund_class_code, donor_grant_source, budgeted,
  procurement_required, donor_restriction, outstanding_advance,
  finance_comments, budget_available,
  director_comments,
  payment_voucher_number, qbo_posting_reference, payment_status
) on requisitions to authenticated;

create policy finance_approver_group_select on finance_approver_group for select to authenticated
  using (auth_is_finance() or auth_role() = 'director' or auth_is_admin());
create policy finance_approver_group_write on finance_approver_group for all to authenticated
  using (auth_is_finance() or auth_is_admin()) with check (auth_is_finance() or auth_is_admin());

create policy requisition_attachments_select on requisition_attachments for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = requisition_attachments.requisition_id
         and (
           r.requester_id = auth.uid()
           or auth_is_admin() or auth_is_finance() or auth_role() = 'director'
           or (auth_role() = 'dept_head' and auth_is_dept_head_of(r.department_id))
         )
    )
  );
create policy requisition_attachments_insert on requisition_attachments for insert to authenticated
  with check (
    uploaded_by = auth.uid()
    and exists (
      select 1 from requisitions r
       where r.id = requisition_attachments.requisition_id
         and (r.requester_id = auth.uid() or auth_is_finance() or auth_is_admin())
    )
  );
create policy requisition_attachments_delete on requisition_attachments for delete to authenticated
  using (uploaded_by = auth.uid() or auth_is_admin());

-- approval_actions: written only through the SECURITY DEFINER engine
-- functions (record_approval_action / submit_requisition / etc.), which
-- run as the table owner and so bypass this policy for INSERT. This policy
-- only needs to cover SELECT, for the audit trail / requisition timeline.
create policy approval_actions_select on approval_actions for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = approval_actions.requisition_id
         and (
           r.requester_id = auth.uid()
           or auth_is_admin() or auth_is_finance() or auth_role() = 'director'
           or (auth_role() = 'dept_head' and auth_is_dept_head_of(r.department_id))
         )
    )
  );

-- email_templates / email_outbox: admin/service-role only. Nothing here is
-- needed by the regular UI (the Edge Function uses the service role key,
-- which bypasses RLS entirely).
create policy email_templates_admin on email_templates for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());
create policy email_outbox_admin on email_outbox for select to authenticated
  using (auth_is_admin());
