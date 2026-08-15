import { readFileSync } from "node:fs";
import path from "node:path";
import { NextResponse } from "next/server";
import { renderToBuffer } from "@react-pdf/renderer";
import { createClient } from "@/lib/supabase/server";
import { RequisitionPdfDocument, type RequisitionPdfData } from "@/lib/pdf/requisition-document";

// Embedded as a data URI rather than fetched by URL — react-pdf's Node
// renderer runs server-side with no need for a network round trip, and this
// avoids depending on NEXT_PUBLIC_APP_URL being reachable from the server.
function loadLogoDataUri(): string | null {
  try {
    const bytes = readFileSync(path.join(process.cwd(), "public", "actea-logo.png"));
    return `data:image/png;base64,${bytes.toString("base64")}`;
  } catch {
    return null;
  }
}

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
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
      { error: "PDF is only available for paid/posted or rejected requisitions." },
      { status: 400 },
    );
  }

  const [{ data: historyRaw }, { data: department }, { data: allProfiles }] = await Promise.all([
    supabase
      .from("approval_actions")
      .select("stage_key, decision, comments, created_at, actor_id")
      .eq("requisition_id", id)
      .order("created_at"),
    supabase.from("departments").select("name").eq("id", requisition.department_id).single(),
    supabase.from("profiles").select("id, full_name"),
  ]);

  const profileById = new Map((allProfiles ?? []).map((p) => [p.id, p.full_name]));
  const nameFor = (uid: string | null) => (uid ? (profileById.get(uid) ?? "Unknown") : "Unknown");

  const data: RequisitionPdfData = {
    requisition_number: requisition.requisition_number,
    requesterName: nameFor(requisition.requester_id),
    departmentName: department?.name ?? "—",
    purpose: requisition.purpose,
    activity_project: requisition.activity_project,
    payee_name: requisition.payee_name,
    payee_contact: requisition.payee_contact,
    amount: requisition.amount,
    currency: requisition.currency,
    payment_mode: requisition.payment_mode,
    payment_mode_details: requisition.payment_mode_details,
    budget_line: requisition.budget_line,
    account_code: requisition.account_code,
    project_fund_class_code: requisition.project_fund_class_code,
    donor_grant_source: requisition.donor_grant_source,
    payment_voucher_number: requisition.payment_voucher_number,
    qbo_posting_reference: requisition.qbo_posting_reference,
    submitted_at: requisition.submitted_at,
    history: (historyRaw ?? []).map((h) => ({
      stage_key: h.stage_key,
      decision: h.decision,
      comments: h.comments,
      created_at: h.created_at,
      actorName: nameFor(h.actor_id),
    })),
    generatedAt: new Date().toISOString(),
    logoSrc: loadLogoDataUri(),
    status: requisition.status as "paid_posted" | "rejected",
  };

  const buffer = await renderToBuffer(RequisitionPdfDocument({ data }));

  return new NextResponse(new Uint8Array(buffer), {
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": `attachment; filename="${requisition.requisition_number ?? id}.pdf"`,
    },
  });
}
