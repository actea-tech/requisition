import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";
import { Button } from "@/components/ui/button";
import { RequisitionsTable } from "@/components/requisitions/requisitions-table";

export default async function MyRequisitionsPage() {
  const profile = await requireProfile();
  const supabase = await createClient();

  const [{ data: requisitions }, { data: department }] = await Promise.all([
    supabase
      .from("requisitions")
      .select("id, requisition_number, status, purpose, amount, currency, created_at")
      .eq("requester_id", profile.id)
      .order("created_at", { ascending: false }),
    profile.department_id
      ? supabase.from("departments").select("name").eq("id", profile.department_id).single()
      : Promise.resolve({ data: null }),
  ]);

  const rows = (requisitions ?? []).map((r) => ({
    ...r,
    requesterName: profile.full_name,
    departmentName: department?.name ?? "—",
  }));

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">My Requisitions</h1>
          <p className="text-sm text-muted-foreground">Everything you&apos;ve submitted.</p>
        </div>
        <Button nativeButton={false} render={<Link href="/requisitions/new" />}>New requisition</Button>
      </div>

      <RequisitionsTable rows={rows} />
    </div>
  );
}
