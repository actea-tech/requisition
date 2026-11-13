-- Recall: the requester can pull a submitted requisition back to themselves.
--
--  * Directly, while it is with the department head / supervisors, or at
--    Finance Review before Finance has acted on it.
--  * By request once Finance has acted (Finance Review after Finance acted,
--    Authorization, Payment Processing): Finance approves or declines.
--  * A recalled requisition goes back to the requester ("Returned for
--    correction"), restarts from the first review when resubmitted (routed as a
--    fresh submission, so a changed kind/type takes the right first stage),
--    and can be cancelled by the requester instead.
--
-- Run 0091 first (adds the new approval_decision values).

alter table requisitions
  add column recalled boolean not null default false,
  add column recall_request_status text check (recall_request_status in ('requested', 'declined')),
  add column recall_reason text,
  add column recall_requested_at timestamptz;

-- Finance has "acted" on a requisition at Finance Review when any Finance
-- approver has recorded a decision this round, or it carries Finance's own
-- work: review fields filled in, the authorization choice changed, extra
-- reviewers or authorizers added, or it was forwarded to an Assistant.
-- Merely opening it does not count.
create function requisition_finance_has_acted(p_requisition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from requisitions r
     where r.id = p_requisition_id
       and (
         nullif(btrim(coalesce(r.finance_comments, '')), '') is not null
         or r.budget_available is not null
         or nullif(btrim(coalesce(r.budget_line, '')), '') is not null
         or nullif(btrim(coalesce(r.account_code, '')), '') is not null
         or nullif(btrim(coalesce(r.project_fund_class_code, '')), '') is not null
         or nullif(btrim(coalesce(r.donor_grant_source, '')), '') is not null
         or r.budgeted is not null
         or r.procurement_required is not null
         or r.donor_restriction is not null
         or r.outstanding_advance is not null
         or r.requires_director_authorization <> 'yes'
         or r.finance_accountant_id is not null
         or exists (select 1 from finance_approver_group g where g.requisition_id = r.id)
         or exists (select 1 from finance_assistant_forwards f where f.requisition_id = r.id)
         or exists (select 1 from requisition_authorizers a where a.requisition_id = r.id)
         or exists (
           select 1 from approval_actions a
            where a.requisition_id = r.id
              and a.stage_key = 'finance'
              and a.decision in ('approved', 'returned', 'rejected')
              and a.created_at >= r.stage_entered_at
         )
       )
  );
$$;

-- What the signed-in requester can do about recalling this requisition right
-- now: 'recall' (pull it back), 'request' (ask Finance), or 'none'.
create function requisition_recall_option(p_requisition_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  r requisitions;
begin
  select * into r from requisitions where id = p_requisition_id;
  if r.id is null or r.requester_id is distinct from auth.uid() then
    return 'none';
  end if;
  -- A consolidated payment is raised by Finance and handled by Finance.
  if r.requisition_kind = 'consolidated' then
    return 'none';
  end if;
  if coalesce(r.cancellation_status, '') = 'requested' or r.recall_request_status = 'requested' then
    return 'none';
  end if;

  if r.status in ('dept_review', 'procurement_dept_review') then
    return 'recall';
  elsif r.status in ('finance_review', 'procurement_finance_review') then
    return case when requisition_finance_has_acted(r.id) then 'request' else 'recall' end;
  elsif r.status in ('director_review', 'approved_for_payment') then
    return 'request';
  end if;
  return 'none';
end;
$$;

grant execute on function requisition_recall_option(uuid) to authenticated;

-- Pulls the requisition back to the requester. Internal: callers check who may.
create function apply_requisition_recall(
  p_requisition_id uuid,
  p_actor_id uuid,
  p_decision approval_decision,
  p_comment text,
  p_return_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_handlers uuid[];
  v_requester_name text;
begin
  select * into r from requisitions where id = p_requisition_id;

  -- Who it was with (worked out before the status changes).
  v_handlers := array(
    select distinct h from requisition_current_handler_ids(p_requisition_id) h where h <> r.requester_id
  );

  -- Restart from the top: where a fresh submission would land is decided again
  -- at resubmit, so a changed kind or type is respected.
  update requisitions
     set status = 'returned',
         return_to = 'requester',
         requires_reapproval = true,
         returned_from_stage = restart_status_for(p_requisition_id, r.requisition_kind = 'procurement'),
         return_reason = p_return_reason,
         recalled = true,
         recall_request_status = null,
         finance_cleared = false,
         director_decision = null
   where id = p_requisition_id;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
  values (p_requisition_id, coalesce(stage_key_for_status(r.status), 'finance'), p_actor_id, p_decision, p_comment);

  select full_name into v_requester_name from profiles where id = r.requester_id;
  perform enqueue_email_for_profiles(
    p_requisition_id, 'recalled', v_handlers,
    jsonb_build_object(
      'requisition_number', coalesce(r.requisition_number, 'New requisition'),
      'requester_name', v_requester_name,
      'comments', p_return_reason,
      'requisition_link', requisition_link(p_requisition_id)
    )
  );
end;
$$;

revoke execute on function apply_requisition_recall(uuid, uuid, approval_decision, text, text) from public, anon, authenticated;

-- The requester pulls it back themselves.
create function recall_requisition(p_requisition_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_option text;
begin
  select * into r from requisitions where id = p_requisition_id;
  if r.id is null then
    raise exception 'Requisition not found';
  end if;
  if r.requester_id is distinct from auth.uid() then
    raise exception 'Only the person who raised a requisition can recall it';
  end if;
  if v_reason is null then
    raise exception 'A reason is required to recall a requisition';
  end if;
  if char_length(v_reason) > 2000 then
    raise exception 'The reason can be at most 2000 characters';
  end if;

  v_option := requisition_recall_option(p_requisition_id);
  if v_option = 'request' then
    raise exception 'Finance has already acted on this requisition - ask Finance to approve a recall instead';
  elsif v_option <> 'recall' then
    raise exception 'This requisition can''t be recalled right now';
  end if;

  perform apply_requisition_recall(
    p_requisition_id, auth.uid(), 'recalled', v_reason, 'Recalled by the requester: ' || v_reason
  );
end;
$$;

grant execute on function recall_requisition(uuid, text) to authenticated;

-- Once Finance has acted: the requester asks, Finance decides.
create function request_requisition_recall(p_requisition_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_requester_name text;
begin
  select * into r from requisitions where id = p_requisition_id;
  if r.id is null then
    raise exception 'Requisition not found';
  end if;
  if r.requester_id is distinct from auth.uid() then
    raise exception 'Only the person who raised a requisition can ask for it to be recalled';
  end if;
  if v_reason is null then
    raise exception 'A reason is required';
  end if;
  if char_length(v_reason) > 2000 then
    raise exception 'The reason can be at most 2000 characters';
  end if;
  if requisition_recall_option(p_requisition_id) <> 'request' then
    raise exception 'A recall can''t be requested for this requisition right now';
  end if;

  update requisitions
     set recall_request_status = 'requested', recall_reason = v_reason, recall_requested_at = now()
   where id = p_requisition_id;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
  values (p_requisition_id, coalesce(stage_key_for_status(r.status), 'finance'), auth.uid(), 'recall_requested', v_reason);

  select full_name into v_requester_name from profiles where id = r.requester_id;
  perform enqueue_email_for_profiles(
    p_requisition_id, 'recall_requested',
    array(
      select p.id from profiles p
       where p.is_active and p.role in ('finance_accountant', 'finance_assistant') and p.is_test_user = r.is_test
    ),
    jsonb_build_object(
      'requisition_number', coalesce(r.requisition_number, 'New requisition'),
      'requester_name', v_requester_name,
      'status_label', requisition_status_label(r.status),
      'comments', v_reason,
      'requisition_link', requisition_link(p_requisition_id)
    )
  );
end;
$$;

grant execute on function request_requisition_recall(uuid, text) to authenticated;

-- Finance approves (it is recalled) or declines (it carries on) a request.
create function decide_recall_request(p_requisition_id uuid, p_approve boolean, p_comment text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_role text;
  v_comment text := nullif(btrim(coalesce(p_comment, '')), '');
  v_requester_name text;
begin
  select role::text into v_role from profiles where id = auth.uid() and is_active;
  if v_role is null or v_role not in ('finance_accountant', 'finance_assistant', 'admin') then
    raise exception 'Only Finance can decide a recall request';
  end if;

  select * into r from requisitions where id = p_requisition_id;
  if r.id is null then
    raise exception 'Requisition not found';
  end if;
  if r.recall_request_status is distinct from 'requested' then
    raise exception 'There is no recall request waiting on this requisition';
  end if;
  if r.requester_id = auth.uid() and v_role <> 'admin' then
    raise exception 'You can''t decide a recall request on your own requisition';
  end if;
  if v_comment is not null and char_length(v_comment) > 2000 then
    raise exception 'The comment can be at most 2000 characters';
  end if;

  select full_name into v_requester_name from profiles where id = r.requester_id;

  if p_approve then
    if r.status not in ('finance_review', 'procurement_finance_review', 'director_review', 'approved_for_payment') then
      raise exception 'This requisition has moved on (now: %) and can no longer be recalled', r.status;
    end if;
    if coalesce(r.cancellation_status, '') = 'requested' then
      raise exception 'A cancellation is waiting on this requisition - decide that first';
    end if;

    perform apply_requisition_recall(
      p_requisition_id, auth.uid(), 'recall_approved',
      coalesce(v_comment, 'Recall approved'),
      'Recall approved by Finance. Reason given: ' || coalesce(r.recall_reason, '')
    );
    perform enqueue_email_for_profiles(
      p_requisition_id, 'recall_approved', array[r.requester_id],
      jsonb_build_object(
        'requisition_number', coalesce(r.requisition_number, 'New requisition'),
        'requester_name', v_requester_name,
        'comments', v_comment,
        'requisition_link', requisition_link(p_requisition_id)
      )
    );
  else
    if v_comment is null then
      raise exception 'A reason is required to decline a recall request';
    end if;
    update requisitions set recall_request_status = 'declined' where id = p_requisition_id;
    insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
    values (p_requisition_id, coalesce(stage_key_for_status(r.status), 'finance'), auth.uid(), 'recall_declined', v_comment);
    perform enqueue_email_for_profiles(
      p_requisition_id, 'recall_declined', array[r.requester_id],
      jsonb_build_object(
        'requisition_number', coalesce(r.requisition_number, 'New requisition'),
        'requester_name', v_requester_name,
        'comments', v_comment,
        'requisition_link', requisition_link(p_requisition_id)
      )
    );
  end if;
end;
$$;

grant execute on function decide_recall_request(uuid, boolean, text) to authenticated;

-- After recalling, the requester can cancel it instead (it was a mistake).
create function cancel_own_recalled_requisition(p_requisition_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  select * into r from requisitions where id = p_requisition_id;
  if r.id is null then
    raise exception 'Requisition not found';
  end if;
  if r.requester_id is distinct from auth.uid() then
    raise exception 'Only the person who raised a requisition can cancel it this way';
  end if;
  if r.status <> 'returned' or not r.recalled then
    raise exception 'Only a requisition you have recalled can be cancelled this way';
  end if;
  if v_reason is null then
    raise exception 'A reason is required to cancel a requisition';
  end if;
  if char_length(v_reason) > 2000 then
    raise exception 'The reason can be at most 2000 characters';
  end if;

  update requisitions
     set status = 'cancelled', cancellation_reason = v_reason, recalled = false, recall_request_status = null
   where id = p_requisition_id;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
  values (
    p_requisition_id,
    coalesce(stage_key_for_status(r.returned_from_stage), 'department'),
    auth.uid(), 'cancelled', v_reason
  );
end;
$$;

grant execute on function cancel_own_recalled_requisition(uuid, text) to authenticated;

-- Resubmitting a recalled requisition: routed as a fresh submission (so a changed
-- kind or type takes the right first stage).
create or replace function resubmit_requisition(p_requisition_id uuid, p_actor_id uuid, p_comments text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_returned_from requisition_status;
  v_target requisition_status;
  v_recalled boolean;
  v_kind text;
begin
  select status, returned_from_stage, recalled, requisition_kind
    into v_status, v_returned_from, v_recalled, v_kind
    from requisitions where id = p_requisition_id;

  if v_status <> 'returned' or v_returned_from is null then
    raise exception 'Requisition % is not returned (status: %)', p_requisition_id, v_status;
  end if;

  -- Recalled: start over from the first review, routed as a fresh submission
  -- (the kind or type may have changed since).
  if v_recalled then
    v_target := restart_status_for(p_requisition_id, v_kind = 'procurement');
    update requisitions
      set status = v_target, returned_from_stage = null, return_reason = null, stage_entered_at = now(),
          recalled = false, recall_request_status = null
      where id = p_requisition_id;
    insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
    values (p_requisition_id, stage_key_for_status(v_target), p_actor_id, 'submitted', nullif(btrim(p_comments), ''));
    return;
  end if;

  v_target := v_returned_from;
  if v_returned_from in ('dept_review', 'procurement_dept_review')
     and not department_stage_applies(p_requisition_id) then
    v_target := restart_status_for(p_requisition_id, v_returned_from = 'procurement_dept_review');
  end if;

  update requisitions
    set status = v_target, returned_from_stage = null, return_reason = null, stage_entered_at = now()
    where id = p_requisition_id;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
  values (
    p_requisition_id,
    stage_key_for_status(v_target),
    p_actor_id,
    'submitted',
    nullif(btrim(p_comments), '')
  );
end;
$$;

-- The people copied in hear it was recalled, not just "returned".
create or replace function notify_copied_in_on_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[];
  v_requester_name text;
  v_event text;
  v_comments text;
begin
  if new.status = 'draft' then
    return new;
  end if;

  select array_agg(user_id) into v_ids from requisition_copied_in where requisition_id = new.id;
  if v_ids is null then
    return new;
  end if;

  v_event := case
    when old.status = 'draft' then 'was submitted and is now at ' || requisition_status_label(new.status)
    when old.status = 'returned' and new.status not in ('rejected', 'cancelled')
      then 'was resubmitted and is now at ' || requisition_status_label(new.status)
    when new.status = 'returned' and new.recalled and not old.recalled then 'was recalled by the requester for changes'
    when new.status = 'returned' then 'was returned to the requester for correction'
    when new.status = 'rejected' then 'was rejected'
    when new.status = 'cancelled' then 'was cancelled'
    when new.status = 'approved_for_payment' then 'was authorized and is now at Payment Processing'
    when new.status = 'paid_posted' then 'was marked as paid'
    when new.status = 'posted_and_closed' then 'was posted and closed'
    else 'moved from ' || requisition_status_label(old.status) || ' to ' || requisition_status_label(new.status)
  end;

  if new.status in ('returned', 'rejected', 'cancelled') then
    select a.comments into v_comments
      from approval_actions a
     where a.requisition_id = new.id and a.decision in ('returned', 'rejected', 'cancelled', 'recalled', 'recall_approved')
     order by a.created_at desc
     limit 1;
  end if;

  select full_name into v_requester_name from profiles where id = new.requester_id;

  perform enqueue_email_for_profiles(
    new.id, 'copied_in_update', v_ids,
    jsonb_build_object(
      'requisition_number', coalesce(new.requisition_number, 'New requisition'),
      'requester_name', v_requester_name,
      'purpose', new.purpose,
      'status_label', requisition_status_label(new.status),
      'event', v_event,
      'comments', v_comments,
      'requisition_link', requisition_link(new.id)
    )
  );

  return new;
end;
$$;

insert into email_templates (key, subject, html_body) values
('recalled', 'Requisition {{requisition_number}} was recalled by the requester', $html$
<p>Hi {{recipient_name}},</p>
<p><strong>{{requester_name}}</strong> recalled requisition <strong>{{requisition_number}}</strong>. No action is needed from you now - it will come back once they have made their changes.</p>
{{#comments}}<blockquote>{{comments}}</blockquote>{{/comments}}
$html$),
('recall_requested', 'Recall requested for requisition {{requisition_number}}', $html$
<p>Hi {{recipient_name}},</p>
<p><strong>{{requester_name}}</strong> asks to recall requisition <strong>{{requisition_number}}</strong>, which is at <strong>{{status_label}}</strong>. Approve or decline the request on the requisition.</p>
{{#comments}}<blockquote>{{comments}}</blockquote>{{/comments}}
<p><a href="{{requisition_link}}" class="btn">Review request</a></p>
$html$),
('recall_approved', 'Your recall of requisition {{requisition_number}} was approved', $html$
<p>Hi {{recipient_name}},</p>
<p>Finance approved your request to recall requisition <strong>{{requisition_number}}</strong>. It is back with you: make your changes and resubmit it, or cancel it.</p>
{{#comments}}<blockquote>{{comments}}</blockquote>{{/comments}}
<p><a href="{{requisition_link}}" class="btn">Open requisition</a></p>
$html$),
('recall_declined', 'Your recall request for requisition {{requisition_number}} was declined', $html$
<p>Hi {{recipient_name}},</p>
<p>Finance declined your request to recall requisition <strong>{{requisition_number}}</strong>. It carries on as before.</p>
{{#comments}}<blockquote>{{comments}}</blockquote>{{/comments}}
<p><a href="{{requisition_link}}" class="btn">View requisition</a></p>
$html$)
on conflict (key) do nothing;
