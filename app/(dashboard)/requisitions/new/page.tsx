import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";

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

  // Departmental only makes sense when there's actually a department head to
  // review it — with no department assigned at all, or a department with
  // nobody set as its head, Individual is the only routing that works.
  const { count: departmentHeadCount } = profile.department_id
    ? await supabase
        .from("department_heads")
        .select("user_id", { count: "exact", head: true })
        .eq("department_id", profile.department_id)
    : { count: 0 };
  const mustBeIndividual = !profile.department_id || (departmentHeadCount ?? 0) === 0;

  const { data, error } = await supabase
    .from("requisitions")
    .insert({
      requester_id: profile.id,
      department_id: profile.department_id,
      ...(mustBeIndividual ? { requisition_type: "individual" as const } : {}),
    })
    .select("id")
    .single();

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
