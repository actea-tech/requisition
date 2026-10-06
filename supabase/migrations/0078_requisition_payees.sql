-- A requisition can pay more than one payee, each with their own payment
-- details. Each payee is a row here; currency stays a single value on the
-- requisition itself (one currency per requisition), and requisitions.amount
-- becomes the *total* of the payee amounts, kept in sync by a trigger — so
-- everything that already reads requisitions.amount (director/assistant
-- thresholds, emails, dashboards, exports) keeps working unchanged.
--
-- The old single-payee columns on requisitions (payee_name, payee_contact,
-- payment_mode, payment_mode_details) are no longer written or read by the
-- app; they're left in place (their existing data is backfilled below) so
-- nothing that predates this migration is lost.

create table requisition_payees (
  id uuid primary key default gen_random_uuid(),
  requisition_id uuid not null references requisitions(id) on delete cascade,
  sort_order int not null default 0,
  payee_name text,
  payee_contact text,
  amount numeric,
  payment_mode text,
  payment_mode_details text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index requisition_payees_requisition_idx on requisition_payees (requisition_id, sort_order);

create trigger requisition_payees_set_updated_at
  before update on requisition_payees
  for each row execute function set_updated_at();

-- Every existing requisition's single payee becomes its first payee row.
-- (Done before the sync trigger exists, so requisitions.amount is simply
-- left as-is — it already equals the one row's amount.)
insert into requisition_payees (requisition_id, sort_order, payee_name, payee_contact, amount, payment_mode, payment_mode_details)
select id, 0, payee_name, payee_contact, amount, payment_mode, payment_mode_details
  from requisitions
 where payee_name is not null
    or payee_contact is not null
    or amount is not null
    or payment_mode is not null
    or payment_mode_details is not null;

-- Same people, same statuses as the requester-fields clause of
-- enforce_field_write_scope() — payee details are exactly the fields
-- (payee name/contact, amount, payment mode) that clause already governs.
create function auth_can_edit_requisition_payees(p_requisition_id uuid)
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
         auth_is_admin()
         or (
           r.is_test = auth_is_test_user()
           and (
             (r.requester_id = auth.uid() and r.status in ('draft', 'returned', 'awaiting_invoice'))
             or (auth_is_finance() and r.status in ('finance_review', 'procurement_finance_review'))
             or (auth_is_dept_head_of(r.department_id) and r.status = 'returned' and r.return_to = 'previous_stage' and r.returned_from_stage in ('dept_review', 'procurement_dept_review'))
             or (auth_is_finance() and r.status = 'returned' and r.return_to = 'previous_stage' and r.returned_from_stage in ('finance_review', 'procurement_finance_review'))
           )
         )
       )
  );
$$;

alter table requisition_payees enable row level security;

-- Visible to exactly whoever can see the requisition (the subquery is
-- itself subject to requisitions_select).
create policy requisition_payees_select on requisition_payees for select to authenticated
  using (exists (select 1 from requisitions r where r.id = requisition_payees.requisition_id));

create policy requisition_payees_insert on requisition_payees for insert to authenticated
  with check (auth_can_edit_requisition_payees(requisition_id));

create policy requisition_payees_update on requisition_payees for update to authenticated
  using (auth_can_edit_requisition_payees(requisition_id))
  with check (auth_can_edit_requisition_payees(requisition_id));

create policy requisition_payees_delete on requisition_payees for delete to authenticated
  using (auth_can_edit_requisition_payees(requisition_id));

grant select, insert, update, delete on requisition_payees to authenticated;

-- requisitions.amount := total of the payee amounts, whenever payees change.
-- security definer so this isn't tripped up by column grants/RLS on
-- requisitions; enforce_field_write_scope() still runs on that update and
-- sees the real caller (auth.uid() comes from the request's JWT), so it
-- remains a second guard on who may change the amount.
create function sync_requisition_total_amount()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition_id uuid := coalesce(new.requisition_id, old.requisition_id);
  v_total numeric;
begin
  select sum(amount) into v_total from requisition_payees where requisition_id = v_requisition_id;
  update requisitions set amount = v_total
   where id = v_requisition_id and amount is distinct from v_total;
  return null;
end;
$$;

create trigger requisition_payees_sync_total
  after insert or update or delete on requisition_payees
  for each row execute function sync_requisition_total_amount();

-- Replaces a requisition's whole payee list in one transaction (the form
-- always saves the full list). security invoker: the RLS policies above
-- apply to the caller. Blank rows are skipped, so an untouched empty
-- "Payee 1" block never creates a row.
create function replace_requisition_payees(p_requisition_id uuid, p_payees jsonb)
returns void
language plpgsql
set search_path = public
as $$
begin
  if jsonb_typeof(p_payees) is distinct from 'array' then
    raise exception 'Payees must be a list';
  end if;
  if jsonb_array_length(p_payees) > 50 then
    raise exception 'A requisition can have at most 50 payees';
  end if;
  if not auth_can_edit_requisition_payees(p_requisition_id) then
    raise exception 'The payees on this requisition can''t be changed right now';
  end if;

  delete from requisition_payees where requisition_id = p_requisition_id;

  insert into requisition_payees (requisition_id, sort_order, payee_name, payee_contact, amount, payment_mode, payment_mode_details)
  select
    p_requisition_id,
    (t.ord - 1)::int,
    nullif(btrim(t.e->>'payee_name'), ''),
    nullif(btrim(t.e->>'payee_contact'), ''),
    nullif(btrim(t.e->>'amount'), '')::numeric,
    nullif(btrim(t.e->>'payment_mode'), ''),
    nullif(btrim(t.e->>'payment_mode_details'), '')
  from jsonb_array_elements(p_payees) with ordinality as t(e, ord)
  where coalesce(
          nullif(btrim(t.e->>'payee_name'), ''),
          nullif(btrim(t.e->>'payee_contact'), ''),
          nullif(btrim(t.e->>'amount'), ''),
          nullif(btrim(t.e->>'payment_mode'), ''),
          nullif(btrim(t.e->>'payment_mode_details'), '')
        ) is not null;
end;
$$;

grant execute on function replace_requisition_payees(uuid, jsonb) to authenticated;
