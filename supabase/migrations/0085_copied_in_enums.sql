-- "Copied in": people the requester copies in to follow a requisition and
-- comment on it. A comment is recorded in the audit trail (approval_actions)
-- as its own decision. Isolated migration (enum value only) per this
-- project's convention - Postgres won't allow using a value added in the
-- same transaction it was added in.
alter type approval_decision add value 'commented';
