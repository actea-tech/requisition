-- finance_approver_group_write allowed any finance-role user (accountant or
-- reviewer) to add/remove group members, and canEditFinance — true for any
-- eligible finance approver, including reviewers already in the group — let
-- an added Finance Reviewer see the panel and add more reviewers themselves.
-- Only the accountant (or admin) should manage this group; the app layer
-- gate is canManageFinanceGroup, this is the matching DB-level enforcement.
drop policy finance_approver_group_write on finance_approver_group;
create policy finance_approver_group_write on finance_approver_group for all to authenticated
  using (auth_role() = 'finance_accountant' or auth_is_admin())
  with check (auth_role() = 'finance_accountant' or auth_is_admin());
