-- Isolated on purpose: a new enum value must be committed before it can be
-- referenced elsewhere (role checks, grants, etc. in later migrations).
alter type user_role add value 'finance_assistant';
