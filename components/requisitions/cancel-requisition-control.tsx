"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { cancelRequisitionAction } from "@/app/(dashboard)/requisitions/[id]/actions";

export function CancelRequisitionControl({
  requisitionId,
  alreadyAuthorized,
}: {
  requisitionId: string;
  /** True once status is approved_for_payment — cancelling only requests it; the Director must approve. */
  alreadyAuthorized: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [isPending, startTransition] = useTransition();

  function handleConfirm() {
    if (!reason.trim()) {
      toast.error("A reason is required.");
      return;
    }
    setOpen(false);
    startTransition(async () => {
      const result = await cancelRequisitionAction(requisitionId, reason.trim());
      if (result.error) toast.error(result.error);
      else toast.success(alreadyAuthorized ? "Cancellation requested" : "Requisition cancelled");
      setReason("");
    });
  }

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogTrigger render={<Button variant="outline" className="w-full" disabled={isPending} />}>
        Cancel requisition
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Cancel this requisition?</AlertDialogTitle>
          <AlertDialogDescription>
            {alreadyAuthorized
              ? "This requisition is already fully authorized — cancelling now only requests it. The Director must approve the cancellation before it actually takes effect."
              : "This can't be undone."}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <div className="space-y-1.5">
          <Label htmlFor="cancel-reason" className="text-xs">
            Reason
          </Label>
          <Textarea id="cancel-reason" value={reason} onChange={(e) => setReason(e.target.value)} rows={3} />
        </div>
        <AlertDialogFooter>
          <AlertDialogCancel>Back</AlertDialogCancel>
          <AlertDialogAction variant="destructive" disabled={isPending} onClick={handleConfirm}>
            {alreadyAuthorized ? "Request cancellation" : "Cancel requisition"}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
