-- Isolated on its own so this new enum value is committed before anything
-- else references it (Postgres enum values must be committed before use).
alter type requisition_scope add value 'finance_direct';
