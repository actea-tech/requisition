-- Isolated on purpose (new enum values must be committed before use
-- elsewhere) — mirrors migration 0035's cancellation-enum pair.
alter type requisition_status add value 'posted_and_closed';
alter type approval_decision add value 'posted_and_closed';
