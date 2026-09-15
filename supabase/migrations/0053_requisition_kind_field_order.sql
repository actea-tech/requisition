-- requisition_kind (migration 0049) was seeded with sort_order 1, tying
-- with 'purpose' (also 1, from migration 0003) — ties resolve by whatever
-- order Postgres happens to return them in, not reliably placing
-- Requisition kind right after Requisition type (sort_order 0). Bump
-- purpose/activity_project up to make room instead.
update form_field_config set sort_order = 2 where section = 'request_details' and field_key = 'purpose';
update form_field_config set sort_order = 3 where section = 'request_details' and field_key = 'activity_project';
