-- Append-only log of every decision made on a requisition. This is the
-- audit trail's backbone and what evaluate_stage() reacts to.
create table approval_actions (
  id uuid primary key default gen_random_uuid(),
  requisition_id uuid not null references requisitions (id) on delete cascade,
  stage_key approval_stage_key not null,
  actor_id uuid not null references profiles (id),
  decision approval_decision not null,
  comments text,
  created_at timestamptz not null default now()
);

create index approval_actions_requisition_id_idx on approval_actions (requisition_id, created_at);
create index approval_actions_actor_id_idx on approval_actions (actor_id);

create function stage_key_for_status(p_status requisition_status)
returns approval_stage_key
language sql
immutable
as $$
  select case p_status
    when 'dept_review' then 'department'::approval_stage_key
    when 'finance_review' then 'finance'::approval_stage_key
    when 'director_review' then 'director'::approval_stage_key
    when 'approved_for_payment' then 'payment'::approval_stage_key
    else null
  end;
$$;

-- Who can act on a requisition at a given stage right now.
create function get_eligible_approver_ids(p_requisition_id uuid, p_stage_key approval_stage_key)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select dh.user_id
    from requisitions r
    join department_heads dh on dh.department_id = r.department_id
    join profiles p on p.id = dh.user_id and p.is_active
   where r.id = p_requisition_id and p_stage_key = 'department'

  union

  select p.id
    from profiles p
   where p_stage_key = 'finance' and p.is_active and p.role = 'finance_accountant'

  union

  select fag.user_id
    from finance_approver_group fag
    join profiles p on p.id = fag.user_id and p.is_active
   where p_stage_key = 'finance' and fag.requisition_id = p_requisition_id

  union

  select p.id
    from profiles p
   where p_stage_key = 'director' and p.is_active and p.role = 'director';
$$;

-- Department-specific override wins for the 'department' stage; otherwise
-- (or if no override exists) falls back to the stage's global row. Written
-- as plpgsql rather than a flat UNION so the fallback is deterministic.
create function get_stage_mode(p_department_id uuid, p_stage_key approval_stage_key)
returns table (mode approval_mode, quorum_count int)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_stage_key = 'department' then
    return query
      select a.mode, a.quorum_count from approval_stage_config a
       where a.stage_key = 'department' and a.department_id = p_department_id;
    if found then
      return;
    end if;
  end if;

  return query
    select a.mode, a.quorum_count from approval_stage_config a
     where a.stage_key = p_stage_key and a.department_id is null
     limit 1;
end;
$$;

create function get_profile_emails(p_user_ids uuid[])
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(email), '{}') from profiles where id = any(p_user_ids) and is_active;
$$;

create function requisition_link(p_requisition_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select (select value from app_settings where key = 'app_url') || '/requisitions/' || p_requisition_id;
$$;

-- Builds the common payload fields shared by most templates, then hands off
-- to enqueue_email for each notification below.
create function notify_role_group(
  p_requisition_id uuid,
  p_stage_key approval_stage_key,
  p_template_key text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_to_emails text[];
begin
  select * into r from requisitions where id = p_requisition_id;
  v_to_emails := get_profile_emails(array(select get_eligible_approver_ids(p_requisition_id, p_stage_key)));

  perform enqueue_email(
    p_requisition_id,
    p_template_key,
    v_to_emails,
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'requester_name', (select full_name from profiles where id = r.requester_id),
      'department_name', (select name from departments where id = r.department_id),
      'amount', r.amount,
      'currency', r.currency,
      'purpose', r.purpose,
      'requisition_link', requisition_link(r.id)
    )
  );
end;
$$;

create function notify_requester(
  p_requisition_id uuid,
  p_template_key text,
  p_comments text default null,
  p_extra_to_emails text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_to_emails text[];
begin
  select * into r from requisitions where id = p_requisition_id;
  select array_append(p_extra_to_emails, email) into v_to_emails from profiles where id = r.requester_id;

  perform enqueue_email(
    p_requisition_id,
    p_template_key,
    v_to_emails,
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'requester_name', (select full_name from profiles where id = r.requester_id),
      'department_name', (select name from departments where id = r.department_id),
      'amount', r.amount,
      'currency', r.currency,
      'purpose', r.purpose,
      'comments', p_comments,
      'requisition_link', requisition_link(r.id)
    )
  );
end;
$$;

create function notify_director_approved(p_requisition_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_to_emails text[];
begin
  select * into r from requisitions where id = p_requisition_id;

  if r.finance_accountant_id is not null then
    v_to_emails := get_profile_emails(array[r.finance_accountant_id]);
  else
    v_to_emails := get_profile_emails(array(select id from profiles where role = 'finance_accountant' and is_active));
  end if;

  perform enqueue_email(
    p_requisition_id,
    'director_approved',
    v_to_emails,
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'requester_name', (select full_name from profiles where id = r.requester_id),
      'requisition_link', requisition_link(r.id)
    )
  );
end;
$$;

create function notify_paid_posted(p_requisition_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_to_emails text[];
begin
  select * into r from requisitions where id = p_requisition_id;
  v_to_emails := get_profile_emails(
    array(select user_id from department_heads where department_id = r.department_id)
  );
  select array_append(v_to_emails, email) into v_to_emails from profiles where id = r.requester_id;

  perform enqueue_email(
    p_requisition_id,
    'paid_posted',
    v_to_emails,
    jsonb_build_object(
      'requisition_number', r.requisition_number,
      'payment_voucher_number', r.payment_voucher_number,
      'qbo_posting_reference', r.qbo_posting_reference,
      'requisition_link', requisition_link(r.id)
    )
  );
end;
$$;

-- Moves a requisition to the next stage once its current stage has
-- resolved as approved, and notifies the next stage's approvers.
create function advance_stage(p_requisition_id uuid, p_from_stage approval_stage_key)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  case p_from_stage
    when 'department' then
      update requisitions set status = 'finance_review', stage_entered_at = now()
        where id = p_requisition_id;
      perform notify_role_group(p_requisition_id, 'finance', 'dept_approved');

    when 'finance' then
      update requisitions set status = 'director_review', finance_cleared = true, stage_entered_at = now()
        where id = p_requisition_id;
      perform notify_role_group(p_requisition_id, 'director', 'finance_cleared');

    when 'director' then
      update requisitions
        set status = 'approved_for_payment', director_decision = 'approved', stage_entered_at = now()
        where id = p_requisition_id;
      perform notify_director_approved(p_requisition_id);

    else
      -- 'payment' has no forward stage to advance to.
      null;
  end case;
end;
$$;

-- The workflow engine. Fires after every approval_actions insert and is the
-- single place that both mutates requisitions.status and enqueues the
-- corresponding notification email(s).
create function evaluate_stage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eligible_count int;
  v_approved_count int;
  v_mode approval_mode;
  v_quorum int;
  v_department_id uuid;
  v_stage_entered_at timestamptz;
  v_resolved boolean;
begin
  if new.decision = 'submitted' then
    case new.stage_key
      when 'department' then perform notify_role_group(new.requisition_id, 'department', 'submitted');
      when 'finance' then perform notify_role_group(new.requisition_id, 'finance', 'dept_approved');
      when 'director' then perform notify_role_group(new.requisition_id, 'director', 'finance_cleared');
      else null;
    end case;
    return new;
  end if;

  if new.decision = 'rejected' then
    update requisitions set status = 'rejected' where id = new.requisition_id;
    perform notify_requester(
      new.requisition_id,
      case new.stage_key
        when 'department' then 'dept_rejected'
        when 'finance' then 'finance_rejected'
        when 'director' then 'director_rejected'
      end,
      new.comments
    );
    return new;
  end if;

  if new.decision = 'returned' then
    update requisitions
      set returned_from_stage = status, status = 'returned', return_reason = new.comments
      where id = new.requisition_id;

    if new.stage_key = 'finance' then
      perform notify_requester(
        new.requisition_id, 'finance_returned', new.comments,
        get_profile_emails(array(
          select user_id from department_heads
          where department_id = (select department_id from requisitions where id = new.requisition_id)
        ))
      );
    elsif new.stage_key = 'director' then
      perform notify_requester(
        new.requisition_id, 'director_returned', new.comments,
        get_profile_emails(array(select id from profiles where role = 'finance_accountant' and is_active))
      );
    else
      perform notify_requester(new.requisition_id, 'dept_returned', new.comments);
    end if;
    return new;
  end if;

  if new.decision = 'completed' then
    update requisitions set status = 'paid_posted' where id = new.requisition_id;
    perform notify_paid_posted(new.requisition_id);
    return new;
  end if;

  if new.decision = 'approved' then
    select department_id, stage_entered_at into v_department_id, v_stage_entered_at
      from requisitions where id = new.requisition_id;

    v_eligible_count := (select count(*) from get_eligible_approver_ids(new.requisition_id, new.stage_key));
    select mode, quorum_count into v_mode, v_quorum from get_stage_mode(v_department_id, new.stage_key);

    select count(distinct actor_id) into v_approved_count
      from approval_actions
     where requisition_id = new.requisition_id
       and stage_key = new.stage_key
       and decision = 'approved'
       and created_at >= v_stage_entered_at;

    v_resolved := case
      when v_eligible_count <= 1 then true
      when v_mode = 'first_approver' then true
      when v_mode = 'all_approvers' then v_approved_count >= v_eligible_count
      when v_mode = 'quorum' then v_approved_count >= coalesce(v_quorum, v_eligible_count)
      else true
    end;

    if v_resolved then
      perform advance_stage(new.requisition_id, new.stage_key);
    end if;
  end if;

  return new;
end;
$$;

create trigger approval_actions_evaluate_stage
  after insert on approval_actions
  for each row execute function evaluate_stage();

-- Entry points the app calls (Server Actions) instead of inserting into
-- approval_actions directly, so validation always happens in one place.

create function record_approval_action(
  p_requisition_id uuid,
  p_actor_id uuid,
  p_decision approval_decision,
  p_comments text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_stage_key approval_stage_key;
begin
  select status into v_status from requisitions where id = p_requisition_id;
  v_stage_key := stage_key_for_status(v_status);

  if v_stage_key is null then
    raise exception 'Requisition % is not awaiting approval (status: %)', p_requisition_id, v_status;
  end if;

  if p_decision = 'completed' then
    if v_stage_key <> 'payment' then
      raise exception 'Requisition % is not ready for payment completion', p_requisition_id;
    end if;
    if not exists (
      select 1 from profiles where id = p_actor_id and is_active and role in ('finance_accountant', 'admin')
    ) then
      raise exception 'Actor % is not permitted to complete payment processing', p_actor_id;
    end if;
  end if;

  if p_decision in ('approved', 'returned', 'rejected')
     and not exists (
       select 1 from get_eligible_approver_ids(p_requisition_id, v_stage_key) id where id = p_actor_id
     ) then
    raise exception 'Actor % is not an eligible approver for requisition % at stage %', p_actor_id, p_requisition_id, v_stage_key;
  end if;

  -- First Finance action on a requisition claims it for that accountant —
  -- "a key head, as the accountant, who receives the request first."
  if v_stage_key = 'finance' then
    update requisitions
      set finance_accountant_id = p_actor_id
      where id = p_requisition_id
        and finance_accountant_id is null
        and exists (select 1 from profiles where id = p_actor_id and role = 'finance_accountant');
  elsif v_stage_key = 'director' then
    update requisitions
      set director_id = p_actor_id
      where id = p_requisition_id and director_id is null;
  end if;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
  values (p_requisition_id, v_stage_key, p_actor_id, p_decision, p_comments);
end;
$$;

create function submit_requisition(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
begin
  select status into v_status from requisitions where id = p_requisition_id;

  if v_status <> 'draft' then
    raise exception 'Requisition % is not a draft (status: %)', p_requisition_id, v_status;
  end if;

  update requisitions
    set status = 'dept_review', stage_entered_at = now(), submitted_at = coalesce(submitted_at, now())
    where id = p_requisition_id;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision)
  values (p_requisition_id, 'department', p_actor_id, 'submitted');
end;
$$;

create function resubmit_requisition(p_requisition_id uuid, p_actor_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status requisition_status;
  v_returned_from requisition_status;
begin
  select status, returned_from_stage into v_status, v_returned_from
    from requisitions where id = p_requisition_id;

  if v_status <> 'returned' or v_returned_from is null then
    raise exception 'Requisition % is not returned (status: %)', p_requisition_id, v_status;
  end if;

  update requisitions
    set status = v_returned_from, returned_from_stage = null, return_reason = null, stage_entered_at = now()
    where id = p_requisition_id;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision)
  values (p_requisition_id, stage_key_for_status(v_returned_from), p_actor_id, 'submitted');
end;
$$;

-- Called by the accountant once payment is made / posted in QBO. Final
-- Processing fields (voucher number, QBO reference, payment_status) are
-- written by the app first; this just logs the closure and fires the email.
create function complete_payment_processing(p_requisition_id uuid, p_actor_id uuid, p_comments text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform record_approval_action(p_requisition_id, p_actor_id, 'completed', p_comments);
end;
$$;
