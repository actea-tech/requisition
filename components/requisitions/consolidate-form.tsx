"use client";

import { useState, useTransition } from "react";
import Link from "next/link";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { createConsolidatedRequisitionAction } from "@/app/(dashboard)/requisitions/consolidate/actions";
import { formatMoney } from "@/lib/analytics";
import { cn } from "@/lib/utils";

export interface ReadyRequisition {
  id: string;
  requisition_number: string | null;
  purpose: string | null;
  amount: number;
  currency: string;
  requesterName: string;
  payees: string[];
  daysWaiting: number;
}

export function ConsolidateForm({ rows }: { rows: ReadyRequisition[] }) {
  const [isPending, startTransition] = useTransition();
  const [selected, setSelected] = useState<string[]>([]);

  // Only requisitions in the same currency can be combined, so work in one
  // currency at a time (the one with the most waiting first).
  const currencies = Array.from(
    rows.reduce((counts, r) => counts.set(r.currency, (counts.get(r.currency) ?? 0) + 1), new Map<string, number>()),
  )
    .sort((a, b) => b[1] - a[1])
    .map(([currency]) => currency);
  const [picked, setPicked] = useState<string | null>(null);
  const currency = picked && currencies.includes(picked) ? picked : (currencies[0] ?? "");

  const visible = rows.filter((r) => r.currency === currency);
  const chosen = visible.filter((r) => selected.includes(r.id));
  const total = chosen.reduce((sum, r) => sum + r.amount, 0);
  const allSelected = visible.length > 0 && chosen.length === visible.length;

  function toggle(id: string, checked: boolean) {
    setSelected((prev) => (checked ? [...prev, id] : prev.filter((s) => s !== id)));
  }

  function toggleAll(checked: boolean) {
    const visibleIds = new Set(visible.map((r) => r.id));
    setSelected((prev) => (checked ? [...prev.filter((id) => !visibleIds.has(id)), ...visible.map((r) => r.id)] : prev.filter((id) => !visibleIds.has(id))));
  }

  function handleCreate() {
    startTransition(async () => {
      const result = await createConsolidatedRequisitionAction(chosen.map((r) => r.id));
      // Success redirects; only an error comes back.
      if (result?.error) toast.error(result.error);
    });
  }

  if (rows.length === 0) {
    return (
      <Card>
        <CardContent className="pt-6 text-sm text-muted-foreground">
          No requisitions are waiting at Payment Processing that can be combined right now.
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Ready to pay</CardTitle>
        <CardDescription>
          Requisitions at Payment Processing that aren&apos;t already combined. Tick two or more.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {currencies.length > 1 ? (
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <span className="text-muted-foreground">Currency:</span>
            {currencies.map((c) => (
              <button
                key={c}
                type="button"
                onClick={() => setPicked(c)}
                className={cn(
                  "rounded-md border px-2.5 py-1 text-xs font-medium transition-colors",
                  c === currency ? "border-primary bg-primary text-primary-foreground" : "text-muted-foreground hover:bg-muted",
                )}
              >
                {c}
              </button>
            ))}
            <span className="text-xs text-muted-foreground">Only one currency can be combined at a time.</span>
          </div>
        ) : null}

        <div className="overflow-x-auto rounded-lg border">
          <table className="w-full text-sm">
            <thead className="bg-muted/40 text-left text-xs text-muted-foreground">
              <tr>
                <th className="w-10 px-3 py-2">
                  <Checkbox
                    aria-label="Select all"
                    checked={allSelected}
                    disabled={isPending}
                    onCheckedChange={(c) => toggleAll(c === true)}
                  />
                </th>
                <th className="px-3 py-2 font-medium">Requisition</th>
                <th className="px-3 py-2 font-medium">Requester</th>
                <th className="px-3 py-2 font-medium">Payees</th>
                <th className="px-3 py-2 text-right font-medium">Waiting</th>
                <th className="px-3 py-2 text-right font-medium">Amount</th>
              </tr>
            </thead>
            <tbody>
              {visible.map((r) => {
                const checked = selected.includes(r.id);
                return (
                  <tr key={r.id} className={cn("border-t", checked && "bg-muted/30")}>
                    <td className="px-3 py-2">
                      <Checkbox
                        aria-label={`Select ${r.requisition_number ?? "requisition"}`}
                        checked={checked}
                        disabled={isPending}
                        onCheckedChange={(c) => toggle(r.id, c === true)}
                      />
                    </td>
                    <td className="px-3 py-2">
                      <Link href={`/requisitions/${r.id}`} className="font-medium underline-offset-4 hover:underline">
                        {r.requisition_number ?? "Pending number"}
                      </Link>
                      {r.purpose ? <div className="max-w-xs truncate text-xs text-muted-foreground">{r.purpose}</div> : null}
                    </td>
                    <td className="px-3 py-2">{r.requesterName}</td>
                    <td className="max-w-xs truncate px-3 py-2 text-muted-foreground">{r.payees.join(", ") || "—"}</td>
                    <td className="px-3 py-2 text-right tabular-nums text-muted-foreground">
                      {r.daysWaiting === 1 ? "1 day" : `${r.daysWaiting} days`}
                    </td>
                    <td className="px-3 py-2 text-right tabular-nums">{formatMoney(r.amount, r.currency)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="text-xs text-muted-foreground">
              {chosen.length === 0 ? "Nothing selected" : `${chosen.length} selected`}
            </div>
            <div className="text-2xl font-semibold tabular-nums">{formatMoney(total, currency)}</div>
          </div>
          <Button disabled={chosen.length < 2 || isPending} onClick={handleCreate}>
            Create consolidated requisition
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
