-- Lets the Finance Accountant/Assistant/admin cancel a requisition outright
-- before it's been fully authorized. Once it's already at
-- approved_for_payment, cancelling instead requires the one active
-- Director's sign-off — see decide_cancellation() below.
alter table requisitions
  add column cancellation_status text check (cancellation_status in ('requested', 'approved', 'denied')),
  add column cancellation_reason text,
  add column cancellation_requested_by uuid references profiles (id);

create function cancel_requisition(p_requisition_id uuid, p_actor_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_stage_key approval_stage_key;
  v_director_id uuid;
begin
  if not exists (
    select 1 from profiles
     where id = p_actor_id and is_active and role in ('finance_accountant', 'finance_assistant', 'admin')
  ) then
    raise exception 'Actor % is not permitted to cancel requisitions', p_actor_id;
  end if;

  select status into v_status from requisitions where id = p_requisition_id;

  if v_status in ('paid_posted', 'cancelled') then
    raise exception 'Requisition % can no longer be cancelled (status: %)', p_requisition_id, v_status;
  end if;

  if v_status = 'approved_for_payment' then
    -- Already fully authorized — Finance can only request cancellation;
    -- the Director decides (decide_cancellation, below).
    update requisitions
      set cancellation_status = 'requested', cancellation_reason = p_reason, cancellation_requested_by = p_actor_id
      where id = p_requisition_id;

    select id into v_director_id from profiles where role = 'director' and is_active limit 1;
    if v_director_id is not null then
      perform enqueue_email_for_profiles(
        p_requisition_id, 'cancellation_requested', array[v_director_id],
        jsonb_build_object(
          'requisition_number', (select requisition_number from requisitions where id = p_requisition_id),
          'requester_name', (
            select full_name from profiles where id = (select requester_id from requisitions where id = p_requisition_id)
          ),
          'reason', p_reason,
          'requisition_link', requisition_link(p_requisition_id)
        )
      );
    end if;
  else
    update requisitions set status = 'cancelled', cancellation_reason = p_reason where id = p_requisition_id;

    v_stage_key := stage_key_for_status(v_status);
    if v_stage_key is not null then
      insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
      values (p_requisition_id, v_stage_key, p_actor_id, 'cancelled', p_reason);
    end if;

    perform notify_requester(p_requisition_id, 'requisition_cancelled', p_reason);
  end if;
end;
$$;

grant execute on function cancel_requisition(uuid, uuid, text) to authenticated;

create function decide_cancellation(p_requisition_id uuid, p_actor_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cancellation_status text;
  v_requested_by uuid;
  v_reason text;
begin
  if not exists (
    select 1 from profiles where id = p_actor_id and is_active and role in ('director', 'admin')
  ) then
    raise exception 'Actor % is not permitted to decide a cancellation request', p_actor_id;
  end if;

  select cancellation_status, cancellation_requested_by, cancellation_reason
    into v_cancellation_status, v_requested_by, v_reason
    from requisitions where id = p_requisition_id;

  if v_cancellation_status is distinct from 'requested' then
    raise exception 'Requisition % has no pending cancellation request', p_requisition_id;
  end if;

  if p_approve then
    update requisitions set status = 'cancelled', cancellation_status = 'approved' where id = p_requisition_id;
    insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
    values (p_requisition_id, 'director', p_actor_id, 'cancelled', v_reason);
    perform notify_requester(p_requisition_id, 'requisition_cancelled', v_reason);
  else
    update requisitions set cancellation_status = 'denied' where id = p_requisition_id;
    if v_requested_by is not null then
      perform enqueue_email_for_profiles(
        p_requisition_id, 'cancellation_denied', array[v_requested_by],
        jsonb_build_object(
          'requisition_number', (select requisition_number from requisitions where id = p_requisition_id),
          'requester_name', (
            select full_name from profiles where id = (select requester_id from requisitions where id = p_requisition_id)
          ),
          'requisition_link', requisition_link(p_requisition_id)
        )
      );
    end if;
  end if;
end;
$$;

grant execute on function decide_cancellation(uuid, uuid, boolean) to authenticated;

insert into email_templates (key, subject, html_body) values
('requisition_cancelled', 'Requisition {{requisition_number}} has been cancelled', $html$
<p>Hi {{recipient_name}},</p>
<p>Requisition <strong>{{requisition_number}}</strong> has been cancelled.</p>
{{#comments}}<blockquote>{{comments}}</blockquote>{{/comments}}
<p><a href="{{requisition_link}}" class="btn">View requisition</a></p>
$html$),
('cancellation_requested', 'Cancellation requested for requisition {{requisition_number}}', $html$
<p>Hi {{recipient_name}},</p>
<p>Requisition <strong>{{requisition_number}}</strong> from {{requester_name}} has already been authorized, and
Finance has requested to cancel it:</p>
<blockquote>{{reason}}</blockquote>
<p>Your approval is needed before it can actually be cancelled.</p>
<p><a href="{{requisition_link}}" class="btn">Review requisition</a></p>
$html$),
('cancellation_denied', 'Cancellation request for requisition {{requisition_number}} was denied', $html$
<p>Hi {{recipient_name}},</p>
<p>The Director denied the request to cancel requisition <strong>{{requisition_number}}</strong>. It remains
approved for payment.</p>
<p><a href="{{requisition_link}}" class="btn">View requisition</a></p>
$html$)
on conflict (key) do nothing;
