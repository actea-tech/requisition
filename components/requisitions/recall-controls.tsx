"use client";

import { useState, useTransition } from "react";
import { format } from "date-fns";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import {
  cancelRecalledRequisitionAction,
  decideRecallRequestAction,
  recallRequisitionAction,
  requestRecallAction,
} from "@/app/(dashboard)/requisitions/[id]/actions";

/** A reason-collecting confirm dialog shared by the recall, request and cancel buttons. */
function ReasonDialog({
  trigger,
  title,
  description,
  confirmLabel,
  destructive,
  onConfirm,
}: {
  trigger: string;
  title: string;
  description: string;
  confirmLabel: string;
  destructive?: boolean;
  onConfirm: (reason: string) => Promise<string | null>;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [isPending, startTransition] = useTransition();

  function handleConfirm() {
    if (!reason.trim()) {
      toast.error("A reason is required.");
      return;
    }
    startTransition(async () => {
      const error = await onConfirm(reason.trim());
      if (error) {
        toast.error(error);
        return;
      }
      setOpen(false);
      setReason("");
    });
  }

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogTrigger render={<Button variant="outline" className="w-full" disabled={isPending} />}>
        {trigger}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{title}</AlertDialogTitle>
          <AlertDialogDescription>{description}</AlertDialogDescription>
        </AlertDialogHeader>
        <div className="space-y-1.5">
          <Label htmlFor="recall-reason" className="text-xs">
            Reason (required)
          </Label>
          <Textarea
            id="recall-reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            rows={3}
            maxLength={2000}
            disabled={isPending}
          />
        </div>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={isPending}>Back</AlertDialogCancel>
          {/* Not the usual AlertDialogAction: it would close the dialog before the result is known. */}
          <Button variant={destructive ? "destructive" : "default"} disabled={isPending} onClick={handleConfirm}>
            {confirmLabel}
          </Button>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

/** The requester pulls the requisition back, or - once Finance has acted - asks for that. */
export function RecallControl({ requisitionId, mode }: { requisitionId: string; mode: "recall" | "request" }) {
  return mode === "recall" ? (
    <ReasonDialog
      trigger="Recall requisition"
      title="Recall this requisition?"
      description="It comes back to you as Returned for correction, and whoever it's with is told to stop. Change what you need, then resubmit it (it starts again from the first review) or cancel it."
      confirmLabel="Recall"
      onConfirm={async (reason) => (await recallRequisitionAction(requisitionId, reason)).error}
    />
  ) : (
    <ReasonDialog
      trigger="Request recall"
      title="Ask Finance to recall this requisition?"
      description="Finance has already acted on it, so Finance decides. If they approve, it comes back to you as Returned for correction. If they decline, it carries on as before."
      confirmLabel="Send request"
      onConfirm={async (reason) => (await requestRecallAction(requisitionId, reason)).error}
    />
  );
}

/** After recalling, the requester can cancel instead of resubmitting. */
export function CancelRecalledControl({ requisitionId }: { requisitionId: string }) {
  return (
    <ReasonDialog
      trigger="Cancel requisition"
      title="Cancel this requisition?"
      description="You recalled it, so you can cancel it instead of resubmitting. This can't be undone."
      confirmLabel="Cancel requisition"
      destructive
      onConfirm={async (reason) => (await cancelRecalledRequisitionAction(requisitionId, reason)).error}
    />
  );
}

/** Finance's view of a recall request: approve (it is recalled) or decline (with a reason). */
export function RecallRequestCard({
  requisitionId,
  requesterName,
  reason,
  requestedAt,
  canDecide,
}: {
  requisitionId: string;
  requesterName: string;
  reason: string | null;
  requestedAt: string | null;
  canDecide: boolean;
}) {
  const [isPending, startTransition] = useTransition();
  const [comment, setComment] = useState("");

  function decide(approve: boolean) {
    if (!approve && !comment.trim()) {
      toast.error("A reason is required to decline.");
      return;
    }
    startTransition(async () => {
      const result = await decideRecallRequestAction(requisitionId, approve, comment.trim() || null);
      if (result.error) toast.error(result.error);
      else {
        toast.success(approve ? "Recall approved" : "Recall request declined");
        setComment("");
      }
    });
  }

  return (
    <Card className="border-primary/40 bg-primary/5">
      <CardContent className="space-y-2 pt-6 text-sm">
        <p className="font-medium">Recall requested</p>
        <p className="text-muted-foreground">
          {requesterName} asks to recall this requisition
          {requestedAt ? ` (${format(new Date(requestedAt), "d MMM yyyy, HH:mm")})` : ""}.
        </p>
        {reason ? <blockquote className="border-l-2 pl-3 text-muted-foreground">{reason}</blockquote> : null}
        {canDecide ? (
          <div className="space-y-2 pt-1">
            <Label htmlFor="recall-decision-comment" className="text-xs">
              Comment (required to decline)
            </Label>
            <Textarea
              id="recall-decision-comment"
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              rows={2}
              maxLength={2000}
              disabled={isPending}
            />
            <div className="flex gap-2">
              <Button size="sm" disabled={isPending} onClick={() => decide(true)}>
                Approve recall
              </Button>
              <Button size="sm" variant="outline" disabled={isPending} onClick={() => decide(false)}>
                Decline
              </Button>
            </div>
          </div>
        ) : (
          <p className="text-xs text-muted-foreground">Waiting for Finance to decide.</p>
        )}
      </CardContent>
    </Card>
  );
}
