"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";
import type { ApprovalDecision, Database } from "@/lib/supabase/database.types";

type RequisitionUpdate = Database["public"]["Tables"]["requisitions"]["Update"];

// Whitelist of columns any authenticated writer might send — the RLS
// column-level GRANTs (migration 0008) are the real enforcement; this just
// keeps the Server Action from forwarding stray keys.
const EDITABLE_FIELDS = [
  "purpose",
  "activity_project",
  "payee_name",
  "payee_contact",
  "amount",
  "currency",
  "payment_mode",
  "payment_mode_details",
  "budget_line",
  "account_code",
  "project_fund_class_code",
  "donor_grant_source",
  "budgeted",
  "procurement_required",
  "donor_restriction",
  "outstanding_advance",
  "finance_comments",
  "budget_available",
  "director_comments",
  "payment_voucher_number",
  "qbo_posting_reference",
  "payment_status",
] as const;

export async function updateRequisitionFields(requisitionId: string, values: Record<string, unknown>) {
  await requireProfile();
  const supabase = await createClient();

  const update: RequisitionUpdate = {};
  for (const key of EDITABLE_FIELDS) {
    if (key in values) {
      // @ts-expect-error — narrowing per-key against the union Update type isn't worth it here.
      update[key] = values[key] === "" ? null : values[key];
    }
  }

  const { error } = await supabase.from("requisitions").update(update).eq("id", requisitionId);

  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

export async function submitRequisitionAction(requisitionId: string) {
  const profile = await requireProfile();
  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_requisition", {
    p_requisition_id: requisitionId,
    p_actor_id: profile.id,
  });
  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

export async function resubmitRequisitionAction(requisitionId: string) {
  const profile = await requireProfile();
  const supabase = await createClient();
  const { error } = await supabase.rpc("resubmit_requisition", {
    p_requisition_id: requisitionId,
    p_actor_id: profile.id,
  });
  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

export async function recordDecisionAction(
  requisitionId: string,
  decision: ApprovalDecision,
  comments: string | null,
  returnTo: "requester" | "previous_stage" = "requester",
  requiresReapproval: boolean = true,
) {
  const profile = await requireProfile();
  const supabase = await createClient();
  const { error } = await supabase.rpc("record_approval_action", {
    p_requisition_id: requisitionId,
    p_actor_id: profile.id,
    p_decision: decision,
    p_comments: comments,
    p_return_to: returnTo,
    p_requires_reapproval: requiresReapproval,
  });
  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

export async function completePaymentAction(requisitionId: string, comments: string | null) {
  const profile = await requireProfile();
  const supabase = await createClient();
  const { error } = await supabase.rpc("complete_payment_processing", {
    p_requisition_id: requisitionId,
    p_actor_id: profile.id,
    p_comments: comments,
  });
  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

export async function deleteDraftRequisition(requisitionId: string) {
  await requireProfile();
  const supabase = await createClient();
  await supabase.from("requisitions").delete().eq("id", requisitionId);
}

export async function addFinanceApprover(requisitionId: string, userId: string) {
  const profile = await requireProfile();
  const supabase = await createClient();
  const { error } = await supabase
    .from("finance_approver_group")
    .insert({ requisition_id: requisitionId, user_id: userId, added_by: profile.id });
  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

export async function removeFinanceApprover(requisitionId: string, userId: string) {
  await requireProfile();
  const supabase = await createClient();
  await supabase.from("finance_approver_group").delete().eq("requisition_id", requisitionId).eq("user_id", userId);
  revalidatePath(`/requisitions/${requisitionId}`);
}

export async function deleteAttachment(attachmentId: string, storagePath: string, requisitionId: string) {
  await requireProfile();
  const supabase = await createClient();
  await supabase.storage.from("requisition-attachments").remove([storagePath]);
  await supabase.from("requisition_attachments").delete().eq("id", attachmentId);
  revalidatePath(`/requisitions/${requisitionId}`);
}

export async function getAttachmentSignedUrl(storagePath: string) {
  const supabase = await createClient();
  const { data } = await supabase.storage
    .from("requisition-attachments")
    .createSignedUrl(storagePath, 60 * 5);
  return data?.signedUrl ?? null;
}
