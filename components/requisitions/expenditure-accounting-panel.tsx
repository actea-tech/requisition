"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Download, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  deleteExpenditure,
  getAttachmentSignedUrl,
  submitRequisitionAccountingAction,
} from "@/app/(dashboard)/requisitions/[id]/actions";

export interface ExpenditureRow {
  id: string;
  entry_type: "expense" | "balance_banked";
  description: string;
  amount: number;
  storage_path: string | null;
}

export function ExpenditureAccountingPanel({
  requisitionId,
  amount,
  currency,
  expenditures,
  canEdit,
  canSubmit,
}: {
  requisitionId: string;
  amount: number | null;
  currency: string;
  expenditures: ExpenditureRow[];
  /** The requester, while the requisition is at paid_posted. */
  canEdit: boolean;
  /** canEdit, plus at least one expense line already added. */
  canSubmit: boolean;
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [description, setDescription] = useState("");
  const [amountInput, setAmountInput] = useState("");
  const [entryType, setEntryType] = useState<"expense" | "balance_banked">("expense");
  const [isUploading, setIsUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const disbursed = amount ?? 0;
  const totalAccounted = expenditures.reduce((sum, e) => sum + e.amount, 0);
  const variance = disbursed - totalAccounted;
  const hasExpenseLine = expenditures.some((e) => e.entry_type === "expense");

  async function handleAddLine() {
    const amt = Number(amountInput);
    if (!description.trim() || !amt || amt <= 0) {
      setError("A description and a positive amount are required.");
      return;
    }
    setError(null);
    setIsUploading(true);

    const formData = new FormData();
    formData.set("requisitionId", requisitionId);
    formData.set("description", description.trim());
    formData.set("amount", String(amt));
    formData.set("entryType", entryType);
    const file = fileInputRef.current?.files?.[0];
    if (file) formData.set("file", file);

    try {
      const res = await fetch("/api/expenditures", { method: "POST", body: formData });
      const json = await res.json();
      if (!res.ok) {
        setError(json.error ?? "Failed to add line");
      } else {
        setDescription("");
        setAmountInput("");
        setEntryType("expense");
        if (fileInputRef.current) fileInputRef.current.value = "";
        router.refresh();
      }
    } catch {
      setError("Failed to add line — check your connection.");
    } finally {
      setIsUploading(false);
    }
  }

  function handleSubmitAccounting() {
    startTransition(async () => {
      const result = await submitRequisitionAccountingAction(requisitionId);
      if (result.error) toast.error(result.error);
      else toast.success("Accounting submitted for review");
    });
  }

  async function handleView(path: string) {
    const url = await getAttachmentSignedUrl(path);
    if (url) window.open(url, "_blank", "noopener,noreferrer");
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Expenditure accounting</CardTitle>
        <CardDescription>
          Account for how the {currency} {disbursed.toLocaleString()} disbursed was spent — add each expense
          with its receipt, and a balance-banked line (with its deposit slip) if you&apos;re returning unused
          funds.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {expenditures.length === 0 ? (
          <p className="text-sm text-muted-foreground">No expenditure lines yet.</p>
        ) : (
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
                  {canEdit ? (
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      disabled={isPending}
                      onClick={() => startTransition(() => deleteExpenditure(e.id, e.storage_path, requisitionId))}
                    >
                      <Trash2 className="size-4" />
                    </Button>
                  ) : null}
                </div>
              </li>
            ))}
          </ul>
        )}

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
            <span>{variance >= 0 ? "Remaining to account for" : "Overspent by"}</span>
            <span>
              {currency} {Math.abs(variance).toLocaleString()}
            </span>
          </div>
        </div>

        {canEdit ? (
          <div className="space-y-2 border-t pt-3">
            <Select
              value={entryType}
              onValueChange={(v) => setEntryType((v ?? "expense") as "expense" | "balance_banked")}
              disabled={isUploading}
              items={{ expense: "Expense", balance_banked: "Balance banked (returning unused funds)" }}
            >
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="expense">Expense</SelectItem>
                <SelectItem value="balance_banked">Balance banked (returning unused funds)</SelectItem>
              </SelectContent>
            </Select>
            <Textarea
              placeholder="Description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              disabled={isUploading}
              rows={2}
              className="text-sm"
            />
            <Input
              type="number"
              placeholder="Amount"
              value={amountInput}
              onChange={(e) => setAmountInput(e.target.value)}
              disabled={isUploading}
            />
            <input
              ref={fileInputRef}
              type="file"
              disabled={isUploading}
              className="text-sm file:mr-3 file:rounded-md file:border file:bg-secondary file:px-3 file:py-1.5 file:text-xs file:font-medium"
            />
            {error ? <p className="text-sm text-destructive">{error}</p> : null}
            <Button variant="outline" className="w-full" disabled={isUploading} onClick={handleAddLine}>
              {isUploading ? "Adding…" : "Add line"}
            </Button>
            <Button className="w-full" disabled={isPending || !canSubmit || !hasExpenseLine} onClick={handleSubmitAccounting}>
              Submit accounting
            </Button>
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}
