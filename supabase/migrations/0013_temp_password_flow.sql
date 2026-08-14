-- Replaces the invite-link flow: admin creates the user with a temporary
-- password directly (no email confirmation link to click), and the user
-- is forced to set a new password on first login.
alter table profiles add column must_change_password boolean not null default true;

create function clear_must_change_password()
returns void
language sql
security definer
set search_path = public
as $$
  update profiles set must_change_password = false where id = auth.uid();
$$;

grant execute on function clear_must_change_password() to authenticated;

update email_templates set
  subject = 'Your ACTEA Requisitions account',
  html_body = $html$
<p>Hi {{full_name}},</p>
<p>An administrator created an ACTEA Requisitions account for you as <strong>{{role_label}}</strong>{{#department_name}} in the {{department_name}} department{{/department_name}}.</p>
<p>Temporary password: <strong>{{temp_password}}</strong></p>
<p><a href="{{login_link}}" class="btn">Sign in</a></p>
<p>You'll be asked to set your own password the first time you log in.</p>
$html$
where key = 'account_invite';
