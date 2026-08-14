import { NextResponse, type NextRequest } from "next/server";
import Papa from "papaparse";
import ExcelJS from "exceljs";
import { createClient } from "@/lib/supabase/server";
import { canViewAudit } from "@/lib/roles";
import { parseAuditFilters, queryAuditRows } from "@/lib/audit";
import { STATUS_LABELS } from "@/lib/requisition-status";
import type { RequisitionStatus } from "@/lib/supabase/database.types";

const HEADERS = [
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

export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const { data: profile } = await supabase.from("profiles").select("role").eq("id", userData.user.id).single();
  if (!profile || !canViewAudit(profile.role)) {
    return NextResponse.json({ error: "Not authorized" }, { status: 403 });
  }

  const searchParams = Object.fromEntries(request.nextUrl.searchParams.entries());
  const filters = parseAuditFilters(searchParams);
  const format = searchParams.format === "xlsx" ? "xlsx" : "csv";

  const [rows, { data: departments }, { data: profiles }] = await Promise.all([
    queryAuditRows(supabase, filters),
    supabase.from("departments").select("id, name"),
    supabase.from("profiles").select("id, full_name"),
  ]);

  const departmentById = new Map((departments ?? []).map((d) => [d.id, d.name]));
  const profileById = new Map((profiles ?? []).map((p) => [p.id, p.full_name]));

  const dataRows = rows.map((r) => [
    r.requisition_number,
    new Date(r.created_at).toISOString().slice(0, 10),
    r.submitted_at ? new Date(r.submitted_at).toISOString().slice(0, 10) : "",
    STATUS_LABELS[r.status as RequisitionStatus] ?? r.status,
    profileById.get(r.requester_id) ?? "",
    departmentById.get(r.department_id) ?? "",
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
  ]);

  const filenameBase = `actea-requisitions-${new Date().toISOString().slice(0, 10)}`;

  if (format === "csv") {
    const csv = Papa.unparse({ fields: HEADERS, data: dataRows });
    return new NextResponse(csv, {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": `attachment; filename="${filenameBase}.csv"`,
      },
    });
  }

  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet("Requisitions");
  sheet.addRow(HEADERS);
  sheet.getRow(1).font = { bold: true };
  dataRows.forEach((row) => sheet.addRow(row));
  sheet.columns.forEach((column) => {
    column.width = 18;
  });

  const buffer = await workbook.xlsx.writeBuffer();

  return new NextResponse(buffer, {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="${filenameBase}.xlsx"`,
    },
  });
}
