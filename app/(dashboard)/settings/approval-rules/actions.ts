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
