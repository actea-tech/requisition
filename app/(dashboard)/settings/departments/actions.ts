"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/auth/session";
import type { ApprovalMode } from "@/lib/supabase/database.types";

export async function createDepartment(_prevState: { error: string | null }, formData: FormData) {
  await requireAdmin();
  const name = String(formData.get("name") ?? "").trim();
  if (!name) return { error: "Department name is required." };

  const supabase = await createClient();
  const { error } = await supabase.from("departments").insert({ name });
  if (error) return { error: error.message };

  revalidatePath("/settings/departments");
  return { error: null };
}

export async function setDepartmentActive(departmentId: string, isActive: boolean) {
  await requireAdmin();
  const supabase = await createClient();
  await supabase.from("departments").update({ is_active: isActive }).eq("id", departmentId);
  revalidatePath("/settings/departments");
}

export async function addDepartmentHead(departmentId: string, userId: string) {
  await requireAdmin();
  const supabase = await createClient();

  const { error } = await supabase.from("department_heads").insert({ department_id: departmentId, user_id: userId });
  if (error) return { error: error.message };

  // Give them the dept_head designation for display/nav purposes, unless
  // they already hold a broader role (finance/director/admin already see
  // "Pending My Approval" and shouldn't be downgraded).
  const { data: profile } = await supabase.from("profiles").select("role").eq("id", userId).single();
  if (profile?.role === "staff") {
    await supabase.from("profiles").update({ role: "dept_head" }).eq("id", userId);
  }

  revalidatePath("/settings/departments");
  return { error: null };
}

export async function removeDepartmentHead(departmentId: string, userId: string) {
  await requireAdmin();
  const supabase = await createClient();
  await supabase.from("department_heads").delete().eq("department_id", departmentId).eq("user_id", userId);
  revalidatePath("/settings/departments");
}

export async function setDepartmentApprovalOverride(
  departmentId: string,
  mode: ApprovalMode | "default",
  quorumCount: number | null,
) {
  await requireAdmin();
  const supabase = await createClient();

  if (mode === "default") {
    await supabase
      .from("approval_stage_config")
      .delete()
      .eq("stage_key", "department")
      .eq("department_id", departmentId);
    revalidatePath("/settings/departments");
    return { error: null };
  }

  // Not a plain .upsert(): the (stage_key, department_id) unique index is
  // partial (WHERE department_id IS NOT NULL — see migration 0004), and
  // PostgREST's upsert can't express that predicate in its ON CONFLICT
  // target, so it errors with "no unique constraint matching". Select then
  // insert/update instead.
  const quorum = mode === "quorum" ? quorumCount : null;
  const { data: existing } = await supabase
    .from("approval_stage_config")
    .select("id")
    .eq("stage_key", "department")
    .eq("department_id", departmentId)
    .maybeSingle();

  const { error } = existing
    ? await supabase.from("approval_stage_config").update({ mode, quorum_count: quorum }).eq("id", existing.id)
    : await supabase.from("approval_stage_config").insert({ stage_key: "department", department_id: departmentId, mode, quorum_count: quorum });

  if (error) return { error: error.message };
  revalidatePath("/settings/departments");
  return { error: null };
}
