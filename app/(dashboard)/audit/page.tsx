import { redirect } from "next/navigation";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";
import { canViewAudit } from "@/lib/roles";
import { parseAuditFilters, queryAuditRows } from "@/lib/audit";
import { AuditFiltersForm } from "@/components/audit/audit-filters";
import { RequisitionsTable } from "@/components/requisitions/requisitions-table";
import { Button } from "@/components/ui/button";

export default async function AuditPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const profile = await requireProfile();
  if (!canViewAudit(profile.role)) redirect("/");

  const resolvedParams = await searchParams;
  const filters = parseAuditFilters(resolvedParams);
  const supabase = await createClient();

  const [rows, { data: departments }, { data: profiles }] = await Promise.all([
    queryAuditRows(supabase, filters),
    supabase.from("departments").select("id, name").order("name"),
    supabase.from("profiles").select("id, full_name"),
  ]);

  const departmentById = new Map((departments ?? []).map((d) => [d.id, d.name]));
  const profileById = new Map((profiles ?? []).map((p) => [p.id, p.full_name]));

  const tableRows = rows.map((r) => ({
    id: r.id,
    requisition_number: r.requisition_number,
    status: r.status,
    purpose: r.purpose,
    amount: r.amount,
    currency: r.currency,
    created_at: r.created_at,
    requesterName: profileById.get(r.requester_id) ?? "Unknown",
    departmentName: departmentById.get(r.department_id) ?? "—",
  }));

  const exportQuery = new URLSearchParams(
    Object.entries(resolvedParams).flatMap(([k, v]) => (v ? [[k, Array.isArray(v) ? v[0] : v] as [string, string]] : [])),
  ).toString();

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-2xl font-semibold">Audit Trail</h1>
          <p className="text-sm text-muted-foreground">
            {rows.length} requisition{rows.length === 1 ? "" : "s"} matching these filters.
          </p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" render={<Link href={`/api/audit/export?format=csv&${exportQuery}`} />}>
            Export CSV
          </Button>
          <Button variant="outline" render={<Link href={`/api/audit/export?format=xlsx&${exportQuery}`} />}>
            Export XLSX
          </Button>
        </div>
      </div>

      <AuditFiltersForm departments={departments ?? []} />
      <RequisitionsTable rows={tableRows} />
    </div>
  );
}
