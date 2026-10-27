-- "Copied in": the requester can copy anyone (any active user) in on a
-- requisition. They don't approve or supervise anything - routing is
-- unchanged - but they can read the whole requisition, get an email at every
-- stage change, and add comments (recorded in the audit trail).
--
-- Run 0085 first (adds the 'commented' approval_decision value).

create table requisition_copied_in (
  requisition_id uuid not null references requisitions (id) on delete cascade,
  user_id uuid not null references profiles (id),
  added_by uuid references profiles (id),
  created_at timestamptz not null default now(),
  primary key (requisition_id, user_id)
);

create index requisition_copied_in_user_id_idx on requisition_copied_in (user_id);

alter table requisition_copied_in enable row level security;
-- Visible to whoever can see the requisition. Written only through
-- set_requisition_copied_in() below.
create policy requisition_copied_in_select on requisition_copied_in for select to authenticated
  using (exists (select 1 from requisitions r where r.id = requisition_copied_in.requisition_id));
grant select on requisition_copied_in to authenticated;

-- A draft is still private work in progress, so being copied in grants
-- nothing until the requisition has been submitted.
create function auth_is_requisition_copied_in(p_requisition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from requisition_copied_in c
      join requisitions r on r.id = c.requisition_id
     where c.requisition_id = p_requisition_id
       and c.user_id = auth.uid()
       and r.status <> 'draft'
  );
$$;

grant execute on function auth_is_requisition_copied_in(uuid) to authenticated;

create function requisition_status_label(p_status requisition_status)
returns text
language sql
immutable
as $$
  select case p_status
    when 'draft' then 'Draft'
    when 'dept_review' then 'Department Review'
    when 'procurement_dept_review' then 'Procurement - Department Review'
    when 'procurement_finance_review' then 'Procurement - Finance Review'
    when 'awaiting_invoice' then 'Awaiting Invoice'
    when 'finance_review' then 'Finance Review'
    when 'director_review' then 'Authorization'
    when 'approved_for_payment' then 'Payment Processing'
    when 'paid_posted' then 'Paid'
    when 'accounting_review' then 'Accounting Review'
    when 'posted_and_closed' then 'Posted & Closed'
    when 'returned' then 'Returned for Correction'
    when 'rejected' then 'Rejected'
    when 'cancelled' then 'Cancelled'
    else p_status::text
  end;
$$;

-- Whoever the requisition is with right now: the requester, plus whoever can
-- act on the stage it's at (Finance for Payment Processing onwards).
create function requisition_current_handler_ids(p_requisition_id uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  r requisitions;
  v_effective requisition_status;
  v_stage approval_stage_key;
begin
  select * into r from requisitions where id = p_requisition_id;
  if r.id is null then
    return;
  end if;

  return next r.requester_id;

  -- Returned to a previous stage's approvers: it's with them, not the requester.
  v_effective := case
    when r.status = 'returned' and r.return_to = 'previous_stage' and r.returned_from_stage is not null
      then r.returned_from_stage
    else r.status
  end;
  v_stage := stage_key_for_status(v_effective);

  if v_stage is not null and v_stage <> 'payment' then
    return query select * from get_eligible_approver_ids(p_requisition_id, v_stage);
  elsif v_effective in ('approved_for_payment', 'paid_posted', 'accounting_review') then
    return query
      select p.id
        from profiles p
       where p.is_active
         and p.role in ('finance_accountant', 'finance_assistant')
         and p.is_test_user = r.is_test;
  end if;
end;
$$;

-- The requester sets (replaces) who is copied in, any time before the
-- requisition is closed. Anyone active except themselves.
create function set_requisition_copied_in(p_requisition_id uuid, p_user_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition requisitions;
  v_ids uuid[] := coalesce((select array_agg(distinct u) from unnest(p_user_ids) u), '{}');
  v_added uuid[];
  v_requester_name text;
begin
  select * into v_requisition from requisitions where id = p_requisition_id;
  if v_requisition.id is null then
    raise exception 'Requisition not found';
  end if;
  if not (v_requisition.requester_id = auth.uid() or auth_is_admin()) then
    raise exception 'Only the requester can copy people in';
  end if;
  if v_requisition.status in ('posted_and_closed', 'cancelled', 'rejected') then
    raise exception 'People can no longer be copied in once the requisition is closed';
  end if;
  if cardinality(v_ids) > 10 then
    raise exception 'Copy in at most 10 people';
  end if;
  if v_requisition.requester_id = any(v_ids) then
    raise exception 'You can''t copy yourself in';
  end if;
  if exists (
    select 1 from unnest(v_ids) u
     where not exists (
       select 1 from profiles p
        where p.id = u and p.is_active and p.is_test_user = v_requisition.is_test
     )
  ) then
    raise exception 'Only active users can be copied in';
  end if;

  v_added := coalesce(
    array(
      select u from unnest(v_ids) u
       where not exists (
         select 1 from requisition_copied_in c where c.requisition_id = p_requisition_id and c.user_id = u
       )
    ),
    '{}'
  );

  delete from requisition_copied_in
   where requisition_id = p_requisition_id and not (user_id = any(v_ids));
  insert into requisition_copied_in (requisition_id, user_id, added_by)
  select p_requisition_id, u, auth.uid() from unnest(v_added) u;

  -- Tell newly added people straight away, once there's something to see.
  -- On a draft the "submitted" update they get later does that.
  if cardinality(v_added) > 0 and v_requisition.status <> 'draft' then
    select full_name into v_requester_name from profiles where id = v_requisition.requester_id;
    perform enqueue_email_for_profiles(
      p_requisition_id, 'copied_in', v_added,
      jsonb_build_object(
        'requisition_number', coalesce(v_requisition.requisition_number, 'New requisition'),
        'requester_name', v_requester_name,
        'purpose', v_requisition.purpose,
        'status_label', requisition_status_label(v_requisition.status),
        'requisition_link', requisition_link(p_requisition_id)
      )
    );
  end if;
end;
$$;

grant execute on function set_requisition_copied_in(uuid, uuid[]) to authenticated;

-- A copied-in person comments on the requisition. It goes into the audit
-- trail under their name, and the requester and whoever it's currently with
-- are emailed.
create function add_requisition_comment(p_requisition_id uuid, p_comment text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition requisitions;
  v_comment text := nullif(btrim(coalesce(p_comment, '')), '');
  v_commenter_name text;
  v_requester_name text;
begin
  select * into v_requisition from requisitions where id = p_requisition_id;
  if v_requisition.id is null then
    raise exception 'Requisition not found';
  end if;
  if not auth_is_requisition_copied_in(p_requisition_id) then
    raise exception 'Only people copied in on this requisition can comment here';
  end if;
  if v_comment is null then
    raise exception 'Write a comment first';
  end if;
  if char_length(v_comment) > 2000 then
    raise exception 'Comments can be at most 2000 characters';
  end if;

  insert into approval_actions (requisition_id, stage_key, actor_id, decision, comments)
  values (
    p_requisition_id,
    coalesce(
      stage_key_for_status(
        case
          when v_requisition.status = 'returned' and v_requisition.return_to = 'previous_stage'
            and v_requisition.returned_from_stage is not null then v_requisition.returned_from_stage
          else v_requisition.status
        end
      ),
      'finance'
    ),
    auth.uid(), 'commented', v_comment
  );

  select full_name into v_commenter_name from profiles where id = auth.uid();
  select full_name into v_requester_name from profiles where id = v_requisition.requester_id;

  perform enqueue_email_for_profiles(
    p_requisition_id, 'copied_in_comment',
    array(
      select distinct h from requisition_current_handler_ids(p_requisition_id) h where h <> auth.uid()
    ),
    jsonb_build_object(
      'requisition_number', coalesce(v_requisition.requisition_number, 'New requisition'),
      'requester_name', v_requester_name,
      'commenter_name', v_commenter_name,
      'purpose', v_requisition.purpose,
      'status_label', requisition_status_label(v_requisition.status),
      'comments', v_comment,
      'requisition_link', requisition_link(p_requisition_id)
    )
  );
end;
$$;

grant execute on function add_requisition_comment(uuid, text) to authenticated;

-- Every stage change emails the people copied in: submitted, each approval,
-- returned, rejected, authorized, paid, closed. Hooking the status column
-- covers every path (approvals, returns, resubmits, cancellation...).
create function notify_copied_in_on_status_change()
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
     where a.requisition_id = new.id and a.decision in ('returned', 'rejected', 'cancelled')
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

create trigger requisitions_notify_copied_in
  after update of status on requisitions
  for each row
  when (old.status is distinct from new.status)
  execute function notify_copied_in_on_status_change();

insert into email_templates (key, subject, html_body) values
('copied_in', 'You''ve been copied in on requisition {{requisition_number}}', $html$
<p>Hi {{recipient_name}},</p>
<p><strong>{{requester_name}}</strong> copied you in on requisition <strong>{{requisition_number}}</strong> so you can follow it. It is currently at <strong>{{status_label}}</strong>.</p>
{{#purpose}}<p>Purpose: {{purpose}}</p>{{/purpose}}
<p>You'll get an email at each stage, and you can add comments on the requisition any time. You can't approve or change it.</p>
<p><a href="{{requisition_link}}" class="btn">View requisition</a></p>
$html$),
('copied_in_update', 'Requisition {{requisition_number}}: {{status_label}}', $html$
<p>Hi {{recipient_name}},</p>
<p>You're copied in on requisition <strong>{{requisition_number}}</strong> from {{requester_name}}. It {{event}}.</p>
{{#purpose}}<p>Purpose: {{purpose}}</p>{{/purpose}}
{{#comments}}<blockquote>{{comments}}</blockquote>{{/comments}}
<p><a href="{{requisition_link}}" class="btn">View requisition</a></p>
$html$),
('copied_in_comment', '{{commenter_name}} commented on requisition {{requisition_number}}', $html$
<p>Hi {{recipient_name}},</p>
<p><strong>{{commenter_name}}</strong>, who is copied in on requisition <strong>{{requisition_number}}</strong> from {{requester_name}}, left a comment. The requisition is currently at <strong>{{status_label}}</strong>.</p>
<blockquote>{{comments}}</blockquote>
<p><a href="{{requisition_link}}" class="btn">View requisition</a></p>
$html$)
on conflict (key) do nothing;

-- People copied in can read the requisition, its documents and its audit
-- trail (payees follow requisition visibility).
drop policy requisitions_select on requisitions;
create policy requisitions_select on requisitions for select to authenticated
  using (
    auth_is_admin()
    or (
      is_test = auth_is_test_user()
      and (
        requester_id = auth.uid()
        or auth_is_finance()
        or auth_role() = 'director'
        or auth_is_dept_head_of(department_id)
        or auth_is_finance_group_member(id)
        or auth_is_requisition_authorizer(id)
        or auth_is_requisition_supervisor(id)
        or auth_is_requisition_copied_in(id)
        or auth_is_forwarded_assistant(id)
        or (auth_role() = 'finance_assistant' and status <> 'draft')
      )
    )
  );

drop policy requisition_attachments_select on requisition_attachments;
create policy requisition_attachments_select on requisition_attachments for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = requisition_attachments.requisition_id
         and (
           auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               r.requester_id = auth.uid()
               or auth_is_finance() or auth_role() = 'director'
               or auth_is_dept_head_of(r.department_id)
               or auth_is_finance_group_member(r.id)
               or auth_is_requisition_authorizer(r.id)
               or auth_is_requisition_supervisor(r.id)
               or auth_is_requisition_copied_in(r.id)
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status <> 'draft')
             )
           )
         )
    )
  );

drop policy approval_actions_select on approval_actions;
create policy approval_actions_select on approval_actions for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = approval_actions.requisition_id
         and (
           auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               r.requester_id = auth.uid()
               or auth_is_finance() or auth_role() = 'director'
               or auth_is_dept_head_of(r.department_id)
               or auth_is_finance_group_member(r.id)
               or auth_is_requisition_authorizer(r.id)
               or auth_is_requisition_supervisor(r.id)
               or auth_is_requisition_copied_in(r.id)
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status <> 'draft')
             )
           )
         )
    )
  );

drop policy requisition_attachments_storage_select on storage.objects;
create policy requisition_attachments_storage_select on storage.objects for select to authenticated
  using (
    bucket_id = 'requisition-attachments'
    and exists (
      select 1 from requisitions r
       where r.id::text = (storage.foldername(name))[1]
         and (
           auth_is_admin()
           or (
             r.is_test = auth_is_test_user()
             and (
               r.requester_id = auth.uid()
               or auth_is_finance() or auth_role() = 'director'
               or (auth_role() = 'dept_head' and auth_is_dept_head_of(r.department_id))
               or auth_is_requisition_authorizer(r.id)
               or auth_is_requisition_supervisor(r.id)
               or auth_is_requisition_copied_in(r.id)
               or auth_is_forwarded_assistant(r.id)
               or (auth_role() = 'finance_assistant' and r.status <> 'draft')
             )
           )
         )
    )
  );
