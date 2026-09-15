-- The authorization stage (migration 0031) is decided by whoever is
-- selected as an authorizer for that requisition — the Director by
-- default, but possibly a board member or other staff granted authorizer
-- status instead. These four templates still hardcoded "the Director" as
-- if they were always the one deciding; reword to the role-neutral
-- "authorizer(s)", matching how the app already labels this stage
-- ("Authorization", not "Director") everywhere else.
--
-- cancellation_denied is left as-is: decide_cancellation() genuinely
-- restricts that decision to role = 'director' (or admin), so "The
-- Director denied..." is accurate there.
update email_templates set
  subject = 'Requisition {{requisition_number}} returned during authorization',
  html_body = $html$
<p>Hi {{requester_name}},</p>
<p>The authorizer(s) returned requisition <strong>{{requisition_number}}</strong> for correction:</p>
<blockquote>{{comments}}</blockquote>
<p><a href="{{requisition_link}}" class="btn">Update and resubmit</a></p>
$html$
where key = 'director_returned';

update email_templates set
  subject = 'Requisition {{requisition_number}} was rejected during authorization',
  html_body = $html$
<p>Hi {{requester_name}},</p>
<p>The authorizer(s) rejected requisition <strong>{{requisition_number}}</strong>:</p>
<blockquote>{{comments}}</blockquote>
$html$
where key = 'director_rejected';

update email_templates set
  html_body = $html$
<p>Hello,</p>
<p>The authorizer(s) approved requisition <strong>{{requisition_number}}</strong> from {{requester_name}}. It's ready for payment processing.</p>
<p><a href="{{requisition_link}}" class="btn">Process payment</a></p>
$html$
where key = 'director_approved';

update email_templates set
  html_body = $html$
<p>Hello,</p>
<p>Finance cleared requisition <strong>{{requisition_number}}</strong> from {{requester_name}} for <strong>{{currency}} {{amount}}</strong>. No further authorization is required for this requisition — it's ready for payment processing.</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$
where key = 'finance_cleared_no_director';
