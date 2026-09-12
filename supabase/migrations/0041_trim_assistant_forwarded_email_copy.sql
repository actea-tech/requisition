update email_templates set
  html_body = $html$
<p>Hi {{recipient_name}},</p>
<p>The Finance Accountant forwarded requisition <strong>{{requisition_number}}</strong> from {{requester_name}} ({{department_name}}) for <strong>{{currency}} {{amount}}</strong> to you for approval.</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$
where key = 'finance_assistant_forwarded';
