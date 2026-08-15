import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, RequisitionStatus } from "@/lib/supabase/database.types";

export interface AuditFilters {
  status?: RequisitionStatus;
  departmentId?: string;
  fromDate?: string;
  toDate?: string;
  requisitionNumber?: string;
}

export function parseAuditFilters(searchParams: Record<string, string | string[] | undefined>): AuditFilters {
  const get = (key: string) => {
    const v = searchParams[key];
    return Array.isArray(v) ? v[0] : v;
  };

  return {
    status: (get("status") as RequisitionStatus) || undefined,
    departmentId: get("department") || undefined,
    fromDate: get("from") || undefined,
    toDate: get("to") || undefined,
    requisitionNumber: get("q") || undefined,
  };
}

export const AUDIT_COLUMNS = [
  "requisition_number",
  "created_at",
  "submitted_at",
  "status",
  "requester",
  "department",
  "purpose",
  "payee_name",
  "amount",
  "currency",
  "payment_mode",
  "budget_line",
  "account_code",
  "project_fund_class_code",
  "donor_grant_source",
  "donor_restriction",
  "budget_available",
  "payment_voucher_number",
  "qbo_posting_reference",
  "payment_status",
] as const;

export const AUDIT_HEADERS = [
  "Requisition Number",
  "Date",
  "Submitted",
  "Status",
  "Requester",
  "Department",
  "Purpose",
  "Payee",
  "Amount",
  "Currency",
  "Payment Mode",
  "Budget Line",
  "Account Code",
  "Project/Fund/Class Code",
  "Donor/Grant Source",
  "Donor Restriction",
  "Budget Available",
  "Payment Voucher Number",
  "QBO Posting Reference",
  "Payment Status",
];

export interface AuditSourceRow {
  requisition_number: string | null;
  created_at: string;
  submitted_at: string | null;
  status: string;
  requester_id: string;
  department_id: string;
  purpose: string | null;
  payee_name: string | null;
  amount: number | null;
  currency: string;
  payment_mode: string | null;
  budget_line: string | null;
  account_code: string | null;
  project_fund_class_code: string | null;
  donor_grant_source: string | null;
  donor_restriction: string | null;
  budget_available: string | null;
  payment_voucher_number: string | null;
  qbo_posting_reference: string | null;
  payment_status: string;
}

export function auditRowToValues(
  r: AuditSourceRow,
  requesterName: string,
  departmentName: string,
  statusLabel: string,
): (string | number)[] {
  return [
    r.requisition_number ?? "",
    new Date(r.created_at).toISOString().slice(0, 10),
    r.submitted_at ? new Date(r.submitted_at).toISOString().slice(0, 10) : "",
    statusLabel,
    requesterName,
    departmentName,
    r.purpose ?? "",
    r.payee_name ?? "",
    r.amount ?? "",
    r.currency,
    r.payment_mode ?? "",
    r.budget_line ?? "",
    r.account_code ?? "",
    r.project_fund_class_code ?? "",
    r.donor_grant_source ?? "",
    r.donor_restriction ?? "",
    r.budget_available ?? "",
    r.payment_voucher_number ?? "",
    r.qbo_posting_reference ?? "",
    r.payment_status,
  ];
}

export async function queryAuditRows(supabase: SupabaseClient<Database>, filters: AuditFilters) {
  let query = supabase
    .from("requisitions")
    .select(
      "id, requisition_number, created_at, submitted_at, status, requester_id, department_id, purpose, payee_name, amount, currency, payment_mode, budget_line, account_code, project_fund_class_code, donor_grant_source, donor_restriction, budget_available, payment_voucher_number, qbo_posting_reference, payment_status",
    )
    .neq("status", "draft")
    .order("created_at", { ascending: false });

  if (filters.status) query = query.eq("status", filters.status);
  if (filters.departmentId) query = query.eq("department_id", filters.departmentId);
  if (filters.fromDate) query = query.gte("created_at", filters.fromDate);
  if (filters.toDate) query = query.lte("created_at", `${filters.toDate}T23:59:59`);
  if (filters.requisitionNumber) query = query.ilike("requisition_number", `%${filters.requisitionNumber}%`);

  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return data ?? [];
}
