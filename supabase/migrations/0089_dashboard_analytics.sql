-- Dashboard analytics: one function returns every number the analytics
-- section of the dashboard shows, already limited to what the caller may see.
--
-- Who sees it: Admin always; any other role only if it's ticked in Settings
-- (app_settings.analytics_roles). What they see depends on the role:
--   admin / director / finance_accountant / board  -> the whole organisation
--   dept_head                                      -> their department(s) + their own
--   finance_assistant                              -> ones assigned to them + their own
--   finance_reviewer                               -> ones they review + their own
--   anyone else                                    -> their own requisitions
-- Drafts never count. Test users only ever see test requisitions, and real
-- users real ones.
--
-- Definitions:
--   completed   = paid (paid_posted, accounting_review, posted_and_closed)
--   in progress = at a review/payment stage or awaiting an invoice (not returned)
--   turnaround  = first submission -> paid, minus time spent Returned or
--                 Awaiting Invoice (those wait on the requester, not on approvers)
--   overdue     = at an approval stage longer than analytics_overdue_days;
--                 Awaiting Invoice has its own limit, analytics_invoice_overdue_days

insert into app_settings (key, value) values
  ('analytics_roles', 'director,finance_accountant,board'),
  ('analytics_overdue_days', '5'),
  ('analytics_invoice_overdue_days', '30')
on conflict (key) do nothing;

create function get_dashboard_analytics(p_range text default 'all')
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_is_test boolean;
  v_roles text[];
  v_scope text;
  v_start timestamptz;
  v_overdue_days int;
  v_invoice_days int;
  v_result jsonb;
begin
  select role::text, is_test_user into v_role, v_is_test
    from profiles where id = v_uid and is_active;
  if v_role is null then
    return jsonb_build_object('allowed', false);
  end if;

  select array(select btrim(x) from unnest(string_to_array(coalesce(value, ''), ',')) x)
    into v_roles from app_settings where key = 'analytics_roles';
  v_roles := coalesce(v_roles, array['director', 'finance_accountant', 'board']);
  if v_role <> 'admin' and not (v_role = any(v_roles)) then
    return jsonb_build_object('allowed', false);
  end if;

  v_scope := case
    when v_role in ('admin', 'director', 'finance_accountant', 'board') then 'org'
    when v_role = 'dept_head' then 'department'
    when v_role = 'finance_assistant' then 'assigned'
    when v_role = 'finance_reviewer' then 'reviewer'
    else 'own'
  end;

  v_start := case p_range
    when 'month' then date_trunc('month', now())
    when 'quarter' then date_trunc('quarter', now())
    when 'year' then date_trunc('year', now())
    else null
  end;

  select coalesce((select case when value ~ '^\d+$' then value::int end from app_settings where key = 'analytics_overdue_days'), 5),
         coalesce((select case when value ~ '^\d+$' then value::int end from app_settings where key = 'analytics_invoice_overdue_days'), 30)
    into v_overdue_days, v_invoice_days;

  with scoped as (
    select r.id, r.status::text as status, r.requisition_kind, r.requisition_number, r.purpose,
           r.department_id, r.requester_id, r.currency,
           coalesce(r.amount, r.estimated_amount, 0) as amt,
           coalesce(r.submitted_at, r.created_at) as submitted_at,
           r.stage_entered_at
      from requisitions r
     where r.is_test = v_is_test
       and r.status <> 'draft'
       and (
         v_scope = 'org'
         or r.requester_id = v_uid
         or (v_scope = 'department'
             and r.department_id in (select dh.department_id from department_heads dh where dh.user_id = v_uid))
         or (v_scope = 'assigned' and finance_assistant_is_assigned(r.id, v_uid))
         or (v_scope = 'reviewer'
             and exists (select 1 from finance_approver_group g where g.requisition_id = r.id and g.user_id = v_uid))
       )
  ),
  in_range as (
    select * from scoped where v_start is null or submitted_at >= v_start
  ),
  paid as (
    select a.requisition_id, min(a.created_at) as paid_at
      from approval_actions a
     where a.decision = 'completed' and a.requisition_id in (select id from scoped)
     group by a.requisition_id
  ),
  returned_pause as (
    select a.requisition_id,
           sum(coalesce(
                 (select min(b.created_at) from approval_actions b
                   where b.requisition_id = a.requisition_id and b.decision = 'submitted' and b.created_at > a.created_at),
                 now()) - a.created_at) as pause
      from approval_actions a
     where a.decision = 'returned' and a.requisition_id in (select id from scoped)
     group by a.requisition_id
  ),
  invoice_pause as (
    select i.requisition_id,
           sum(i.created_at - coalesce(
                 (select max(p.created_at) from approval_actions p
                   where p.requisition_id = i.requisition_id and p.decision = 'approved'
                     and p.stage_key = 'finance' and p.created_at < i.created_at),
                 i.created_at)) as pause
      from approval_actions i
     where i.decision = 'invoice_submitted' and i.requisition_id in (select id from scoped)
     group by i.requisition_id
  ),
  turnaround as (
    select greatest(
             extract(epoch from (p.paid_at - s.submitted_at)
                                - coalesce(rp.pause, interval '0')
                                - coalesce(ip.pause, interval '0')),
             0) / 86400.0 as days
      from in_range s
      join paid p on p.requisition_id = s.id
      left join returned_pause rp on rp.requisition_id = s.id
      left join invoice_pause ip on ip.requisition_id = s.id
     where s.status in ('paid_posted', 'accounting_review', 'posted_and_closed')
  )
  select jsonb_build_object(
    'allowed', true,
    'scope', v_scope,
    'range', case when v_start is null then 'all' else p_range end,
    'overdue_days', v_overdue_days,
    'invoice_overdue_days', v_invoice_days,

    'counts', (
      select jsonb_build_object(
        'total', count(*),
        'in_progress', count(*) filter (where status in ('dept_review', 'procurement_dept_review', 'procurement_finance_review', 'awaiting_invoice', 'finance_review', 'director_review', 'approved_for_payment')),
        'completed', count(*) filter (where status in ('paid_posted', 'accounting_review', 'posted_and_closed')),
        'returned', count(*) filter (where status = 'returned'),
        'rejected', count(*) filter (where status = 'rejected'),
        'cancelled', count(*) filter (where status = 'cancelled')
      ) from in_range
    ),

    'amounts', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'currency', currency, 'requisitioned', requisitioned, 'paid', paid_amt, 'pipeline', pipeline
             ) order by requisitioned desc), '[]'::jsonb)
        from (
          select currency,
                 coalesce(sum(amt) filter (where status not in ('rejected', 'cancelled')), 0) as requisitioned,
                 coalesce(sum(amt) filter (where status in ('paid_posted', 'accounting_review', 'posted_and_closed')), 0) as paid_amt,
                 coalesce(sum(amt) filter (where status in ('dept_review', 'procurement_dept_review', 'procurement_finance_review', 'awaiting_invoice', 'finance_review', 'director_review', 'approved_for_payment', 'returned')), 0) as pipeline
            from in_range
           group by currency
        ) x
    ),

    'turnaround', (
      select jsonb_build_object(
        'average_days', round(avg(days)::numeric, 1),
        'median_days', round((percentile_cont(0.5) within group (order by days))::numeric, 1),
        'sample', count(*)
      ) from turnaround
    ),

    -- "Right now" figures ignore the date filter.
    'overdue_count', (
      select count(*) from scoped
       where status in ('dept_review', 'procurement_dept_review', 'procurement_finance_review', 'finance_review', 'director_review', 'approved_for_payment')
         and stage_entered_at < now() - make_interval(days => v_overdue_days)
    ),

    'by_stage', (
      select coalesce(jsonb_agg(jsonb_build_object('status', status, 'count', n) order by n desc), '[]'::jsonb)
        from (
          select status, count(*) as n from scoped
           where status in ('dept_review', 'procurement_dept_review', 'procurement_finance_review', 'awaiting_invoice', 'finance_review', 'director_review', 'approved_for_payment', 'returned')
           group by status
        ) x
    ),

    'oldest', (
      select coalesce(jsonb_agg(row_to_json(o)::jsonb order by o.age_days desc), '[]'::jsonb)
        from (
          select s.id, s.requisition_number, s.purpose, s.status, s.currency, s.amt as amount,
                 pr.full_name as requester_name, d.name as department_name,
                 floor(extract(epoch from now() - s.submitted_at) / 86400)::int as age_days,
                 floor(extract(epoch from now() - s.stage_entered_at) / 86400)::int as days_in_stage
            from scoped s
            left join profiles pr on pr.id = s.requester_id
            left join departments d on d.id = s.department_id
           where s.status in ('dept_review', 'procurement_dept_review', 'procurement_finance_review', 'awaiting_invoice', 'finance_review', 'director_review', 'approved_for_payment', 'returned')
           order by s.submitted_at asc
           limit 5
        ) o
    ),

    'invoice_overdue', (
      select coalesce(jsonb_agg(row_to_json(o)::jsonb order by o.days_waiting desc), '[]'::jsonb)
        from (
          select s.id, s.requisition_number, s.purpose, s.currency, s.amt as amount,
                 pr.full_name as requester_name, d.name as department_name,
                 floor(extract(epoch from now() - s.stage_entered_at) / 86400)::int as days_waiting
            from scoped s
            left join profiles pr on pr.id = s.requester_id
            left join departments d on d.id = s.department_id
           where s.status = 'awaiting_invoice'
             and s.stage_entered_at < now() - make_interval(days => v_invoice_days)
           order by s.stage_entered_at asc
           limit 10
        ) o
    ),

    'awaiting_accounting', (
      select jsonb_build_object(
        'count', count(*),
        'amounts', coalesce(
          (select jsonb_agg(jsonb_build_object('currency', currency, 'amount', t) order by t desc)
             from (select currency, sum(amt) as t from scoped
                    where requisition_kind = 'fund' and status in ('paid_posted', 'accounting_review')
                    group by currency) y),
          '[]'::jsonb)
      ) from scoped where requisition_kind = 'fund' and status in ('paid_posted', 'accounting_review')
    ),

    -- Last 12 months, whatever the date filter says.
    'monthly', (
      select jsonb_agg(jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'submitted', sub, 'completed', done) order by m)
        from (
          select m,
                 (select count(*) from scoped s where date_trunc('month', s.submitted_at) = m) as sub,
                 (select count(*) from paid p where p.requisition_id in (select id from scoped) and date_trunc('month', p.paid_at) = m) as done
            from generate_series(date_trunc('month', now()) - interval '11 months', date_trunc('month', now()), interval '1 month') m
        ) z
    ),

    'by_department', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'department', department, 'currency', currency, 'total', total, 'count', n
             ) order by total desc), '[]'::jsonb)
        from (
          select coalesce(d.name, 'No department') as department, s.currency, sum(s.amt) as total, count(*) as n
            from in_range s
            left join departments d on d.id = s.department_id
           where s.status not in ('rejected', 'cancelled')
           group by coalesce(d.name, 'No department'), s.currency
           order by total desc
           limit 60
        ) x
    )
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function get_dashboard_analytics(text) to authenticated;
