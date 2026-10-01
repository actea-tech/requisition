-- Root cause of "Product/Service Requisition silently routes as Payment":
-- migration 0073 added the estimated_amount column but never granted
-- insert/update on it to authenticated (requisitions uses explicit
-- column-level grants — see migration 0008's comment: "Postgres requires
-- both a column grant AND a passing RLS policy for a write to succeed").
-- Every save from the requisition form sends estimated_amount in the same
-- single UPDATE statement as every other field (updateRequisitionFields
-- builds one combined update), so the missing grant made Postgres reject
-- the *entire* statement with "permission denied for column
-- estimated_amount" — including the requisition_kind change bundled in
-- it. The save genuinely failed (visible via "Save changes"); submitting
-- straight after silently carried on with the still-unchanged kind
-- (see the app-layer fix alongside this migration).
grant insert (estimated_amount) on requisitions to authenticated;
grant update (estimated_amount) on requisitions to authenticated;
