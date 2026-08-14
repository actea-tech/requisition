"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";

export async function updateOwnName(_prevState: { error: string | null }, formData: FormData) {
  const profile = await requireProfile();
  const fullName = String(formData.get("full_name") ?? "").trim();
  if (!fullName) return { error: "Name is required." };

  const supabase = await createClient();
  const { error } = await supabase.from("profiles").update({ full_name: fullName }).eq("id", profile.id);
  if (error) return { error: error.message };

  revalidatePath("/profile");
  return { error: null };
}

export async function updateOwnPassword(_prevState: { error: string | null }, formData: FormData) {
  const password = String(formData.get("password") ?? "");
  const confirm = String(formData.get("confirm") ?? "");
  if (password.length < 8) return { error: "Password must be at least 8 characters." };
  if (password !== confirm) return { error: "Passwords don't match." };

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password });
  return { error: error?.message ?? null };
}
