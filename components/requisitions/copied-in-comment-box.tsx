"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { addRequisitionCommentAction } from "@/app/(dashboard)/requisitions/[id]/actions";

export function CopiedInCommentBox({ requisitionId }: { requisitionId: string }) {
  const [isPending, startTransition] = useTransition();
  const [comment, setComment] = useState("");

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Add a comment</CardTitle>
        <CardDescription>
          You&apos;re copied in on this requisition, so you can read it and comment — you can&apos;t approve or change
          it. Your comment goes into the audit trail with your name, and the requester and whoever it&apos;s with now
          are emailed.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <Textarea
          value={comment}
          onChange={(e) => setComment(e.target.value)}
          placeholder="Write your comment…"
          rows={3}
          maxLength={2000}
          disabled={isPending}
        />
        <div className="flex justify-end">
          <Button
            disabled={!comment.trim() || isPending}
            onClick={() =>
              startTransition(async () => {
                const result = await addRequisitionCommentAction(requisitionId, comment);
                if (result.error) {
                  toast.error(result.error);
                  return;
                }
                toast.success("Comment added");
                setComment("");
              })
            }
          >
            Post comment
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
