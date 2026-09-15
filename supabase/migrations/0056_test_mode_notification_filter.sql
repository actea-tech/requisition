-- Test mode, part 3: the single choke point every notify_role_group,
-- notify_finance_cleared_no_director, notify_director_approved,
-- notify_paid_posted, notify_assistant_forwarded, and
-- notify_finance_group_added call routes through — filtering here covers
-- all of them without touching any individually, and acts as a safety net
-- even if a recipient list passed in were ever built incorrectly upstream.
create or replace function enqueue_email_for_profiles(
  p_requisition_id uuid,
  p_template_key text,
  p_profile_ids uuid[],
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
begin
  for rec in
    select p.id, p.email, p.full_name
      from profiles p
      join requisitions r on r.id = p_requisition_id
     where p.id = any(p_profile_ids) and p.is_active and p.is_test_user = r.is_test
  loop
    perform enqueue_email(
      p_requisition_id, p_template_key, array[rec.email],
      p_payload || jsonb_build_object('recipient_name', rec.full_name)
    );
  end loop;
end;
$$;
