"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/auth/session";

export async function createCurrency(code: string) {
  await requireAdmin();
  const supabase = await createClient();

  const { error } = await supabase.from("currencies").insert({ code });
  if (error) return { error: error.message };

  revalidatePath("/settings/currencies");
  revalidatePath("/settings/approval-rules");
  return { error: null };
}

export async function deleteCurrency(code: string) {
  await requireAdmin();
  const supabase = await createClient();
  await supabase.from("currencies").delete().eq("code", code);
  revalidatePath("/settings/currencies");
  revalidatePath("/settings/approval-rules");
}
