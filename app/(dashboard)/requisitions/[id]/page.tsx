import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";
import { stageKeyForStatus } from "@/lib/requisition-status";
import {
  RequisitionWorkspace,
  type RequisitionRowForForm,
  type SectionSpec,
} from "@/components/requisitions/requisition-workspace";
import type { FormSection } from "@/lib/supabase/database.types";

const SECTION_DEFS: { key: FormSection; label: string }[] = [
  { key: "request_details", label: "Request Details" },
  { key: "payment_details", label: "Payment Details" },
  { key: "budget_and_coding", label: "Budget and Coding" },
  { key: "compliance_and_support", label: "Compliance and Support" },
  { key: "finance_review", label: "Finance Review" },
  { key: "final_processing", label: "Final Processing" },
];

export default async function RequisitionDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const profile = await requireProfile();
  const supabase = await createClient();

  const { data: requisition, error } = await supabase.from("requisitions").select("*").eq("id", id).single();
  if (error || !requisition) notFound();

  const [
    { data: fieldConfig },
    { data: attachmentsRaw },
    { data: historyRaw },
    { data: financeGroupRaw },
    { data: allProfiles },
    { data: department },
  ] = await Promise.all([
    supabase
      .from("form_field_config")
      .select("section, field_key, label, help_text, is_required, is_visible")
      .order("sort_order"),
    supabase
      .from("requisition_attachments")
      .select("id, file_name, file_size, storage_path, uploaded_by")
      .eq("requisition_id", id),
    supabase
      .from("approval_actions")
      .select("id, stage_key, decision, comments, created_at, actor_id")
      .eq("requisition_id", id)
      .order("created_at"),
    supabase.from("finance_approver_group").select("user_id").eq("requisition_id", id),
    supabase.from("profiles").select("id, full_name, role, is_active"),
    supabase.from("departments").select("name").eq("id", requisition.department_id).single(),
  ]);

  const profileById = new Map((allProfiles ?? []).map((p) => [p.id, p]));
  const nameFor = (uid: string | null) => (uid ? (profileById.get(uid)?.full_name ?? "Unknown") : "Unknown");

  const isOwner = requisition.requester_id === profile.id;
  const isAdmin = profile.role === "admin";

  // A "return to previous stage" targets that stage's approver(s) — treat
  // them exactly as if the requisition were back at that stage (same
  // decide panel, same field-edit rules), rather than a separate
  // edit-then-"Resubmit" flow. stage_key_for_status only recognizes the
  // active review statuses, so resolve against returned_from_stage first.
  const isReturnedToPreviousStage =
    requisition.status === "returned" && requisition.return_to === "previous_stage" && requisition.returned_from_stage !== null;
  const effectiveStatus = isReturnedToPreviousStage ? requisition.returned_from_stage! : requisition.status;
  const stageKey = stageKeyForStatus(effectiveStatus);

  let isEligibleApprover = false;
  if (stageKey && stageKey !== "payment") {
    const { data: eligibleIds } = await supabase.rpc("get_eligible_approver_ids", {
      p_requisition_id: id,
      p_stage_key: stageKey,
    });
    isEligibleApprover = isAdmin || Boolean(eligibleIds?.includes(profile.id));
  }

  const canDecide = stageKey === "department" || stageKey === "finance" || stageKey === "director" ? isEligibleApprover : false;
  const canEditFinance = stageKey === "finance" && isEligibleApprover;
  const canEditFinalProcessing =
    stageKey === "payment" && (isAdmin || requisition.finance_accountant_id === profile.id);

  // The requester's own edit-then-submit/resubmit flow — draft, or
  // returned straight back to them (not redirected to a previous stage).
  const canEditDraftFields =
    isOwner && (requisition.status === "draft" || (requisition.status === "returned" && !isReturnedToPreviousStage));
  const canUploadAttachments = canEditDraftFields || canEditFinance || isAdmin;

  const previousStageLabel = stageKey === "finance" ? "Department Head" : stageKey === "director" ? "Finance" : null;

  // Field/section visibility toggles (Settings > Form Fields) are a
  // requester-facing convenience only — from department head upward,
  // everyone sees every field (still not editable unless it's their turn),
  // per the current requirements.
  const restrictToRequesterView = isOwner && !canDecide && !canEditFinance && !canEditFinalProcessing && !isAdmin;
  const REQUESTER_VISIBLE_SECTIONS = new Set<FormSection>(["request_details", "payment_details"]);

  const sections: SectionSpec[] = SECTION_DEFS.filter(
    ({ key }) => !restrictToRequesterView || REQUESTER_VISIBLE_SECTIONS.has(key),
  ).map(({ key, label }) => ({
    key,
    label,
    editable:
      key === "request_details" || key === "payment_details"
        ? canEditDraftFields
        : key === "budget_and_coding" || key === "compliance_and_support"
          ? canEditFinance
          : key === "finance_review"
            ? canEditFinance
            : canEditFinalProcessing,
    fields: (fieldConfig ?? [])
      .filter(
        (f) =>
          f.section === key &&
          f.field_key !== "supporting_documents" &&
          (!restrictToRequesterView || f.is_visible),
      )
      .map((f) => ({
        field_key: f.field_key,
        label: f.label,
        help_text: f.help_text,
        is_required: f.is_required,
      })),
  }));

  const requisitionForForm: RequisitionRowForForm = {
    ...requisition,
    requesterName: nameFor(requisition.requester_id),
    departmentName: department?.name ?? "—",
  };

  const attachments = (attachmentsRaw ?? []).map((a) => ({
    id: a.id,
    file_name: a.file_name,
    file_size: a.file_size,
    storage_path: a.storage_path,
    uploaderName: nameFor(a.uploaded_by),
  }));

  const history = (historyRaw ?? []).map((h) => ({
    id: h.id,
    stage_key: h.stage_key,
    decision: h.decision,
    comments: h.comments,
    created_at: h.created_at,
    actorName: nameFor(h.actor_id),
  }));

  const financeGroup = (financeGroupRaw ?? []).map((m) => ({
    id: m.user_id,
    full_name: nameFor(m.user_id),
  }));

  const financeCandidates = (allProfiles ?? [])
    .filter((p) => p.is_active && (p.role === "finance_accountant" || p.role === "finance_reviewer"))
    .map((p) => ({ id: p.id, full_name: p.full_name }));

  return (
    <RequisitionWorkspace
      requisition={requisitionForForm}
      sections={sections}
      attachments={attachments}
      history={history}
      permissions={{
        canEditDraftFields,
        canDecide,
        canEditFinance,
        canEditFinalProcessing,
        canUploadAttachments,
        isOwnerDraft: canEditDraftFields,
      }}
      financeGroup={financeGroup}
      financeCandidates={financeCandidates}
      previousStageLabel={previousStageLabel}
    />
  );
}
