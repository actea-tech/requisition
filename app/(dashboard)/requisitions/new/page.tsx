import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";

export default async function NewRequisitionPage() {
  const profile = await requireProfile();

  if (!profile.department_id) {
    return (
      <div className="mx-auto max-w-md rounded-lg border bg-card p-6 text-center">
        <h1 className="text-lg font-semibold">No department assigned</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Your account isn&apos;t assigned to a department yet, so a requisition can&apos;t be routed for
          approval. Ask your administrator to set your department in Settings &rarr; Users.
        </p>
      </div>
    );
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("requisitions")
    .insert({ requester_id: profile.id, department_id: profile.department_id })
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
