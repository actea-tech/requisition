"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { DynamicField, type FieldMeta } from "@/components/requisitions/dynamic-field";
import { StatusStepper } from "@/components/requisitions/status-stepper";
import { StatusBadge } from "@/components/requisitions/status-badge";
import { ApprovalHistory, type HistoryEntry } from "@/components/requisitions/approval-history";
import { AttachmentsPanel, type AttachmentRow } from "@/components/requisitions/attachments-panel";
import { FinanceGroupPanel } from "@/components/requisitions/finance-group-panel";
import { AuthorizerGroupPanel } from "@/components/requisitions/authorizer-group-panel";
import { AssistantForwardControl } from "@/components/requisitions/assistant-forward-control";
import { CancelRequisitionControl } from "@/components/requisitions/cancel-requisition-control";
import {
  clearRequisitionAuthorizers,
  completePaymentAction,
  decideCancellationAction,
  deleteDraftRequisition,
  markPostedAndClosedAction,
  recordDecisionAction,
  resubmitRequisitionAction,
  setRequiresDirectorAuthorizationAction,
  submitRequisitionAction,
  updateRequisitionFields,
} from "@/app/(dashboard)/requisitions/[id]/actions";
import type { RequisitionStatus } from "@/lib/supabase/database.types";

export interface SectionSpec {
  key: string;
  label: string;
  fields: FieldMeta[];
  editable: boolean;
}

export interface RequisitionRowForForm {
  id: string;
  requisition_number: string | null;
  status: RequisitionStatus;
  returned_from_stage: RequisitionStatus | null;
  return_reason: string | null;
  cancellation_status: "requested" | "approved" | "denied" | null;
  cancellation_reason: string | null;
  amount: number | null;
  currency: string;
  requesterName: string;
  departmentName: string;
  submitted_at: string | null;
  [key: string]: unknown;
}

export function RequisitionWorkspace({
  requisition,
  sections,
  attachments,
  paymentAttachments,
  history,
  permissions,
  financeGroup,
  financeCandidates,
  previousStageLabel,
  currencyOptions,
  authorizerGroup,
  authorizerCandidates,
  requesterId,
  authorizationMethodOptions,
  assistantCandidates,
  forwardedAssistantId,
  requisitionTypeOptions,
}: {
  requisition: RequisitionRowForForm;
  sections: SectionSpec[];
  attachments: AttachmentRow[];
  paymentAttachments: AttachmentRow[];
  history: HistoryEntry[];
  currencyOptions: { value: string; label: string }[];
  permissions: {
    canEditDraftFields: boolean;
    canDecide: boolean;
    canEditFinance: boolean;
    canManageFinanceGroup: boolean;
    canSetDirectorAuthorization: boolean;
    canEditFinalProcessing: boolean;
    canMarkPostedAndClosed: boolean;
    canUploadAttachments: boolean;
    canManageAuthorizers: boolean;
    requiresAuthorizationMethodOnApprove: boolean;
    canCancelRequisition: boolean;
    canDecideCancellation: boolean;
    isOwnerDraft: boolean;
  };
  financeGroup: { id: string; full_name: string }[];
  financeCandidates: { id: string; full_name: string }[];
  previousStageLabel: string | null;
  authorizerGroup: { id: string; full_name: string }[];
  authorizerCandidates: { id: string; full_name: string }[];
  requesterId: string;
  authorizationMethodOptions: { value: string; label: string }[];
  assistantCandidates: { id: string; full_name: string }[];
  forwardedAssistantId: string | null;
  /** Role-filtered options for the Requisition type field; undefined falls back to the static departmental/individual list. */
  requisitionTypeOptions?: { value: string; label: string }[];
}) {
  const router = useRouter();
  const [returnTo, setReturnTo] = useState<"requester" | "previous_stage">("requester");
  const [requiresReapproval, setRequiresReapproval] = useState(true);
  const [requiresDirectorAuth, setRequiresDirectorAuth] = useState<"yes" | "no">(
    requisition.requires_director_authorization === "no" ? "no" : "yes",
  );
  const [values, setValues] = useState<Record<string, string>>(() => {
    const initial: Record<string, string> = {};
    for (const section of sections) {
      for (const field of section.fields) {
        const raw = requisition[field.field_key];
        initial[field.field_key] = raw === null || raw === undefined ? "" : String(raw);
      }
    }
    return initial;
  });
  const [comment, setComment] = useState("");
  const [authorizationMethod, setAuthorizationMethod] = useState("");
  const [isPending, startTransition] = useTransition();

  function setField(key: string, value: string) {
    setValues((prev) => ({ ...prev, [key]: value }));
  }

  function handleSave() {
    startTransition(async () => {
      const result = await updateRequisitionFields(requisition.id, values);
      if (result.error) toast.error(result.error);
      else toast.success("Changes saved");
    });
  }

  function handleSubmit() {
    startTransition(async () => {
      await updateRequisitionFields(requisition.id, values);
      const result = await submitRequisitionAction(requisition.id);
      if (result.error) toast.error(result.error);
      else toast.success("Requisition submitted for department review");
    });
  }

  function handleResubmit() {
    startTransition(async () => {
      await updateRequisitionFields(requisition.id, values);
      const result = await resubmitRequisitionAction(requisition.id);
      if (result.error) toast.error(result.error);
      else toast.success("Requisition resubmitted");
    });
  }

  function handleDelete() {
    if (!confirm("Delete this draft? This can't be undone.")) return;
    startTransition(async () => {
      await deleteDraftRequisition(requisition.id);
      router.push("/requisitions");
    });
  }

  function handleDecision(decision: "approved" | "returned" | "rejected") {
    if (decision !== "approved" && !comment.trim()) {
      toast.error("A comment is required when returning or rejecting.");
      return;
    }
    if (decision === "approved" && permissions.requiresAuthorizationMethodOnApprove && !authorizationMethod) {
      toast.error("Select how you authorized this before approving.");
      return;
    }
    if (decision === "approved" && permissions.canEditFinance && requiresDirectorAuth === "yes" && authorizerGroup.length === 0) {
      toast.error("Add at least one authorizer before approving.");
      return;
    }
    startTransition(async () => {
      if (permissions.canEditFinance) {
        await updateRequisitionFields(requisition.id, values);
      }
      // Deciding on a requisition returned to a previous stage (not the
      // requester): it's sitting at status='returned', which
      // record_approval_action rejects outright — move it back into the
      // active review status first so the decision applies directly,
      // with no separate "Resubmit" step for the user.
      if (requisition.status === "returned") {
        await resubmitRequisitionAction(requisition.id);
      }
      const result = await recordDecisionAction(
        requisition.id,
        decision,
        comment.trim() || null,
        decision === "returned" ? returnTo : "requester",
        decision === "returned" ? requiresReapproval : true,
        decision === "approved" ? authorizationMethod || null : null,
      );
      if (result.error) toast.error(result.error);
      else {
        toast.success("Decision recorded");
        setComment("");
        router.push("/approvals");
      }
    });
  }

  function handleSetRequiresDirectorAuth(value: "yes" | "no") {
    setRequiresDirectorAuth(value);
    startTransition(async () => {
      const result = await setRequiresDirectorAuthorizationAction(requisition.id, value);
      if (result.error) toast.error(result.error);
      if (value === "no" && authorizerGroup.length > 0) {
        await clearRequisitionAuthorizers(requisition.id);
      }
    });
  }

  function handleCompletePayment() {
    startTransition(async () => {
      await updateRequisitionFields(requisition.id, values);
      const result = await completePaymentAction(requisition.id, comment.trim() || null);
      if (result.error) toast.error(result.error);
      else toast.success("Requisition marked as Paid");
    });
  }

  function handleMarkPostedAndClosed() {
    startTransition(async () => {
      const result = await markPostedAndClosedAction(requisition.id, comment.trim() || null);
      if (result.error) toast.error(result.error);
      else toast.success("Requisition posted and closed");
    });
  }

  function handleDecideCancellation(approve: boolean) {
    startTransition(async () => {
      const result = await decideCancellationAction(requisition.id, approve);
      if (result.error) toast.error(result.error);
      else toast.success(approve ? "Cancellation approved" : "Cancellation denied");
    });
  }

  return (
    <div className="grid gap-6 print:block lg:grid-cols-[1fr_320px]">
      <div className="space-y-6">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            <h1 className="text-2xl font-semibold">
              {requisition.requisition_number ?? (requisition.status === "draft" ? "Draft requisition" : "Pending number")}
            </h1>
            <p className="text-sm text-muted-foreground">
              {requisition.requesterName} &middot; {requisition.departmentName}
            </p>
          </div>
          <div className="flex items-center gap-2 print:hidden">
            <StatusBadge status={requisition.status} />
            <Button variant="outline" size="sm" onClick={() => window.print()}>
              Print record
            </Button>
            {requisition.status === "posted_and_closed" || requisition.status === "rejected" ? (
              <>
                <Button
                  render={<a href={`/api/requisitions/${requisition.id}/export?format=csv`} />}
                  nativeButton={false}
                  variant="outline"
                  size="sm"
                >
                  Export CSV
                </Button>
                <Button
                  render={<a href={`/api/requisitions/${requisition.id}/export?format=xlsx`} />}
                  nativeButton={false}
                  variant="outline"
                  size="sm"
                >
                  Export Excel
                </Button>
                <Button render={<a href={`/api/requisitions/${requisition.id}/pdf`} />} nativeButton={false} size="sm">
                  Download PDF
                </Button>
              </>
            ) : null}
          </div>
        </div>

        {requisition.status === "returned" && requisition.return_reason ? (
          <Card className="border-destructive/40 bg-destructive/5">
            <CardContent className="pt-6 text-sm">
              <p className="font-medium text-destructive">Returned for correction</p>
              <p className="mt-1 text-muted-foreground">{requisition.return_reason}</p>
            </CardContent>
          </Card>
        ) : null}

        {requisition.cancellation_status === "requested" ? (
          <Card className="border-destructive/40 bg-destructive/5">
            <CardContent className="space-y-2 pt-6 text-sm">
              <p className="font-medium text-destructive">Cancellation requested</p>
              <p className="text-muted-foreground">{requisition.cancellation_reason}</p>
              {permissions.canDecideCancellation ? (
                <div className="flex gap-2 pt-1">
                  <Button
                    size="sm"
                    variant="destructive"
                    disabled={isPending}
                    onClick={() => handleDecideCancellation(true)}
                  >
                    Approve cancellation
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={isPending}
                    onClick={() => handleDecideCancellation(false)}
                  >
                    Deny
                  </Button>
                </div>
              ) : null}
            </CardContent>
          </Card>
        ) : null}

        {sections.map((section) =>
          section.fields.length === 0 ? null : (
            <Card key={section.key}>
              <CardHeader>
                <CardTitle className="text-base">{section.label}</CardTitle>
              </CardHeader>
              <CardContent className="grid gap-4 sm:grid-cols-2">
                {section.fields.map((field) => (
                  <div key={field.field_key} className={field.field_key === "purpose" ? "sm:col-span-2" : ""}>
                    <DynamicField
                      field={field}
                      value={values[field.field_key] ?? ""}
                      onChange={(v) => setField(field.field_key, v)}
                      disabled={!section.editable || isPending}
                      optionsOverride={
                        field.field_key === "currency"
                          ? currencyOptions
                          : field.field_key === "requisition_type"
                            ? requisitionTypeOptions
                            : undefined
                      }
                    />
                  </div>
                ))}
              </CardContent>
            </Card>
          ),
        )}

        <AttachmentsPanel
          requisitionId={requisition.id}
          attachments={attachments}
          canUpload={permissions.canUploadAttachments}
          canDelete={permissions.isOwnerDraft}
        />

        {permissions.canEditFinalProcessing || paymentAttachments.length > 0 ? (
          <AttachmentsPanel
            requisitionId={requisition.id}
            attachments={paymentAttachments}
            canUpload={permissions.canEditFinalProcessing}
            canDelete={permissions.canEditFinalProcessing}
            title="Payment processing documents"
            section="final_processing"
            withDescription
          />
        ) : null}

        {permissions.canManageFinanceGroup ? (
          <FinanceGroupPanel requisitionId={requisition.id} members={financeGroup} candidates={financeCandidates} />
        ) : null}

        {permissions.canManageFinanceGroup ? (
          <AssistantForwardControl
            requisitionId={requisition.id}
            candidates={assistantCandidates}
            forwardedAssistantId={forwardedAssistantId}
          />
        ) : null}

        {permissions.canManageAuthorizers ? (
          <AuthorizerGroupPanel
            requisitionId={requisition.id}
            members={authorizerGroup}
            candidates={authorizerCandidates}
            requesterId={requesterId}
            disabled={requiresDirectorAuth === "no"}
          />
        ) : null}

        <ApprovalHistory entries={history} />
      </div>

      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Requisition status</CardTitle>
          </CardHeader>
          <CardContent>
            <StatusStepper status={requisition.status} returnedFromStage={requisition.returned_from_stage} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Summary</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-muted-foreground">Amount</span>
              <span className="font-medium">
                {requisition.amount ? `${requisition.currency} ${requisition.amount.toLocaleString()}` : "—"}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Department</span>
              <span className="font-medium">{requisition.departmentName}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Submitted</span>
              <span className="font-medium">
                {requisition.submitted_at ? new Date(requisition.submitted_at).toLocaleDateString() : "Not yet"}
              </span>
            </div>
          </CardContent>
        </Card>

        <Card className="print:hidden">
          <CardHeader>
            <CardTitle className="text-base">Actions</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {permissions.canEditDraftFields ? (
              <>
                <Button className="w-full" variant="outline" disabled={isPending} onClick={handleSave}>
                  Save changes
                </Button>
                <Button
                  className="w-full"
                  disabled={isPending}
                  onClick={requisition.status === "returned" ? handleResubmit : handleSubmit}
                >
                  {requisition.status === "returned" ? "Resubmit" : "Submit for approval"}
                </Button>
                {requisition.status === "draft" ? (
                  <Button className="w-full" variant="ghost" disabled={isPending} onClick={handleDelete}>
                    Delete draft
                  </Button>
                ) : null}
              </>
            ) : null}

            {permissions.canSetDirectorAuthorization ? (
              <div className="space-y-2 rounded-md border p-2.5">
                <Label className="text-xs">Requires authorization?</Label>
                <Select
                  value={requiresDirectorAuth}
                  onValueChange={(v) => handleSetRequiresDirectorAuth((v ?? "yes") as "yes" | "no")}
                  disabled={isPending}
                  items={{ yes: "Yes — requires authorization", no: "No — clear directly for payment" }}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="yes">Yes — requires authorization</SelectItem>
                    <SelectItem value="no">No — clear directly for payment</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            ) : null}

            {permissions.canDecide ? (
              <div className="space-y-2">
                <Label htmlFor="decision-comment">Comment</Label>
                <Textarea
                  id="decision-comment"
                  value={comment}
                  onChange={(e) => setComment(e.target.value)}
                  placeholder="Required when returning or rejecting"
                  rows={3}
                />
                {permissions.canEditFinance ? (
                  <Button className="w-full" variant="outline" disabled={isPending} onClick={handleSave}>
                    Save Finance fields
                  </Button>
                ) : null}

                {permissions.requiresAuthorizationMethodOnApprove ? (
                  <div className="space-y-1.5">
                    <Label className="text-xs">How did you authorize this?</Label>
                    <Select
                      value={authorizationMethod || undefined}
                      onValueChange={(v) => setAuthorizationMethod(v ?? "")}
                      disabled={isPending}
                      items={Object.fromEntries(authorizationMethodOptions.map((o) => [o.value, o.label]))}
                    >
                      <SelectTrigger className="w-full">
                        <SelectValue placeholder="Select…" />
                      </SelectTrigger>
                      <SelectContent>
                        {authorizationMethodOptions.map((o) => (
                          <SelectItem key={o.value} value={o.value}>
                            {o.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                ) : null}

                <Button
                  className="w-full"
                  disabled={
                    isPending ||
                    (permissions.requiresAuthorizationMethodOnApprove && !authorizationMethod) ||
                    (permissions.canEditFinance && requiresDirectorAuth === "yes" && authorizerGroup.length === 0)
                  }
                  onClick={() => handleDecision("approved")}
                >
                  Approve
                </Button>
                {permissions.canEditFinance && requiresDirectorAuth === "yes" && authorizerGroup.length === 0 ? (
                  <p className="text-xs text-muted-foreground">Add at least one authorizer before approving.</p>
                ) : null}

                {previousStageLabel ? (
                  <div className="space-y-2 rounded-md border p-2.5">
                    <Label className="text-xs">If returned, send to</Label>
                    <Select
                      value={returnTo}
                      onValueChange={(v) => setReturnTo((v ?? "requester") as typeof returnTo)}
                      items={{ requester: "Requester", previous_stage: previousStageLabel }}
                    >
                      <SelectTrigger className="w-full">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="requester">Requester</SelectItem>
                        <SelectItem value="previous_stage">{previousStageLabel}</SelectItem>
                      </SelectContent>
                    </Select>
                    {returnTo === "requester" ? (
                      <label className="flex items-center gap-2 text-xs text-muted-foreground">
                        <Checkbox
                          checked={requiresReapproval}
                          onCheckedChange={(c) => setRequiresReapproval(c === true)}
                        />
                        Requires re-approval from earlier stages
                      </label>
                    ) : null}
                  </div>
                ) : null}

                <Button
                  className="w-full"
                  variant="outline"
                  disabled={isPending}
                  onClick={() => handleDecision("returned")}
                >
                  Return for correction
                </Button>
                <Button
                  className="w-full"
                  variant="destructive"
                  disabled={isPending}
                  onClick={() => handleDecision("rejected")}
                >
                  Reject
                </Button>
              </div>
            ) : null}

            {permissions.canEditFinalProcessing ? (
              <div className="space-y-2">
                <Button className="w-full" variant="outline" disabled={isPending} onClick={handleSave}>
                  Save payment details
                </Button>
                <Button className="w-full" disabled={isPending} onClick={handleCompletePayment}>
                  Mark Paid
                </Button>
              </div>
            ) : null}

            {permissions.canMarkPostedAndClosed ? (
              <Button className="w-full" disabled={isPending} onClick={handleMarkPostedAndClosed}>
                Mark Posted &amp; Closed
              </Button>
            ) : null}

            {permissions.canCancelRequisition ? (
              <CancelRequisitionControl
                requisitionId={requisition.id}
                alreadyAuthorized={requisition.status === "approved_for_payment"}
              />
            ) : null}

            {!permissions.canEditDraftFields &&
            !permissions.canDecide &&
            !permissions.canSetDirectorAuthorization &&
            !permissions.canEditFinalProcessing &&
            !permissions.canMarkPostedAndClosed &&
            !permissions.canCancelRequisition ? (
              <p className="text-sm text-muted-foreground">No action needed from you right now.</p>
            ) : null}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
