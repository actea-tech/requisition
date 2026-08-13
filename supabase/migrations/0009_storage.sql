insert into storage.buckets (id, name, public)
values ('requisition-attachments', 'requisition-attachments', false)
on conflict (id) do nothing;

-- Files are uploaded to `<requisition_id>/<uuid>-<filename>`, so the first
-- path segment doubles as the ownership check — same visibility rule as
-- the requisition_attachments table itself.
create policy requisition_attachments_storage_select on storage.objects for select to authenticated
  using (
    bucket_id = 'requisition-attachments'
    and exists (
      select 1 from requisitions r
       where r.id::text = (storage.foldername(name))[1]
         and (
           r.requester_id = auth.uid()
           or auth_is_admin() or auth_is_finance() or auth_role() = 'director'
           or (auth_role() = 'dept_head' and auth_is_dept_head_of(r.department_id))
         )
    )
  );

create policy requisition_attachments_storage_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'requisition-attachments'
    and exists (
      select 1 from requisitions r
       where r.id::text = (storage.foldername(name))[1]
         and (r.requester_id = auth.uid() or auth_is_finance() or auth_is_admin())
    )
  );

create policy requisition_attachments_storage_delete on storage.objects for delete to authenticated
  using (bucket_id = 'requisition-attachments' and (owner = auth.uid() or auth_is_admin()));
