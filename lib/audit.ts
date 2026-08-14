import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, RequisitionStatus } from "@/lib/supabase/database.types";

export interface AuditFilters {
  status?: RequisitionStatus;
  departmentId?: string;
  fromDate?: string;
  toDate?: string;
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

export async function queryAuditRows(supabase: SupabaseClient<Database>, filters: AuditFilters) {
  let query = supabase
    .from("requisitions")
    .select(
      "id, requisition_number, created_at, submitted_at, status, requester_id, department_id, purpose, payee_name, amount, currency, payment_mode, budget_line, account_code, project_fund_class_code, donor_grant_source, donor_restriction, budget_available, payment_voucher_number, qbo_posting_reference, payment_status",
    )
    .order("created_at", { ascending: false });

  if (filters.status) query = query.eq("status", filters.status);
  if (filters.departmentId) query = query.eq("department_id", filters.departmentId);
  if (filters.fromDate) query = query.gte("created_at", filters.fromDate);
  if (filters.toDate) query = query.lte("created_at", `${filters.toDate}T23:59:59`);

  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return data ?? [];
}
