-- Product/Service (procurement) requisitions: a department head approves
-- the need and Finance confirms budget availability before an invoice
-- even exists, then the same requisition continues through the ordinary
-- finance_review/director_review/payment pipeline once the real invoice is
-- attached. Isolated migration (enum values only) per this project's
-- established convention — Postgres won't allow using a value added in the
-- same transaction it was added in.
alter type requisition_status add value 'procurement_dept_review';
alter type requisition_status add value 'procurement_finance_review';
alter type requisition_status add value 'awaiting_invoice';

alter type form_section add value 'procurement_documents';

alter type approval_decision add value 'invoice_submitted';
