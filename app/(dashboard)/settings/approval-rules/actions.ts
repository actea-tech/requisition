"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/auth/session";
import type { ApprovalMode, ApprovalStageKey } from "@/lib/supabase/database.types";

export async function setGlobalStageMode(
  stageKey: ApprovalStageKey,
  mode: ApprovalMode,
  quorumCount: number | null,
) {
  await requireAdmin();
  const supabase = await createClient();

  const { error } = await supabase
    .from("approval_stage_config")
    .update({ mode, quorum_count: mode === "quorum" ? quorumCount : null })
    .eq("stage_key", stageKey)
    .is("department_id", null);

  revalidatePath("/settings/approval-rules");
  return { error: error?.message ?? null };
}

export async function setDirectorAuthMode(mode: "accountant_discretion" | "amount_threshold") {
  await requireAdmin();
  const supabase = await createClient();

  const { error } = await supabase.from("app_settings").update({ value: mode }).eq("key", "director_auth_mode");

  revalidatePath("/settings/approval-rules");
  return { error: error?.message ?? null };
}

export async function upsertDirectorAuthThreshold(currency: string, thresholdAmount: number) {
  await requireAdmin();
  const supabase = await createClient();

  const { error } = await supabase
    .from("director_auth_thresholds")
    .upsert({ currency, threshold_amount: thresholdAmount }, { onConflict: "currency" });

  revalidatePath("/settings/approval-rules");
  return { error: error?.message ?? null };
}

export async function deleteDirectorAuthThreshold(currency: string) {
  await requireAdmin();
  const supabase = await createClient();
  await supabase.from("director_auth_thresholds").delete().eq("currency", currency);
  revalidatePath("/settings/approval-rules");
}

// A currency with no row here means the Assistant isn't eligible via
// threshold for it at all — only forwarding grants them a specific
// requisition in that case (see get_eligible_approver_ids, migration
// 0029). Deleting a threshold is how a currency gets "disabled".
export async function upsertFinanceAssistantThreshold(currency: string, thresholdAmount: number) {
  await requireAdmin();
  const supabase = await createClient();

  const { error } = await supabase
    .from("finance_assistant_thresholds")
    .upsert({ currency, threshold_amount: thresholdAmount }, { onConflict: "currency" });

  revalidatePath("/settings/approval-rules");
  return { error: error?.message ?? null };
}

export async function deleteFinanceAssistantThreshold(currency: string) {
  await requireAdmin();
  const supabase = await createClient();
  await supabase.from("finance_assistant_thresholds").delete().eq("currency", currency);
  revalidatePath("/settings/approval-rules");
}

export async function setPaymentStageCancellationEnabled(enabled: boolean) {
  await requireAdmin();
  const supabase = await createClient();

  const { error } = await supabase
    .from("app_settings")
    .update({ value: enabled ? "yes" : "no" })
    .eq("key", "payment_stage_cancellation_enabled");

  revalidatePath("/settings/approval-rules");
  return { error: error?.message ?? null };
}

export async function setNewRequisitionsEnabled(enabled: boolean) {
  await requireAdmin();
  const supabase = await createClient();

  const { error } = await supabase
    .from("app_settings")
    .update({ value: enabled ? "yes" : "no" })
    .eq("key", "new_requisitions_enabled");

  revalidatePath("/settings/approval-rules");
  revalidatePath("/requisitions/new");
  return { error: error?.message ?? null };
}
