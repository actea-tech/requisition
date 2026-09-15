"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { getAttachmentSignedUrl, reviewRequisitionAccountingAction } from "@/app/(dashboard)/requisitions/[id]/actions";
import type { ExpenditureRow } from "@/components/requisitions/expenditure-accounting-panel";

export function AccountingReviewPanel({
  requisitionId,
  amount,
  currency,
  expenditures,
}: {
  requisitionId: string;
  amount: number | null;
  currency: string;
  expenditures: ExpenditureRow[];
}) {
  const [isPending, startTransition] = useTransition();
  const [comments, setComments] = useState("");
  const [shortfallNote, setShortfallNote] = useState("");

  const disbursed = amount ?? 0;
  const totalAccounted = expenditures.reduce((sum, e) => sum + e.amount, 0);
  const variance = disbursed - totalAccounted;
  const isOverspent = variance < 0;

  function handleReview(approve: boolean) {
    if (!approve && !comments.trim()) {
      toast.error("A comment is required when returning it for correction.");
      return;
    }
    startTransition(async () => {
      const result = await reviewRequisitionAccountingAction(
        requisitionId,
        approve,
        comments.trim() || null,
        isOverspent ? shortfallNote.trim() || null : null,
      );
      if (result.error) toast.error(result.error);
      else toast.success(approve ? "Accounting approved — requisition closed" : "Sent back for correction");
    });
  }

  async function handleView(path: string) {
    const url = await getAttachmentSignedUrl(path);
    if (url) window.open(url, "_blank", "noopener,noreferrer");
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Review accounting</CardTitle>
        <CardDescription>The requester has submitted their expenditure accounting for review.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <ul className="space-y-1.5">
          {expenditures.map((e) => (
            <li key={e.id} className="flex items-center justify-between gap-2 rounded-md border px-3 py-2 text-sm">
              <div className="min-w-0">
                <span className="text-xs font-medium text-muted-foreground">
                  {e.entry_type === "balance_banked" ? "Balance banked" : "Expense"}
                </span>
                <p className="truncate">{e.description}</p>
              </div>
              <div className="flex shrink-0 items-center gap-1">
                <span className="text-xs text-muted-foreground">
                  {currency} {e.amount.toLocaleString()}
                </span>
                {e.storage_path ? (
                  <Button variant="ghost" size="icon-sm" onClick={() => handleView(e.storage_path!)}>
                    <Download className="size-4" />
                  </Button>
                ) : null}
              </div>
            </li>
          ))}
        </ul>

        <div className="space-y-1 rounded-md bg-muted/50 px-3 py-2 text-sm">
          <div className="flex justify-between text-muted-foreground">
            <span>Disbursed</span>
            <span>
              {currency} {disbursed.toLocaleString()}
            </span>
          </div>
          <div className="flex justify-between text-muted-foreground">
            <span>Accounted for</span>
            <span>
              {currency} {totalAccounted.toLocaleString()}
            </span>
          </div>
          <div className="flex justify-between font-medium">
            <span>{isOverspent ? "Overspent by" : "Remaining"}</span>
            <span>
              {currency} {Math.abs(variance).toLocaleString()}
            </span>
          </div>
        </div>

        {isOverspent ? (
          <Textarea
            placeholder="How will the overspend be recovered? (e.g. deduct from October payroll) — optional, informational only"
            value={shortfallNote}
            onChange={(e) => setShortfallNote(e.target.value)}
            disabled={isPending}
            rows={2}
            className="text-sm"
          />
        ) : null}

        <Textarea
          placeholder="Comments (required if returning for correction)"
          value={comments}
          onChange={(e) => setComments(e.target.value)}
          disabled={isPending}
          rows={2}
          className="text-sm"
        />

        <div className="space-y-2">
          <Button className="w-full" disabled={isPending} onClick={() => handleReview(true)}>
            Approve &amp; close
          </Button>
          <Button variant="outline" className="w-full" disabled={isPending} onClick={() => handleReview(false)}>
            Return for correction
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
