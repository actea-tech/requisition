"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/auth/session";

export async function setFieldVisibility(id: string, isVisible: boolean) {
  await requireAdmin();
  const supabase = await createClient();
  await supabase.from("form_field_config").update({ is_visible: isVisible }).eq("id", id);
  revalidatePath("/settings/form-fields");
}

export async function setFieldRequired(id: string, isRequired: boolean) {
  await requireAdmin();
  const supabase = await createClient();
  await supabase.from("form_field_config").update({ is_required: isRequired }).eq("id", id);
  revalidatePath("/settings/form-fields");
}
