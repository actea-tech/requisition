"use server";

import { redirect } from "next/navigation";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";
import type { Database } from "@/lib/supabase/database.types";

// Departmental only makes sense when there's actually a department head to
// review it — with no department at all, or a department with nobody set
// as its head, Individual is the only routing that works. Shared by the
// page (0/1-department requesters) and createRequisitionInDepartment below
// (2+-department requesters, after they've picked one).
export async function createDraftRequisition(
  supabase: SupabaseClient<Database>,
  requesterId: string,
  departmentId: string | null,
) {
  const { count: departmentHeadCount } = departmentId
    ? await supabase
        .from("department_heads")
        .select("user_id", { count: "exact", head: true })
        .eq("department_id", departmentId)
    : { count: 0 };
  const mustBeIndividual = !departmentId || (departmentHeadCount ?? 0) === 0;

  return supabase
    .from("requisitions")
    .insert({
      requester_id: requesterId,
      department_id: departmentId,
      ...(mustBeIndividual ? { requisition_type: "individual" as const } : {}),
    })
    .select("id")
    .single();
}

export async function createRequisitionInDepartment(departmentId: string) {
  const profile = await requireProfile();
  const supabase = await createClient();

  const { count: membershipCount } = await supabase
    .from("profile_departments")
    .select("department_id", { count: "exact", head: true })
    .eq("profile_id", profile.id)
    .eq("department_id", departmentId);
  if (!membershipCount) {
    return { error: "You don't belong to that department." };
  }

  const { data, error } = await createDraftRequisition(supabase, profile.id, departmentId);
  if (error || !data) {
    return { error: error?.message ?? "Couldn't start a new requisition." };
  }

  redirect(`/requisitions/${data.id}`);
}
