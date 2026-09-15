-- Both entry points into approved_for_payment only ever notified Finance
-- Accountants (falling back to every active one when finance_accountant_id
-- wasn't set yet) — never finance_assistant — even though migrations
-- 0042/0043 already made Payment Processing/Finalization fully usable by
-- an Assistant. Broaden both to also notify every active Assistant.
create or replace function notify_finance_cleared_no_director(p_requisition_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_ids uuid[];
begin
  select * into r from requisitions where id = p_requisition_id;
  v_ids := (
    case
      when r.finance_accountant_id is not null then array[r.finance_accountant_id]
      else array(select id from profiles where role = 'finance_accountant' and is_active)
    end
  ) || array(select id from profiles where role = 'finance_assistant' and is_active);

  perform enqueue_email_for_profiles(
    p_requisition_id, 'finance_cleared_no_director', v_ids,
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'requester_name', (select full_name from profiles where id = r.requester_id),
      'amount', r.amount,
      'currency', r.currency,
      'requisition_link', requisition_link(r.id)
    )
  );
end;
$$;

create or replace function notify_director_approved(p_requisition_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_ids uuid[];
begin
  select * into r from requisitions where id = p_requisition_id;
  v_ids := (
    case
      when r.finance_accountant_id is not null then array[r.finance_accountant_id]
      else array(select id from profiles where role = 'finance_accountant' and is_active)
    end
  ) || array(select id from profiles where role = 'finance_assistant' and is_active);

  perform enqueue_email_for_profiles(
    p_requisition_id, 'director_approved', v_ids,
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'requester_name', (select full_name from profiles where id = r.requester_id),
      'requisition_link', requisition_link(r.id)
    )
  );
end;
$$;

-- Hide cancellation at Payment Processing behind a settings toggle, off by
-- default per Finance's own request — an admin can turn it back on from
-- Settings > Approval Rules. Defense in depth: the app layer
-- (canCancelRequisition) hides the control, and this is the matching
-- server-side check so the RPC can't be called directly to bypass it.
insert into app_settings (key, value) values ('payment_stage_cancellation_enabled', 'no')
  on conflict (key) do nothing;

create or replace function cancel_requisition(p_requisition_id uuid, p_actor_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_stage_key approval_stage_key;
  v_director_id uuid;
  v_payment_cancellation_enabled text;
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
    select value into v_payment_cancellation_enabled from app_settings where key = 'payment_stage_cancellation_enabled';
    if coalesce(v_payment_cancellation_enabled, 'no') <> 'yes' then
      raise exception 'Cancellation at Payment Processing is currently disabled';
    end if;

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
