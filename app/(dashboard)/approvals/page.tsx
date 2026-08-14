import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";
import { RequisitionsTable } from "@/components/requisitions/requisitions-table";
import { PENDING_APPROVAL_OR_FILTER } from "@/lib/requisition-status";

// Deliberately doesn't pre-filter statuses by profile.role — RLS is the
// actual authority on what each viewer can see (department_heads
// membership, finance role, director role, admin), and role can drift out
// of sync with that (see migration 0015). Excludes the viewer's own
// submissions since self-approval isn't possible anyway (0012).
export default async function ApprovalsPage() {
  const profile = await requireProfile();
  const supabase = await createClient();

  const [{ data: requisitions }, { data: departments }, { data: requesterProfiles }] = await Promise.all([
    supabase
      .from("requisitions")
      .select("id, requisition_number, status, purpose, amount, currency, created_at, requester_id, department_id")
      .or(PENDING_APPROVAL_OR_FILTER)
      .neq("requester_id", profile.id)
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
