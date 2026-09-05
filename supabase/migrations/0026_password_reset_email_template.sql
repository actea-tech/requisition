-- Used when an admin resets an already-active user's password (as opposed
-- to 'account_invite', reused for resending a never-signed-in user's
-- original setup details — see resetUserPassword() in
-- app/(dashboard)/settings/users/actions.ts).
insert into email_templates (key, subject, html_body) values
('password_reset', 'Your ACTEA Requisitions password has been reset', $html$
<p>Hi {{full_name}},</p>
<p>An administrator reset your ACTEA Requisitions password.</p>
<p>Temporary password: <strong>{{temp_password}}</strong></p>
<p><a href="{{login_link}}" class="btn">Sign in</a></p>
<p>You'll be asked to set your own password the next time you sign in.</p>
$html$)
on conflict (key) do nothing;
