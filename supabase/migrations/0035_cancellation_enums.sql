-- Isolated on its own so both new enum values are committed before anything
-- else references them.
alter type requisition_status add value 'cancelled';
alter type approval_decision add value 'cancelled';
