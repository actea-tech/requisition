"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/auth/session";

export async function addToAuthorizerPool(userId: string) {
  const profile = await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("authorizer_pool").insert({ user_id: userId, added_by: profile.id });
  revalidatePath("/settings/authorizers");
  return { error: error?.message ?? null };
}

export async function removeFromAuthorizerPool(userId: string) {
  await requireAdmin();
  const supabase = await createClient();
  await supabase.from("authorizer_pool").delete().eq("user_id", userId);
  revalidatePath("/settings/authorizers");
}

export async function setMinAuthorizerCount(count: number) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase
    .from("app_settings")
    .update({ value: String(count) })
    .eq("key", "min_authorizer_count");
  revalidatePath("/settings/authorizers");
  return { error: error?.message ?? null };
}

export async function createAuthorizationMethod(label: string) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("authorization_methods").insert({ label });
  if (error) return { error: error.message };
  revalidatePath("/settings/authorizers");
  return { error: null };
}

export async function deleteAuthorizationMethod(id: string) {
  await requireAdmin();
  const supabase = await createClient();
  await supabase.from("authorization_methods").delete().eq("id", id);
  revalidatePath("/settings/authorizers");
}
