import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";

export default async function NewRequisitionPage() {
  const profile = await requireProfile();
  const supabase = await createClient();

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
