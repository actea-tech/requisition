import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";
import { ChooseDepartmentForm } from "@/components/requisitions/choose-department-form";
import { createDraftRequisition } from "./actions";

export default async function NewRequisitionPage() {
  const profile = await requireProfile();
  const supabase = await createClient();

  if (profile.role !== "admin") {
    const { data: newRequisitionsRow } = await supabase
      .from("app_settings")
      .select("value")
      .eq("key", "new_requisitions_enabled")
      .maybeSingle();
    if (newRequisitionsRow?.value === "no") {
      return (
        <div className="mx-auto max-w-md rounded-lg border bg-card p-6 text-center">
          <h1 className="text-lg font-semibold">New requisitions are paused</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            An administrator has temporarily paused new requisitions. Please check back later.
          </p>
        </div>
      );
    }
  }

  const { data: memberships } = await supabase
    .from("profile_departments")
    .select("department_id")
    .eq("profile_id", profile.id);
  const membershipIds = (memberships ?? []).map((m) => m.department_id);

  let departmentId: string | null = null;
  if (membershipIds.length === 1) {
    departmentId = membershipIds[0];
  } else if (membershipIds.length > 1) {
    const { data: departments } = await supabase
      .from("departments")
      .select("id, name")
      .in("id", membershipIds)
      .order("name");
    return <ChooseDepartmentForm departments={departments ?? []} />;
  }
  // membershipIds.length === 0 → departmentId stays null (individual-only).

  const { data, error } = await createDraftRequisition(supabase, profile.id, departmentId);

  if (error || !data) {
    return (
      <div className="mx-auto max-w-md rounded-lg border bg-card p-6 text-center">
        <h1 className="text-lg font-semibold">Couldn&apos;t start a new requisition</h1>
        <p className="mt-2 text-sm text-muted-foreground">{error?.message}</p>
      </div>
    );
  }

  redirect(`/requisitions/${data.id}`);
}
