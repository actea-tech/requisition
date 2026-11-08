import type { UserRole } from "@/lib/supabase/database.types";

// Settings > Approval Rules > Dashboard analytics (stored in app_settings).
export const ANALYTICS_ROLES_SETTING_KEY = "analytics_roles";
export const ANALYTICS_OVERDUE_DAYS_SETTING_KEY = "analytics_overdue_days";
export const ANALYTICS_INVOICE_OVERDUE_DAYS_SETTING_KEY = "analytics_invoice_overdue_days";

// The roles an admin can switch the analytics on for (Admin always sees it).
// Director, Finance Lead and Board Members see the whole organisation; every
// other role only ever sees what's relevant to them (see get_dashboard_analytics).
export const ANALYTICS_ROLE_CHOICES: { role: UserRole; scope: string }[] = [
  { role: "director", scope: "Whole organisation" },
  { role: "finance_accountant", scope: "Whole organisation" },
  { role: "board", scope: "Whole organisation" },
  { role: "finance_assistant", scope: "Requisitions assigned to them, and their own" },
  { role: "finance_reviewer", scope: "Requisitions they review, and their own" },
  { role: "dept_head", scope: "Their department(s), and their own" },
  { role: "staff", scope: "Their own requisitions" },
];

export const DEFAULT_ANALYTICS_ROLES: UserRole[] = ["director", "finance_accountant", "board"];
export const DEFAULT_OVERDUE_DAYS = 5;
export const DEFAULT_INVOICE_OVERDUE_DAYS = 30;

export function parseAnalyticsRoles(value: string | null | undefined): UserRole[] {
  if (value === null || value === undefined) return DEFAULT_ANALYTICS_ROLES;
  const known = new Set(ANALYTICS_ROLE_CHOICES.map((c) => c.role as string));
  return value
    .split(",")
    .map((v) => v.trim())
    .filter((v): v is UserRole => known.has(v));
}

export function serializeAnalyticsRoles(roles: UserRole[]): string {
  return ANALYTICS_ROLE_CHOICES.map((c) => c.role)
    .filter((r) => roles.includes(r))
    .join(",");
}

export function parseDays(value: string | null | undefined, fallback: number): number {
  return value && /^\d+$/.test(value) ? Number(value) : fallback;
}

export const ANALYTICS_RANGES = [
  { key: "all", label: "All time" },
  { key: "year", label: "This year" },
  { key: "quarter", label: "This quarter" },
  { key: "month", label: "This month" },
] as const;
export type AnalyticsRange = (typeof ANALYTICS_RANGES)[number]["key"];

export function parseRange(value: string | undefined): AnalyticsRange {
  return ANALYTICS_RANGES.some((r) => r.key === value) ? (value as AnalyticsRange) : "all";
}

export const SCOPE_LABELS: Record<string, string> = {
  org: "Whole organisation",
  department: "Your department(s) and your own requisitions",
  assigned: "Requisitions assigned to you and your own",
  reviewer: "Requisitions you review and your own",
  own: "Your own requisitions",
};

export interface AnalyticsOpenRow {
  id: string;
  requisition_number: string | null;
  purpose: string | null;
  status: string;
  currency: string;
  amount: number;
  requester_name: string | null;
  department_name: string | null;
  age_days: number;
  days_in_stage: number;
}

export interface AnalyticsInvoiceRow {
  id: string;
  requisition_number: string | null;
  purpose: string | null;
  currency: string;
  amount: number;
  requester_name: string | null;
  department_name: string | null;
  days_waiting: number;
}

export interface DashboardAnalytics {
  allowed: boolean;
  scope: string;
  range: AnalyticsRange;
  overdue_days: number;
  invoice_overdue_days: number;
  counts: { total: number; in_progress: number; completed: number; returned: number; rejected: number; cancelled: number };
  amounts: { currency: string; requisitioned: number; paid: number; pipeline: number }[];
  turnaround: { average_days: number | null; median_days: number | null; sample: number };
  overdue_count: number;
  by_stage: { status: string; count: number }[];
  oldest: AnalyticsOpenRow[];
  invoice_overdue: AnalyticsInvoiceRow[];
  awaiting_accounting: { count: number; amounts: { currency: string; amount: number }[] };
  /** Consolidated payments (left out of every other number above). */
  consolidated: { count: number; amounts: { currency: string; amount: number }[] };
  monthly: { month: string; submitted: number; completed: number }[];
  by_department: { department: string; currency: string; total: number; count: number }[];
}

export function formatMoney(amount: number, currency: string) {
  return `${currency} ${amount.toLocaleString(undefined, { maximumFractionDigits: 0 })}`;
}

export function formatDays(days: number | null) {
  if (days === null) return "—";
  return days === 1 ? "1 day" : `${days} days`;
}
