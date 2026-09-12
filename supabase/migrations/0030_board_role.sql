-- Isolated on purpose: a new enum value must be committed before it can be
-- referenced elsewhere in a later migration.
alter type user_role add value 'board';
