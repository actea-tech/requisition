-- Recalling a requisition: audit-trail entries for the requester recalling it,
-- asking Finance to allow a recall, and Finance approving or declining that
-- request. Isolated migration (enum values only) per this project's
-- convention - Postgres won't allow using a value added in the same
-- transaction it was added in.
alter type approval_decision add value 'recalled';
alter type approval_decision add value 'recall_requested';
alter type approval_decision add value 'recall_approved';
alter type approval_decision add value 'recall_declined';
