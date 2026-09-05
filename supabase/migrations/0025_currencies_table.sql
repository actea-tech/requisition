-- Currency codes previously lived only as a hardcoded list in
-- lib/requisition-fields.ts (used for the requisition form's Currency
-- select), disconnected from the Director-authorization threshold table's
-- free-text currency field. One shared, admin-manageable table so both
-- pick from the same source — no FK from requisitions.currency /
-- director_auth_thresholds.currency on purpose, so removing a currency
-- here never breaks historical rows that already reference it.
create table currencies (
  code text primary key,
  created_at timestamptz not null default now()
);

alter table currencies enable row level security;

create policy currencies_select on currencies for select to authenticated using (true);
create policy currencies_write on currencies for all to authenticated
  using (auth_is_admin()) with check (auth_is_admin());

grant select, insert, delete on currencies to authenticated;

insert into currencies (code) values ('KES'), ('USD'), ('EUR'), ('GBP'), ('UGX'), ('TZS')
  on conflict (code) do nothing;
