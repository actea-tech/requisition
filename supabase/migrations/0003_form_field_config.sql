-- Drives which fields render on the requisition form, per section. Request
-- Details / Payment Details stay fixed defaults per the requirements doc;
-- Budget & Coding / Compliance & Support / Finance Review / Final Processing
-- rows are editable in Settings so field visibility can change without a
-- code deploy.
create table form_field_config (
  id uuid primary key default gen_random_uuid(),
  section form_section not null,
  field_key text not null,
  label text not null,
  help_text text,
  is_visible boolean not null default true,
  is_required boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (section, field_key)
);

create trigger form_field_config_set_updated_at
  before update on form_field_config
  for each row execute function set_updated_at();

insert into form_field_config (section, field_key, label, help_text, is_required, sort_order) values
  ('request_details', 'purpose', 'Purpose of request', 'Clear business purpose and expected use.', true, 1),
  ('request_details', 'activity_project', 'Activity / project linked to the request', 'Relevant activity, event, project, or operational need.', false, 2),

  ('payment_details', 'payee_name', 'Payee / supplier name', 'Name of person, supplier, consultant, institution, or staff member.', true, 1),
  ('payment_details', 'payee_contact', 'Payee contact details', 'Email, phone, and other relevant details where applicable.', false, 2),
  ('payment_details', 'amount', 'Amount requested', 'Amount before or inclusive of taxes, as applicable.', true, 3),
  ('payment_details', 'currency', 'Currency', 'KES, USD, EUR, etc.', true, 4),
  ('payment_details', 'payment_mode', 'Payment mode', 'Bank transfer, M-Pesa, cheque, petty cash, etc.', true, 5),

  ('budget_and_coding', 'budget_line', 'Budget line', 'Relevant approved budget line.', true, 1),
  ('budget_and_coding', 'account_code', 'Account code', 'Finance to review/confirm before posting.', false, 2),
  ('budget_and_coding', 'project_fund_class_code', 'Project / fund / class code', 'Required for QBO and donor/fund reporting.', false, 3),
  ('budget_and_coding', 'donor_grant_source', 'Donor / grant source', 'Where the request relates to a restricted project or donor-funded activity.', false, 4),
  ('budget_and_coding', 'budgeted', 'Budgeted?', 'Yes/No, subject to Finance confirmation.', true, 5),

  ('compliance_and_support', 'supporting_documents', 'Supporting documents attached', 'Invoice, quotation, budget, payroll, contract, expense report, cash advance request, etc.', true, 0),
  ('compliance_and_support', 'procurement_required', 'Procurement requirement applicable?', 'Indicates whether quotations, procurement documentation, LPO, or contract support is required.', true, 1),
  ('compliance_and_support', 'donor_restriction', 'Donor restriction applicable?', 'Finance to review where applicable.', true, 2),
  ('compliance_and_support', 'outstanding_advance', 'Outstanding imprest/advance?', 'Finance to confirm before clearance.', true, 3),

  ('finance_review', 'finance_comments', 'Finance comments', 'Finance review notes, queries, or clearance comments.', false, 1),
  ('finance_review', 'budget_available', 'Budget available?', 'As confirmed by Finance.', true, 2),

  ('final_processing', 'payment_voucher_number', 'Payment voucher number', 'Completed by Finance after approval.', true, 1),
  ('final_processing', 'qbo_posting_reference', 'QBO posting reference', 'Completed by Finance once posted in QBO Advanced.', false, 2),
  ('final_processing', 'payment_status', 'Payment status', 'Pending, approved for payment, paid, posted in QBO, or returned.', true, 3);
