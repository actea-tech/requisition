import { NextResponse, type NextRequest } from "next/server";
import Papa from "papaparse";
import ExcelJS from "exceljs";
import { createClient } from "@/lib/supabase/server";
import { AUDIT_HEADERS, auditRowToValues } from "@/lib/audit";
import { STATUS_LABELS } from "@/lib/requisition-status";
import type { RequisitionStatus } from "@/lib/supabase/database.types";

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  // RLS on `requisitions` already scopes this to rows the caller may see —
  // no separate authorization check needed here.
  const { data: requisition, error } = await supabase.from("requisitions").select("*").eq("id", id).single();
  if (error || !requisition) {
    return NextResponse.json({ error: "Requisition not found" }, { status: 404 });
  }

  if (requisition.status !== "paid_posted" && requisition.status !== "rejected") {
    return NextResponse.json(
      { error: "Export is only available for paid/posted or rejected requisitions." },
      { status: 400 },
    );
  }

  const format = request.nextUrl.searchParams.get("format") === "xlsx" ? "xlsx" : "csv";

  const [{ data: requesterProfile }, { data: department }] = await Promise.all([
    supabase.from("profiles").select("full_name").eq("id", requisition.requester_id).single(),
    supabase.from("departments").select("name").eq("id", requisition.department_id).single(),
  ]);

  const dataRow = auditRowToValues(
    requisition,
    requesterProfile?.full_name ?? "",
    department?.name ?? "",
    STATUS_LABELS[requisition.status as RequisitionStatus] ?? requisition.status,
  );

  const filenameBase = requisition.requisition_number ?? id;

  if (format === "csv") {
    const csv = Papa.unparse({ fields: AUDIT_HEADERS, data: [dataRow] });
    return new NextResponse(csv, {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": `attachment; filename="${filenameBase}.csv"`,
      },
    });
  }

  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet("Requisition");
  sheet.addRow(AUDIT_HEADERS);
  sheet.getRow(1).font = { bold: true };
  sheet.addRow(dataRow);
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
