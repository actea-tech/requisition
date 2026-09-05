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
  // Read from app_settings (same source the send-email function uses) —
  // not process.env.NEXT_PUBLIC_APP_URL, which drifts from the deployed
  // domain and was the cause of emails linking to localhost.
  const { data: appUrlSetting } = await supabaseAdmin.from("app_settings").select("value").eq("key", "app_url").single();
  const appUrl = appUrlSetting?.value ?? process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";
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

// Covers both cases from the same mechanism — generate a fresh temp
// password, force must_change_password back on, email it — since neither
// the account_invite flow's original temp password nor a forgotten one is
// ever retrievable afterwards. Only the email copy differs: a user who's
// never signed in yet gets their original "account_invite" wording resent
// (still accurate — they still haven't set anything up); an already-active
// user who forgot their password gets "password_reset" instead, since
// telling them "an account was created for you" would be misleading.
export async function resetUserPassword(userId: string) {
  await requireAdmin();
  const supabaseAdmin = createAdminClient();

  const { data: profile } = await supabaseAdmin
    .from("profiles")
    .select("full_name, email, role, department_id, must_change_password")
    .eq("id", userId)
    .single();
  if (!profile) return { error: "User not found." };

  const tempPassword = randomBytes(9).toString("base64url");
  const { error: authError } = await supabaseAdmin.auth.admin.updateUserById(userId, { password: tempPassword });
  if (authError) return { error: authError.message };

  await supabaseAdmin.from("profiles").update({ must_change_password: true }).eq("id", userId);

  const { data: appUrlSetting } = await supabaseAdmin.from("app_settings").select("value").eq("key", "app_url").single();
  const appUrl = appUrlSetting?.value ?? process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";

  const { data: department } = profile.department_id
    ? await supabaseAdmin.from("departments").select("name").eq("id", profile.department_id).single()
    : { data: null };

  await supabaseAdmin.rpc("enqueue_email", {
    p_requisition_id: null,
    p_template_key: profile.must_change_password ? "account_invite" : "password_reset",
    p_to_emails: [profile.email],
    p_payload: {
      full_name: profile.full_name,
      role_label: ROLE_LABELS[profile.role],
      department_name: department?.name ?? null,
      temp_password: tempPassword,
      login_link: `${appUrl}/login`,
    },
  });

  revalidatePath("/settings/users");
  return { error: null };
}

export async function deleteUser(userId: string) {
  const admin = await requireAdmin();
  if (userId === admin.id) {
    return { error: "You can't delete your own account." };
  }

  // profiles.id references auth.users(id) on delete cascade, so deleting
  // the auth user (not just the profiles row) is what actually removes
  // them — and requisitions.requester_id/finance_accountant_id/director_id,
  // approval_actions.actor_id, requisition_attachments.uploaded_by, and
  // finance_approver_group.added_by all reference profiles with no cascade,
  // so that delete is blocked if this user has any requisition history.
  const supabaseAdmin = createAdminClient();
  const { error } = await supabaseAdmin.auth.admin.deleteUser(userId);
  if (error) {
    const message = /foreign key|violates|constraint/i.test(error.message)
      ? "This user has requisition history and can't be removed. Disable them instead."
      : error.message;
    return { error: message };
  }

  revalidatePath("/settings/users");
  return { error: null };
}
