-- Display-name-only rename (lib/roles.ts): "Finance Accountant" -> "Finance
-- Lead", "Assistant Finance Accountant" -> "Finance Assistant". The role
-- enum values (finance_accountant/finance_assistant) are unchanged — this
-- only updates the two email template bodies that spell the old name out.
update email_templates set
  html_body = $html$
<p>Hi {{recipient_name}},</p>
<p>Requisition <strong>{{requisition_number}}</strong> from {{requester_name}} ({{department_name}}) for <strong>{{currency}} {{amount}}</strong> has reached Finance review. No action is needed from you at this time — the Finance Lead will handle it, or forward it to you if needed.</p>
<p><a href="{{requisition_link}}" class="btn">View requisition</a></p>
$html$
where key = 'finance_assistant_no_action_needed';

update email_templates set
  html_body = $html$
<p>Hi {{recipient_name}},</p>
<p>The Finance Lead forwarded requisition <strong>{{requisition_number}}</strong> from {{requester_name}} ({{department_name}}) for <strong>{{currency}} {{amount}}</strong> to you for approval.</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$
where key = 'finance_assistant_forwarded';
