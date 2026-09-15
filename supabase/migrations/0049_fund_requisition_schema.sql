-- Fund vs. Payment is orthogonal to requisition_type (departmental /
-- individual / finance_direct, which is about routing/who-reviews-first,
-- not what kind of spend this is) — a plain checked column rather than a
-- new requisition_scope value, so any routing type can be a Fund
-- requisition. Defaults to 'payment' everywhere, so nothing changes for
-- existing requisitions.
alter table requisitions add column requisition_kind text not null default 'payment'
  check (requisition_kind in ('payment', 'fund'));
grant update (requisition_kind) on requisitions to authenticated;

insert into form_field_config (section, field_key, label, help_text, is_required, sort_order) values
  ('request_details', 'requisition_kind', 'Requisition kind',
   'Fund/advance requisitions (e.g. trip money, petty cash) require accounting for how the funds were spent once paid — see Expenditure Accounting once this is paid.',
   true, 1);

-- Purely informational traceability for the "raise a new, ordinary
-- requisition for an in-budget shortfall" recommendation — no workflow
-- coupling, nothing currently sets it from the UI (a future "raise a
-- linked requisition" convenience action would).
alter table requisitions add column related_requisition_id uuid references requisitions (id);

-- Finance's free-text record of how an out-of-budget shortfall will be
-- recovered (e.g. "Deduct from October payroll"). Purely informational —
-- no payroll integration, out of this system's scope. Set only via
-- review_requisition_accounting(), not a plain field edit.
alter table requisitions add column accounting_shortfall_note text;

-- One row per expenditure line *or* the "balance banked" line (proof of
-- returning unspent funds) — same shape, distinguished by entry_type, so
-- one table covers both instead of two near-duplicates.
create table requisition_expenditures (
  id uuid primary key default gen_random_uuid(),
  requisition_id uuid not null references requisitions (id) on delete cascade,
  entry_type text not null default 'expense' check (entry_type in ('expense', 'balance_banked')),
  description text not null,
  amount numeric(14,2) not null,
  storage_path text,
  file_name text,
  file_size bigint,
  created_by uuid not null references profiles (id),
  created_at timestamptz not null default now()
);

create index requisition_expenditures_requisition_id_idx on requisition_expenditures (requisition_id);

alter table requisition_expenditures enable row level security;

-- Mirrors requisition_attachments_select's visibility rule exactly.
create policy requisition_expenditures_select on requisition_expenditures for select to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = requisition_expenditures.requisition_id
         and (
           r.requester_id = auth.uid()
           or auth_is_admin()
           or auth_is_finance()
           or auth_is_forwarded_assistant(r.id)
           or (auth_role() = 'finance_assistant' and r.finance_accountant_id = auth.uid())
         )
    )
  );

-- Only the requester can add/remove lines, and only while there's actually
-- an accounting to submit: at paid_posted (covers both the first pass and
-- resubmitting after review_requisition_accounting sends it back).
create policy requisition_expenditures_insert on requisition_expenditures for insert to authenticated
  with check (
    created_by = auth.uid()
    and exists (
      select 1 from requisitions r
       where r.id = requisition_expenditures.requisition_id
         and r.requester_id = auth.uid()
         and r.requisition_kind = 'fund'
         and r.status = 'paid_posted'
    )
  );

create policy requisition_expenditures_delete on requisition_expenditures for delete to authenticated
  using (
    exists (
      select 1 from requisitions r
       where r.id = requisition_expenditures.requisition_id
         and r.requester_id = auth.uid()
         and r.status = 'paid_posted'
    )
  );

grant select, insert, delete on requisition_expenditures to authenticated;
