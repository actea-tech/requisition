import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";
import { Button } from "@/components/ui/button";
import { RequisitionsTable } from "@/components/requisitions/requisitions-table";
import { cn } from "@/lib/utils";

const TABS = [
  { key: "all", label: "All" },
  { key: "draft", label: "Drafts" },
  { key: "active", label: "In Progress" },
  { key: "accounting", label: "Accounting" },
  { key: "done", label: "Closed" },
] as const;

export default async function MyRequisitionsPage({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string }>;
}) {
  const { tab = "all" } = await searchParams;
  const profile = await requireProfile();
  const supabase = await createClient();

  let query = supabase
    .from("requisitions")
    .select("id, requisition_number, status, purpose, amount, currency, created_at, department_id")
    .eq("requester_id", profile.id)
    .order("created_at", { ascending: false });

  if (tab === "draft") query = query.in("status", ["draft", "returned"]);
  else if (tab === "active")
    query = query.in("status", ["dept_review", "finance_review", "director_review", "approved_for_payment", "paid_posted"]);
  // Fund requisitions specifically at the accounting stage — either still
  // awaiting your own submission (paid_posted) or already submitted and
  // awaiting Finance's review (accounting_review). Also reachable from the
  // dashboard's "Needs your accounting" card.
  else if (tab === "accounting" || tab === "needs_accounting")
    query = query.eq("requisition_kind", "fund").in("status", ["paid_posted", "accounting_review"]);
  // paid_posted moved to "active"/"accounting" above — it isn't actually
  // closed yet (still awaiting either accounting or Finance's Posted &
  // Closed step), so only genuinely terminal statuses belong here now.
  else if (tab === "done") query = query.in("status", ["posted_and_closed", "rejected"]);

  const [{ data: requisitions }, { data: departments }] = await Promise.all([
    query,
    supabase.from("departments").select("id, name"),
  ]);

  const departmentById = new Map((departments ?? []).map((d) => [d.id, d.name]));

  const rows = (requisitions ?? []).map((r) => ({
    ...r,
    requesterName: profile.full_name,
    departmentName: (r.department_id && departmentById.get(r.department_id)) ?? "—",
  }));

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">My Requisitions</h1>
          <p className="text-sm text-muted-foreground">Everything you&apos;ve submitted, including drafts.</p>
        </div>
        <Button render={<Link href="/requisitions/new" />} nativeButton={false}>
          New requisition
        </Button>
      </div>

      <div className="flex gap-1 border-b">
        {TABS.map((t) => (
          <Link
            key={t.key}
            href={t.key === "all" ? "/requisitions" : `/requisitions?tab=${t.key}`}
            className={cn(
              "border-b-2 px-3 py-2 text-sm font-medium transition-colors",
              tab === t.key ? "border-primary text-primary" : "border-transparent text-muted-foreground hover:text-foreground",
            )}
          >
            {t.label}
          </Link>
        ))}
      </div>

      <RequisitionsTable rows={rows} />
    </div>
  );
}
