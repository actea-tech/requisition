-- Global default per stage, with an optional per-department override for the
-- 'department' stage (finance/director are always global — there's one
-- Finance group and one Director group org-wide).
create table approval_stage_config (
  id uuid primary key default gen_random_uuid(),
  stage_key approval_stage_key not null,
  department_id uuid references departments (id) on delete cascade,
  mode approval_mode not null default 'first_approver',
  quorum_count int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quorum_count_required check (
    (mode = 'quorum' and quorum_count is not null and quorum_count > 0)
    or (mode <> 'quorum')
  ),
  constraint only_department_stage_has_department check (
    department_id is null or stage_key = 'department'
  )
);

-- One global row per stage_key (department_id null), and at most one
-- override row per (stage_key, department_id) pair.
create unique index approval_stage_config_global_idx
  on approval_stage_config (stage_key)
  where department_id is null;

create unique index approval_stage_config_dept_idx
  on approval_stage_config (stage_key, department_id)
  where department_id is not null;

create trigger approval_stage_config_set_updated_at
  before update on approval_stage_config
  for each row execute function set_updated_at();

insert into approval_stage_config (stage_key, mode) values
  ('department', 'first_approver'),
  ('finance', 'first_approver'),
  ('director', 'first_approver');
