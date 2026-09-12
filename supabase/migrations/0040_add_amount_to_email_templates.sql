-- dept_approved (the main "please review" email Finance gets when a
-- department clears a requisition), stage_returned (Finance notified when
-- Director sends it back to them), and return_fyi (Finance's FYI copy when
-- Director returns straight to the requester) have never mentioned the
-- amount — notify_role_group()/notify_requester() have always included
-- {{amount}}/{{currency}} in the payload, the templates just never
-- referenced them.
update email_templates set
  html_body = $html$
<p>Hi {{recipient_name}},</p>
<p>Requisition <strong>{{requisition_number}}</strong> from {{requester_name}} ({{department_name}}) for <strong>{{currency}} {{amount}}</strong> was approved at department level and needs Finance review.</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$
where key = 'dept_approved';

update email_templates set
  html_body = $html$
<p>Hi {{recipient_name}},</p>
<p>Requisition <strong>{{requisition_number}}</strong> from {{requester_name}} for <strong>{{currency}} {{amount}}</strong> was sent back to you for correction before it can continue.</p>
{{#comments}}<blockquote>{{comments}}</blockquote>{{/comments}}
<p><a href="{{requisition_link}}" class="btn">Review and resubmit</a></p>
$html$
where key = 'stage_returned';

update email_templates set
  html_body = $html$
<p>Hi {{recipient_name}},</p>
<p>Requisition <strong>{{requisition_number}}</strong> from {{requester_name}} for <strong>{{currency}} {{amount}}</strong> was returned for correction. No action is needed from you right now.</p>
{{#comments}}<blockquote>{{comments}}</blockquote>{{/comments}}
$html$
where key = 'return_fyi';
