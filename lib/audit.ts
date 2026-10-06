import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, RequisitionStatus } from "@/lib/supabase/database.types";

export interface AuditFilters {
  status?: RequisitionStatus;
  departmentId?: string;
  fromDate?: string;
  toDate?: string;
  requisitionNumber?: string;
  mode?: "test" | "production";
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
    mode: (get("mode") as "test" | "production") || undefined,
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
  "payees",
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
  "payment_reference",
] as const;

export const AUDIT_HEADERS = [
  "Requisition Number",
  "Date",
  "Submitted",
  "Status",
  "Requester",
  "Department",
  "Purpose",
  "Payee(s)",
  "Total Amount",
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
  "Payment Reference",
];

export interface AuditSourceRow {
  requisition_number: string | null;
  created_at: string;
  submitted_at: string | null;
  status: string;
  requester_id: string;
  department_id: string | null;
  purpose: string | null;
  amount: number | null;
  currency: string;
  budget_line: string | null;
  account_code: string | null;
  project_fund_class_code: string | null;
  donor_grant_source: string | null;
  donor_restriction: string | null;
  budget_available: string | null;
  payment_voucher_number: string | null;
  qbo_posting_reference: string | null;
  payment_status: string;
  payment_reference: string | null;
}

export interface AuditPayee {
  payee_name: string | null;
  amount: number | null;
  payment_mode: string | null;
}

// "Name (amount); Name (amount)" — one cell, since the export is one row per
// requisition. The full per-payee detail (contact, payment mode details)
// lives on the requisition itself and its PDF.
function summarizePayees(payees: AuditPayee[]) {
  const names = payees
    .map((p) => {
      const name = p.payee_name?.trim();
      if (!name && p.amount == null) return "";
      return `${name || "Unnamed payee"}${p.amount != null ? ` (${p.amount.toLocaleString()})` : ""}`;
    })
    .filter(Boolean)
    .join("; ");
  const modes = [...new Set(payees.map((p) => p.payment_mode?.trim()).filter((m): m is string => Boolean(m)))].join("; ");
  return { names, modes };
}

export function auditRowToValues(
  r: AuditSourceRow,
  requesterName: string,
  departmentName: string,
  statusLabel: string,
  payees: AuditPayee[] = [],
): (string | number)[] {
  const { names, modes } = summarizePayees(payees);
  return [
    r.requisition_number ?? "",
    new Date(r.created_at).toISOString().slice(0, 10),
    r.submitted_at ? new Date(r.submitted_at).toISOString().slice(0, 10) : "",
    statusLabel,
    requesterName,
    departmentName,
    r.purpose ?? "",
    names,
    r.amount ?? "",
    r.currency,
    modes,
    r.budget_line ?? "",
    r.account_code ?? "",
    r.project_fund_class_code ?? "",
    r.donor_grant_source ?? "",
    r.donor_restriction ?? "",
    r.budget_available ?? "",
    r.payment_voucher_number ?? "",
    r.qbo_posting_reference ?? "",
    r.payment_status,
    r.payment_reference ?? "",
  ];
}

export async function queryAuditRows(supabase: SupabaseClient<Database>, filters: AuditFilters) {
  let query = supabase
    .from("requisitions")
    .select(
      "id, requisition_number, created_at, submitted_at, status, requester_id, department_id, purpose, amount, currency, budget_line, account_code, project_fund_class_code, donor_grant_source, donor_restriction, budget_available, payment_voucher_number, qbo_posting_reference, payment_status, payment_reference",
    )
    .neq("status", "draft")
    .order("created_at", { ascending: false });

  if (filters.status) query = query.eq("status", filters.status);
  if (filters.departmentId) query = query.eq("department_id", filters.departmentId);
  if (filters.fromDate) query = query.gte("created_at", filters.fromDate);
  if (filters.toDate) query = query.lte("created_at", `${filters.toDate}T23:59:59`);
  if (filters.requisitionNumber) query = query.ilike("requisition_number", `%${filters.requisitionNumber}%`);
  if (filters.mode) query = query.eq("is_test", filters.mode === "test");

  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return data ?? [];
}

// requisition_payees for a set of requisitions, grouped by requisition id.
// Fetched in chunks: an `in (...)` filter goes in the request URL, so a few
// hundred ids at once would run past URL length limits.
export async function queryPayeesByRequisition(supabase: SupabaseClient<Database>, requisitionIds: string[]) {
  const byRequisition = new Map<string, AuditPayee[]>();
  const CHUNK = 100;
  for (let i = 0; i < requisitionIds.length; i += CHUNK) {
    const { data, error } = await supabase
      .from("requisition_payees")
      .select("requisition_id, payee_name, amount, payment_mode")
      .in("requisition_id", requisitionIds.slice(i, i + CHUNK))
      .order("sort_order")
      .order("created_at");
    if (error) throw new Error(error.message);
    for (const row of data ?? []) {
      const list = byRequisition.get(row.requisition_id) ?? [];
      list.push({ payee_name: row.payee_name, amount: row.amount, payment_mode: row.payment_mode });
      byRequisition.set(row.requisition_id, list);
    }
  }
  return byRequisition;
}
