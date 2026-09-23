-- A profile can now belong to more than one department. department_heads
-- was already a proper many-to-many join table (a user can already be head
-- of multiple departments), but plain membership was a single nullable
-- profiles.department_id column — replaced here by profile_departments.
create table profile_departments (
  profile_id uuid not null references profiles (id) on delete cascade,
  department_id uuid not null references departments (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (profile_id, department_id)
);

alter table profile_departments enable row level security;

create policy profile_departments_select on profile_departments for select to authenticated using (true);
create policy profile_departments_write on profile_departments for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());

grant select, insert, delete on profile_departments to authenticated;

insert into profile_departments (profile_id, department_id)
select id, department_id from profiles where department_id is not null;

create function auth_is_member_of_department(p_department_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from profile_departments where department_id = p_department_id and profile_id = auth.uid()
  );
$$;

grant execute on function auth_is_member_of_department(uuid) to authenticated;

-- auth_department_id()'s only two callers are rewritten below; its body
-- (`select department_id from profiles ...`) would break once the column
-- is gone, so it's dropped rather than left as dead code.
drop policy profiles_update_self on profiles;
drop policy requisitions_insert on requisitions;
drop function auth_department_id();

-- Department membership isn't a profiles column anymore, so there's
-- nothing left to guard here beyond role.
create policy profiles_update_self on profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid() and role = auth_role());

create policy requisitions_insert on requisitions for insert to authenticated
  with check (
    requester_id = auth.uid()
    and (department_id is null or auth_is_member_of_department(department_id))
    and status = 'draft'
    and (auth_is_admin() or app_new_requisitions_enabled())
  );

-- The invite flow now sends a JSON array of department ids instead of one.
create or replace function handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.email),
    new.email,
    coalesce((new.raw_user_meta_data ->> 'role')::user_role, 'staff')
  );

  insert into public.profile_departments (profile_id, department_id)
  select new.id, dept_id::uuid
    from jsonb_array_elements_text(coalesce(new.raw_user_meta_data -> 'department_ids', '[]'::jsonb)) as dept_id;

  return new;
end;
$$;

alter table profiles drop column department_id;
