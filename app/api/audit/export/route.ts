import { NextResponse, type NextRequest } from "next/server";
import Papa from "papaparse";
import ExcelJS from "exceljs";
import { createClient } from "@/lib/supabase/server";
import { canViewAudit } from "@/lib/roles";
import { AUDIT_HEADERS, auditRowToValues, parseAuditFilters, queryAuditRows } from "@/lib/audit";
import { STATUS_LABELS } from "@/lib/requisition-status";
import type { RequisitionStatus } from "@/lib/supabase/database.types";

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

  const dataRows = rows.map((r) =>
    auditRowToValues(
      r,
      profileById.get(r.requester_id) ?? "",
      departmentById.get(r.department_id) ?? "",
      STATUS_LABELS[r.status as RequisitionStatus] ?? r.status,
    ),
  );

  const filenameBase = `actea-requisitions-${new Date().toISOString().slice(0, 10)}`;

  if (format === "csv") {
    const csv = Papa.unparse({ fields: AUDIT_HEADERS, data: dataRows });
    return new NextResponse(csv, {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": `attachment; filename="${filenameBase}.csv"`,
      },
    });
  }

  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet("Requisitions");
  sheet.addRow(AUDIT_HEADERS);
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
