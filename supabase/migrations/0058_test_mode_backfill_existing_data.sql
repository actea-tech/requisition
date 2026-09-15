-- Test mode, part 5: everything raised on the platform before this feature
-- existed was testing — flag all of it as test data now that the
-- production/test split exists. Existing requisition_number values
-- (REQ-<year>-<n>) are left exactly as issued, since some may already be
-- referenced in emails/PDFs/vouchers; this is about flagging past data, not
-- renumbering it. Production starts genuinely fresh: the (year, false)
-- counter is untouched, so the first real production requisition this year
-- is still REQ-<year>-0001.
update profiles set is_test_user = true;
update requisitions set is_test = true;

insert into requisition_number_counters (year, is_test, last_value)
  select year, true, last_value from requisition_number_counters where is_test = false
  on conflict (year, is_test) do update set last_value = excluded.last_value;

update requisition_number_counters set last_value = 0 where is_test = false;
