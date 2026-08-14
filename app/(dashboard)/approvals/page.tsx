import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";
import { RequisitionsTable } from "@/components/requisitions/requisitions-table";
import type { RequisitionStatus, UserRole } from "@/lib/supabase/database.types";

function statusesForRole(role: UserRole): RequisitionStatus[] {
  switch (role) {
    case "dept_head":
      return ["dept_review"];
    case "finance_accountant":
    case "finance_reviewer":
      return ["finance_review", "approved_for_payment"];
    case "director":
      return ["director_review"];
    case "admin":
      return ["dept_review", "finance_review", "director_review", "approved_for_payment"];
    default:
      return [];
  }
}

export default async function ApprovalsPage() {
  const profile = await requireProfile();
  if (profile.role === "staff") redirect("/");

  const supabase = await createClient();
  const statuses = statusesForRole(profile.role);

  const [{ data: requisitions }, { data: departments }, { data: requesterProfiles }] = await Promise.all([
    supabase
      .from("requisitions")
      .select("id, requisition_number, status, purpose, amount, currency, created_at, requester_id, department_id")
      .in("status", statuses)
      .order("created_at", { ascending: true }),
    supabase.from("departments").select("id, name"),
    supabase.from("profiles").select("id, full_name"),
  ]);

  const departmentById = new Map((departments ?? []).map((d) => [d.id, d.name]));
  const profileById = new Map((requesterProfiles ?? []).map((p) => [p.id, p.full_name]));

  const rows = (requisitions ?? []).map((r) => ({
    ...r,
    requesterName: profileById.get(r.requester_id) ?? "Unknown",
    departmentName: departmentById.get(r.department_id) ?? "—",
  }));

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold">Pending My Approval</h1>
        <p className="text-sm text-muted-foreground">Requisitions waiting on a decision from you.</p>
      </div>
      <RequisitionsTable rows={rows} />
    </div>
  );
}
