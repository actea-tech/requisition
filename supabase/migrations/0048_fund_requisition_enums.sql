-- Isolated on purpose (new enum values must be committed before use
-- elsewhere) — mirrors migration 0035's cancellation-enum pair and this
-- feature round's own 0044.
alter type requisition_status add value 'accounting_review';
alter type approval_decision add value 'accounting_submitted';
alter type approval_decision add value 'accounting_approved';
alter type approval_decision add value 'accounting_returned';
