"use server";

import { randomBytes } from "node:crypto";
import { revalidatePath } from "next/cache";
import { requireAdmin } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import { ROLE_LABELS } from "@/lib/roles";
import type { UserRole } from "@/lib/supabase/database.types";

export async function inviteUser(_prevState: { error: string | null }, formData: FormData) {
  await requireAdmin();

  const fullName = String(formData.get("full_name") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const role = String(formData.get("role") ?? "staff") as UserRole;
  const departmentId = String(formData.get("department_id") ?? "") || null;

  if (!fullName || !email) {
    return { error: "Full name and email are required." };
  }

  const supabaseAdmin = createAdminClient();
  const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";
  const tempPassword = randomBytes(9).toString("base64url");

  const { error } = await supabaseAdmin.auth.admin.createUser({
    email,
    password: tempPassword,
    email_confirm: true,
    user_metadata: { full_name: fullName, role, department_id: departmentId },
  });

  if (error) {
    return { error: error.message };
  }

  const { data: department } = departmentId
    ? await supabaseAdmin.from("departments").select("name").eq("id", departmentId).single()
    : { data: null };

  await supabaseAdmin.rpc("enqueue_email", {
    p_requisition_id: null,
    p_template_key: "account_invite",
    p_to_emails: [email],
    p_payload: {
      full_name: fullName,
      role_label: ROLE_LABELS[role],
      department_name: department?.name ?? null,
      temp_password: tempPassword,
      login_link: `${appUrl}/login`,
    },
  });

  revalidatePath("/settings/users");
  return { error: null };
}

export async function updateUserRole(userId: string, role: UserRole, departmentId: string | null) {
  await requireAdmin();
  const supabaseAdmin = createAdminClient();
  const { error } = await supabaseAdmin.from("profiles").update({ role, department_id: departmentId }).eq("id", userId);
  revalidatePath("/settings/users");
  return { error: error?.message ?? null };
}

export async function setUserActive(userId: string, isActive: boolean) {
  await requireAdmin();
  const supabaseAdmin = createAdminClient();
  await supabaseAdmin.from("profiles").update({ is_active: isActive }).eq("id", userId);
  revalidatePath("/settings/users");
}
