import type { UserRole } from "@/lib/supabase/database.types";

export const ROLE_LABELS: Record<UserRole, string> = {
  staff: "Staff",
  dept_head: "Department Head",
  finance_accountant: "Finance Accountant",
  finance_reviewer: "Finance Reviewer",
  director: "Director",
  admin: "Admin",
};

export const ROLE_OPTIONS = Object.entries(ROLE_LABELS).map(([value, label]) => ({
  value: value as UserRole,
  label,
}));

export function isFinanceRole(role: UserRole) {
  return role === "finance_accountant" || role === "finance_reviewer";
}

export function canAccessSettings(role: UserRole) {
  return role === "admin";
}

export function canViewAudit(role: UserRole) {
  return role === "admin" || isFinanceRole(role) || role === "director";
}
