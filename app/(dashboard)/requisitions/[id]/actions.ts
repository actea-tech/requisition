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
  "requisition_type",
  "requisition_kind",
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
  authorizationMethod: string | null = null,
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
    p_authorization_method: authorizationMethod,
  });
  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

export async function setRequiresDirectorAuthorizationAction(requisitionId: string, value: "yes" | "no") {
  const profile = await requireProfile();
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_requires_director_authorization", {
    p_requisition_id: requisitionId,
    p_actor_id: profile.id,
    p_value: value,
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

export async function markPostedAndClosedAction(requisitionId: string, comments: string | null) {
  const profile = await requireProfile();
  const supabase = await createClient();
  const { error } = await supabase.rpc("mark_posted_and_closed", {
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

// Routed through RPCs (not a plain insert/delete) — adding one after the
// stage already resolved (requisition at Payment Processing) needs to
// reopen it for authorization, and removing one needs to re-check whether
// whoever's left has already fully approved. See migration 0034.
export async function addRequisitionAuthorizer(requisitionId: string, userId: string) {
  const profile = await requireProfile();
  const supabase = await createClient();
  const { error } = await supabase.rpc("add_requisition_authorizer", {
    p_requisition_id: requisitionId,
    p_actor_id: profile.id,
    p_user_id: userId,
  });
  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

export async function removeRequisitionAuthorizer(requisitionId: string, userId: string) {
  const profile = await requireProfile();
  const supabase = await createClient();
  const { error } = await supabase.rpc("remove_requisition_authorizer", {
    p_requisition_id: requisitionId,
    p_actor_id: profile.id,
    p_user_id: userId,
  });
  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

// Switching "Requires authorization?" back to No means any authorizers
// already selected are no longer relevant — clear them so a later switch
// back to Yes starts from an empty, deliberate selection rather than
// stale picks.
export async function clearRequisitionAuthorizers(requisitionId: string) {
  await requireProfile();
  const supabase = await createClient();
  await supabase.from("requisition_authorizers").delete().eq("requisition_id", requisitionId);
  revalidatePath(`/requisitions/${requisitionId}`);
}

// Single-active-forward semantics: forwarding replaces any prior forward
// for this requisition rather than stacking up multiple targets, so the
// UI can stay a one-click "forward to X" control instead of a picker list.
export async function forwardToAssistant(requisitionId: string, assistantId: string) {
  const profile = await requireProfile();
  const supabase = await createClient();
  await supabase.from("finance_assistant_forwards").delete().eq("requisition_id", requisitionId);
  const { error } = await supabase
    .from("finance_assistant_forwards")
    .insert({ requisition_id: requisitionId, assistant_id: assistantId, forwarded_by: profile.id });
  if (!error) {
    await supabase.rpc("notify_assistant_forwarded", {
      p_requisition_id: requisitionId,
      p_assistant_id: assistantId,
    });
  }
  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

export async function unforwardFromAssistant(requisitionId: string) {
  await requireProfile();
  const supabase = await createClient();
  await supabase.from("finance_assistant_forwards").delete().eq("requisition_id", requisitionId);
  revalidatePath(`/requisitions/${requisitionId}`);
}

export async function cancelRequisitionAction(requisitionId: string, reason: string) {
  const profile = await requireProfile();
  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_requisition", {
    p_requisition_id: requisitionId,
    p_actor_id: profile.id,
    p_reason: reason,
  });
  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

export async function decideCancellationAction(requisitionId: string, approve: boolean) {
  const profile = await requireProfile();
  const supabase = await createClient();
  const { error } = await supabase.rpc("decide_cancellation", {
    p_requisition_id: requisitionId,
    p_actor_id: profile.id,
    p_approve: approve,
  });
  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

export async function deleteAttachment(attachmentId: string, storagePath: string, requisitionId: string) {
  await requireProfile();
  const supabase = await createClient();
  await supabase.storage.from("requisition-attachments").remove([storagePath]);
  await supabase.from("requisition_attachments").delete().eq("id", attachmentId);
  revalidatePath(`/requisitions/${requisitionId}`);
}

export async function deleteExpenditure(expenditureId: string, storagePath: string | null, requisitionId: string) {
  await requireProfile();
  const supabase = await createClient();
  if (storagePath) await supabase.storage.from("requisition-attachments").remove([storagePath]);
  await supabase.from("requisition_expenditures").delete().eq("id", expenditureId);
  revalidatePath(`/requisitions/${requisitionId}`);
}

export async function submitRequisitionAccountingAction(requisitionId: string) {
  const profile = await requireProfile();
  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_requisition_accounting", {
    p_requisition_id: requisitionId,
    p_actor_id: profile.id,
  });
  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

export async function reviewRequisitionAccountingAction(
  requisitionId: string,
  approve: boolean,
  comments: string | null,
  shortfallNote: string | null,
) {
  const profile = await requireProfile();
  const supabase = await createClient();
  const { error } = await supabase.rpc("review_requisition_accounting", {
    p_requisition_id: requisitionId,
    p_actor_id: profile.id,
    p_approve: approve,
    p_comments: comments,
    p_shortfall_note: shortfallNote,
  });
  revalidatePath(`/requisitions/${requisitionId}`);
  return { error: error?.message ?? null };
}

export async function getAttachmentSignedUrl(storagePath: string) {
  const supabase = await createClient();
  const { data } = await supabase.storage
    .from("requisition-attachments")
    .createSignedUrl(storagePath, 60 * 5);
  return data?.signedUrl ?? null;
}
