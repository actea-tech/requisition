-- Drop the "it's above your threshold" framing — just tell the Assistant
-- plainly that no action is needed from them right now.
update email_templates set
  html_body = $html$
<p>Hi {{recipient_name}},</p>
<p>Requisition <strong>{{requisition_number}}</strong> from {{requester_name}} ({{department_name}}) for <strong>{{currency}} {{amount}}</strong> has reached Finance review. No action is needed from you at this time — the Finance Accountant will handle it, or forward it to you if needed.</p>
<p><a href="{{requisition_link}}" class="btn">View requisition</a></p>
$html$
where key = 'finance_assistant_no_action_needed';
