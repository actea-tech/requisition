import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";
import { RequisitionsTable } from "@/components/requisitions/requisitions-table";

// Uses get_pending_approval_requisition_ids (0018) rather than a plain
// status filter — a requisition's status only advances once its stage is
// FULLY resolved, so at a multi-approver stage (several department heads,
// an all_approvers/quorum-mode stage, more than one director) a status-only
// filter kept showing "pending" for someone who'd already approved. That
// function also excludes the viewer's own submissions (self-approval isn't
// possible anyway, see 0012). RLS is still the real authority on what each
// viewer can see (department_heads membership, finance role, director role,
// admin), and role can drift out of sync with that (see migration 0015).
export default async function ApprovalsPage() {
  const profile = await requireProfile();
  const supabase = await createClient();

  const { data: pendingIds } = await supabase.rpc("get_pending_approval_requisition_ids", {
    p_user_id: profile.id,
  });

  const [{ data: requisitions }, { data: departments }, { data: requesterProfiles }] = await Promise.all([
    supabase
      .from("requisitions")
      .select("id, requisition_number, status, purpose, amount, currency, created_at, requester_id, department_id")
      .in("id", pendingIds ?? [])
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
