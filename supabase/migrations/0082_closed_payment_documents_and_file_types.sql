-- 1. Payment processing documents are a permanent record once a requisition
--    is Posted & Closed: no new ones, and none can be removed or changed —
--    enforced here so it holds for everyone (admins included) and however
--    the change is attempted.
--
-- 2. Which file types can be uploaded is a setting (Settings > Approval
--    Rules), stored as a comma-separated list of type ids. Finance's
--    proposal is PDF only, so that's the default; admins can switch more on.

create function protect_closed_payment_documents()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requisition_id uuid := coalesce(new.requisition_id, old.requisition_id);
  v_section form_section := coalesce(new.section, old.section);
begin
  if v_section = 'final_processing'
     and exists (select 1 from requisitions where id = v_requisition_id and status = 'posted_and_closed') then
    raise exception 'Payment processing documents on a closed requisition are a permanent record and can''t be added to, changed or removed';
  end if;
  return coalesce(new, old);
end;
$$;

-- A requisition (only ever a draft) being deleted cascades to its
-- attachments; by then its row no longer exists, so this doesn't apply.
create trigger requisition_attachments_protect_closed
  before insert or update or delete on requisition_attachments
  for each row execute function protect_closed_payment_documents();

-- The stored file itself too: the object can't be deleted straight from
-- storage while it belongs to a closed requisition's payment documents.
drop policy requisition_attachments_storage_delete on storage.objects;
create policy requisition_attachments_storage_delete on storage.objects for delete to authenticated
  using (
    bucket_id = 'requisition-attachments'
    and (owner = auth.uid() or auth_is_admin())
    and not exists (
      select 1
        from requisition_attachments a
        join requisitions r on r.id = a.requisition_id
       where a.storage_path = storage.objects.name
         and a.section = 'final_processing'
         and r.status = 'posted_and_closed'
    )
  );

insert into app_settings (key, value) values ('allowed_file_types', 'pdf')
on conflict (key) do nothing;
