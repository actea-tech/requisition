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
import { REQUISITION_TYPES, FINANCE_DIRECT_REQUISITION_TYPE } from "@/lib/requisition-fields";

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
    { data: directorAuthModeRow },
    { data: currenciesRaw },
    { data: authorizersRaw },
    { data: authorizerPoolRaw },
    { data: authorizationMethodsRaw },
    { data: assistantForwardsRaw },
    { data: expendituresRaw },
    { data: paymentCancellationSettingRow },
  ] = await Promise.all([
    supabase
      .from("form_field_config")
      .select("section, field_key, label, help_text, is_required, is_visible")
      .order("sort_order"),
    supabase
      .from("requisition_attachments")
      .select("id, file_name, file_size, storage_path, uploaded_by, section, description")
      .eq("requisition_id", id),
    supabase
      .from("approval_actions")
      .select("id, stage_key, decision, comments, created_at, actor_id")
      .eq("requisition_id", id)
      .order("created_at"),
    supabase.from("finance_approver_group").select("user_id").eq("requisition_id", id),
    supabase.from("profiles").select("id, full_name, role, is_active"),
    supabase.from("departments").select("name").eq("id", requisition.department_id).single(),
    supabase.from("app_settings").select("value").eq("key", "director_auth_mode").maybeSingle(),
    supabase.from("currencies").select("code").order("code"),
    supabase.from("requisition_authorizers").select("user_id").eq("requisition_id", id),
    supabase.from("authorizer_pool").select("user_id"),
    supabase.from("authorization_methods").select("id, label").order("sort_order"),
    supabase.from("finance_assistant_forwards").select("assistant_id").eq("requisition_id", id),
    supabase
      .from("requisition_expenditures")
      .select("id, entry_type, description, amount, storage_path")
      .eq("requisition_id", id)
      .order("created_at"),
    supabase.from("app_settings").select("value").eq("key", "payment_stage_cancellation_enabled").maybeSingle(),
  ]);

  const currencyOptions = (currenciesRaw ?? []).map((c) => ({ value: c.code, label: c.code }));

  const profileById = new Map((allProfiles ?? []).map((p) => [p.id, p]));
  const nameFor = (uid: string | null) => (uid ? (profileById.get(uid)?.full_name ?? "Unknown") : "Unknown");

  const isOwner = requisition.requester_id === profile.id;
  const isAdmin = profile.role === "admin";
  // A Finance Accountant forwarding to their Assistant is full delegation —
  // the Assistant should be able to do anything the Accountant could for
  // this specific requisition, not just approve/reject it.
  const isForwardedAssistant = (assistantForwardsRaw?.[0]?.assistant_id ?? null) === profile.id;

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

  // At multi-approver stages, this user's own 'approved' vote for the
  // current round already counts — don't let them act (or vote) again.
  // Exempt while returned to a previous stage: stage_entered_at only
  // resets once resubmit_requisition runs (on the first click), so until
  // then it still reflects the prior round — every finance approver who
  // already cleared it before Director sent it back would otherwise be
  // wrongly excluded from this fresh round (matches get_pending_approval_
  // requisition_ids in 0018, which treats this the same way).
  const alreadyApprovedThisRound =
    !isReturnedToPreviousStage &&
    (historyRaw ?? []).some(
      (h) =>
        h.stage_key === stageKey &&
        h.actor_id === profile.id &&
        h.decision === "approved" &&
        h.created_at >= requisition.stage_entered_at,
    );

  const canDecide =
    (stageKey === "department" || stageKey === "finance" || stageKey === "director") &&
    isEligibleApprover &&
    !alreadyApprovedThisRound;
  const canEditFinance = stageKey === "finance" && isEligibleApprover;
  // Only the accountant role manages who else reviews — not every eligible
  // finance approver (which would let an added Finance Reviewer add more).
  // A forwarded Assistant is a full stand-in for the Accountant on this
  // requisition, so they get the same right.
  const canManageFinanceGroup =
    stageKey === "finance" && (isAdmin || profile.role === "finance_accountant" || isForwardedAssistant);
  const directorAuthMode = directorAuthModeRow?.value === "amount_threshold" ? "amount_threshold" : "accountant_discretion";
  const canSetDirectorAuthorization =
    stageKey === "finance" &&
    directorAuthMode === "accountant_discretion" &&
    (isAdmin || profile.role === "finance_accountant" || isForwardedAssistant);
  // Any active Accountant/Assistant can pick up Payment Processing — not
  // only whoever is recorded as finance_accountant_id — matching the
  // broadened get_pending_approval_requisition_ids (migration 0042). That
  // RPC/RLS pairing is the actual gate; this is just the UI reflecting it.
  const canEditFinalProcessing =
    stageKey === "payment" &&
    (isAdmin || profile.role === "finance_accountant" || profile.role === "finance_assistant");
  // Second, separate step after marking Paid — the Accountant may
  // legitimately wait on further bank documents before actually posting to
  // QBO and closing it out, so this isn't folded into canEditFinalProcessing
  // above (which only applies while still at approved_for_payment).
  const canMarkPostedAndClosed =
    requisition.status === "paid_posted" &&
    (isAdmin || profile.role === "finance_accountant" || profile.role === "finance_assistant");
  // Reachable at either stage: a requisition may already be at
  // director_review with nobody yet selected (Finance-direct type).
  // Deliberately broader than canManageFinanceGroup — includes the
  // Assistant too, so whoever raised/is handling a Finance-direct
  // requisition can pick authorizers themselves (matches
  // requisition_authorizers_write's RLS, migration 0031).
  const canManageAuthorizers =
    (stageKey === "finance" || stageKey === "director") &&
    (isAdmin || profile.role === "finance_accountant" || profile.role === "finance_assistant");
  const requiresAuthorizationMethodOnApprove = stageKey === "director";

  // Finance can cancel outright up until it's fully authorized; past that
  // point, cancel_requisition() itself only *requests* cancellation and
  // requires the Director's sign-off (decide_cancellation) — see migration
  // 0036. Cancelling once it's reached Payment Processing is hidden by
  // default per Finance's own request — an admin can turn it back on from
  // Settings > Approval Rules (payment_stage_cancellation_enabled).
  const paymentStageCancellationEnabled = paymentCancellationSettingRow?.value === "yes";
  const canCancelRequisition =
    (isAdmin || profile.role === "finance_accountant" || profile.role === "finance_assistant") &&
    !["paid_posted", "posted_and_closed", "cancelled"].includes(requisition.status) &&
    (requisition.status !== "approved_for_payment" || paymentStageCancellationEnabled);
  const canDecideCancellation = (isAdmin || profile.role === "director") && requisition.cancellation_status === "requested";

  // Fund requisitions only: the requester accounts for how the disbursed
  // funds were spent once it's Paid, Finance reviews it, and only then does
  // it reach Posted & Closed. Orthogonal to requisition_type (routing).
  const isFundRequisition = requisition.requisition_kind === "fund";
  const canEditExpenditures = isOwner && isFundRequisition && requisition.status === "paid_posted";
  const showExpenditurePanel =
    isFundRequisition && ["paid_posted", "accounting_review", "posted_and_closed"].includes(requisition.status);
  const canReviewAccounting =
    (isAdmin || profile.role === "finance_accountant" || profile.role === "finance_assistant") &&
    requisition.status === "accounting_review";

  // The requester's own edit-then-submit/resubmit flow — draft, or
  // returned straight back to them (not redirected to a previous stage).
  const canEditDraftFields =
    isOwner && (requisition.status === "draft" || (requisition.status === "returned" && !isReturnedToPreviousStage));
  const canUploadAttachments = canEditDraftFields || canEditFinance || isAdmin;

  // Individual requisitions skip Department Head review entirely, so
  // there's no previous stage to return a Finance decision to.
  const previousStageLabel =
    stageKey === "finance" && requisition.requisition_type === "departmental"
      ? "Department Head"
      : stageKey === "director"
        ? "Finance"
        : null;

  // Field/section visibility toggles (Settings > Form Fields) are a
  // requester-facing convenience only — from department head upward,
  // everyone sees every field (still not editable unless it's their turn),
  // per the current requirements.
  const restrictToRequesterView =
    isOwner && !canDecide && !canEditFinance && !canEditFinalProcessing && !canMarkPostedAndClosed && !isAdmin;
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
          // The requisition's actual status is now set automatically by the
          // workflow engine end-to-end, making this separate manually-set
          // field redundant and confusing at the Payment Processing stage.
          f.field_key !== "payment_status" &&
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

  // Payment-stage supporting documents (post-authorization) get their own
  // section/card, separate from the requester's own supporting documents —
  // reusing the existing final_processing form_section value rather than a
  // new enum, since it already exists for exactly this part of the form.
  const attachments = (attachmentsRaw ?? [])
    .filter((a) => a.section !== "final_processing")
    .map((a) => ({
      id: a.id,
      file_name: a.file_name,
      file_size: a.file_size,
      storage_path: a.storage_path,
      description: a.description,
      uploaderName: nameFor(a.uploaded_by),
    }));
  const paymentAttachments = (attachmentsRaw ?? [])
    .filter((a) => a.section === "final_processing")
    .map((a) => ({
      id: a.id,
      file_name: a.file_name,
      file_size: a.file_size,
      storage_path: a.storage_path,
      description: a.description,
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
    .filter(
      (p) =>
        p.is_active &&
        p.id !== profile.id &&
        (p.role === "finance_accountant" || p.role === "finance_reviewer" || p.role === "finance_assistant"),
    )
    .map((p) => ({ id: p.id, full_name: p.full_name }));

  const authorizerGroup = (authorizersRaw ?? []).map((m) => ({
    id: m.user_id,
    full_name: nameFor(m.user_id),
  }));

  const authorizerPoolIds = new Set((authorizerPoolRaw ?? []).map((m) => m.user_id));
  const authorizerCandidates = (allProfiles ?? [])
    .filter((p) => p.is_active && p.id !== profile.id && (p.role === "director" || authorizerPoolIds.has(p.id)))
    .map((p) => ({ id: p.id, full_name: p.full_name }));

  const authorizationMethodOptions = (authorizationMethodsRaw ?? []).map((m) => ({ value: m.label, label: m.label }));

  const assistantCandidates = (allProfiles ?? [])
    .filter((p) => p.is_active && p.id !== profile.id && p.role === "finance_assistant")
    .map((p) => ({ id: p.id, full_name: p.full_name }));

  const forwardedAssistantId = assistantForwardsRaw?.[0]?.assistant_id ?? null;

  const expenditures = (expendituresRaw ?? []).map((e) => ({
    id: e.id,
    entry_type: e.entry_type,
    description: e.description,
    amount: e.amount,
    storage_path: e.storage_path,
  }));

  // "Finance (direct to authorization)" is only offered to requesters who
  // can actually route straight past both review stages — everyone else
  // still only sees Departmental/Individual.
  const canRaiseFinanceDirect =
    isAdmin || profile.role === "finance_accountant" || profile.role === "finance_assistant";
  const requisitionTypeOptions = canRaiseFinanceDirect
    ? [...REQUISITION_TYPES, FINANCE_DIRECT_REQUISITION_TYPE]
    : undefined;

  return (
    <RequisitionWorkspace
      requisition={requisitionForForm}
      sections={sections}
      attachments={attachments}
      paymentAttachments={paymentAttachments}
      history={history}
      expenditures={expenditures}
      permissions={{
        canEditDraftFields,
        canDecide,
        canEditFinance,
        canManageFinanceGroup,
        canSetDirectorAuthorization,
        canEditFinalProcessing,
        canMarkPostedAndClosed,
        canUploadAttachments,
        canManageAuthorizers,
        requiresAuthorizationMethodOnApprove,
        canCancelRequisition,
        canDecideCancellation,
        canEditExpenditures,
        showExpenditurePanel,
        canReviewAccounting,
        isOwnerDraft: canEditDraftFields,
      }}
      financeGroup={financeGroup}
      financeCandidates={financeCandidates}
      previousStageLabel={previousStageLabel}
      currencyOptions={currencyOptions}
      authorizerGroup={authorizerGroup}
      authorizerCandidates={authorizerCandidates}
      requesterId={requisition.requester_id}
      authorizationMethodOptions={authorizationMethodOptions}
      assistantCandidates={assistantCandidates}
      forwardedAssistantId={forwardedAssistantId}
      requisitionTypeOptions={requisitionTypeOptions}
    />
  );
}
