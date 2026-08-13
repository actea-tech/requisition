-- Requisition numbers: REQ-<year>-<0000>, reset per calendar year.
create table requisition_number_counters (
  year int primary key,
  last_value int not null default 0
);

create function next_requisition_number()
returns text
language plpgsql
as $$
declare
  v_year int := extract(year from now());
  v_next int;
begin
  insert into requisition_number_counters (year, last_value)
  values (v_year, 1)
  on conflict (year) do update set last_value = requisition_number_counters.last_value + 1
  returning last_value into v_next;

  return format('REQ-%s-%s', v_year, lpad(v_next::text, 4, '0'));
end;
$$;

create table requisitions (
  id uuid primary key default gen_random_uuid(),
  requisition_number text not null unique default next_requisition_number(),
  requester_id uuid not null references profiles (id),
  department_id uuid not null references departments (id),
  status requisition_status not null default 'draft',

  -- Request Details
  purpose text,
  activity_project text,

  -- Payment Details
  payee_name text,
  payee_contact text,
  amount numeric(14, 2),
  currency text not null default 'KES',
  payment_mode text,

  -- Budget and Coding
  budget_line text,
  account_code text,
  project_fund_class_code text,
  donor_grant_source text,
  budgeted yes_no,

  -- Compliance and Support
  procurement_required yes_no,
  donor_restriction yes_no_unsure,
  outstanding_advance yes_no,

  -- Finance Review
  finance_comments text,
  budget_available yes_no,
  finance_cleared boolean not null default false,
  finance_accountant_id uuid references profiles (id),

  -- Director Authorization
  director_comments text,
  director_decision text check (director_decision in ('approved', 'returned', 'rejected')),
  director_id uuid references profiles (id),

  -- Final Processing (Payment Processing stage)
  payment_voucher_number text,
  qbo_posting_reference text,
  payment_status text not null default 'pending'
    check (payment_status in ('pending', 'approved_for_payment', 'paid', 'posted_in_qbo', 'returned')),

  -- Workflow bookkeeping
  returned_from_stage requisition_status,
  return_reason text,
  stage_entered_at timestamptz not null default now(),
  submitted_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index requisitions_requester_id_idx on requisitions (requester_id);
create index requisitions_department_id_idx on requisitions (department_id);
create index requisitions_status_idx on requisitions (status);
create index requisitions_finance_accountant_id_idx on requisitions (finance_accountant_id);

create trigger requisitions_set_updated_at
  before update on requisitions
  for each row execute function set_updated_at();

-- Ad-hoc pick of who else in Finance must approve a given requisition,
-- chosen by the accountant handling it. If empty, the accountant's own
-- approval is the whole Finance stage.
create table finance_approver_group (
  requisition_id uuid not null references requisitions (id) on delete cascade,
  user_id uuid not null references profiles (id) on delete cascade,
  added_by uuid references profiles (id),
  created_at timestamptz not null default now(),
  primary key (requisition_id, user_id)
);

create table requisition_attachments (
  id uuid primary key default gen_random_uuid(),
  requisition_id uuid not null references requisitions (id) on delete cascade,
  uploaded_by uuid not null references profiles (id),
  storage_path text not null,
  file_name text not null,
  file_size bigint,
  section form_section not null default 'compliance_and_support',
  created_at timestamptz not null default now()
);

create index requisition_attachments_requisition_id_idx on requisition_attachments (requisition_id);
