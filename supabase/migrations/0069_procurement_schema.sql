-- requisition_kind gains a third value alongside 'payment'/'fund'.
alter table requisitions drop constraint requisitions_requisition_kind_check;
alter table requisitions add constraint requisitions_requisition_kind_check
  check (requisition_kind in ('payment', 'fund', 'procurement'));

-- Set by Finance at Procurement — Finance Review (the budget-availability
-- pass); default off. If set, submitting the invoice restarts the
-- requisition from its type-appropriate first stage instead of proceeding
-- straight to the ordinary finance_review.
alter table requisitions add column requires_full_reapproval boolean not null default false;

-- Stamped by submit_procurement_invoice(); an audit timestamp, not load-
-- bearing for routing (procurement_finance_review and the ordinary
-- finance_review are separate statuses, so nothing needs this column to
-- tell them apart).
alter table requisitions add column invoice_submitted_at timestamptz;
