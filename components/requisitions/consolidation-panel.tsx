"use client";

import { useState, useTransition } from "react";
import Link from "next/link";
import { toast } from "sonner";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { setConsolidationMembersAction } from "@/app/(dashboard)/requisitions/[id]/actions";
import { formatMoney } from "@/lib/analytics";
import { STATUS_LABELS } from "@/lib/requisition-status";
import type { RequisitionStatus } from "@/lib/supabase/database.types";

export interface ConsolidationMember {
  id: string;
  requisition_number: string | null;
  purpose: string | null;
  requester_name: string | null;
  amount: number;
  currency: string;
  status: string;
  payees: string[];
}

export interface ConsolidationCandidate {
  id: string;
  requisition_number: string | null;
  requester_name: string | null;
  amount: number;
}

export function ConsolidationPanel({
  requisitionId,
  members,
  candidates,
  currency,
  editable,
  canOpenMembers,
}: {
  requisitionId: string;
  members: ConsolidationMember[];
  /** Other requisitions at Payment Processing, in the same currency, not already combined. */
  candidates: ConsolidationCandidate[];
  currency: string;
  /** Still a draft (or returned to Finance): the list can change. */
  editable: boolean;
  /** The viewer can open the individual requisitions (Finance, Director, admins). */
  canOpenMembers: boolean;
}) {
  const [isPending, startTransition] = useTransition();
  const [picked, setPicked] = useState("");
  const total = members.reduce((sum, m) => sum + m.amount, 0);
  const memberIds = new Set(members.map((m) => m.id));
  const available = candidates.filter((c) => !memberIds.has(c.id));
  const label = (c: ConsolidationCandidate) =>
    `${c.requisition_number ?? "Pending number"} · ${c.requester_name ?? "Unknown"} · ${formatMoney(c.amount, currency)}`;

  function save(nextIds: string[]) {
    startTransition(async () => {
      const result = await setConsolidationMembersAction(requisitionId, nextIds);
      if (result.error) toast.error(result.error);
      setPicked("");
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Requisitions in this payment</CardTitle>
        <CardDescription>
          {editable
            ? "These requisitions are already approved and are paid together as one. The total and the payees below are worked out from them. Once you submit, the list is fixed."
            : "These requisitions are paid together as one. Paying this pays all of them, and closing it closes them."}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {members.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nothing is in this payment.</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border">
            <table className="w-full text-sm">
              <thead className="bg-muted/40 text-left text-xs text-muted-foreground">
                <tr>
                  <th className="px-3 py-2 font-medium">Requisition</th>
                  <th className="px-3 py-2 font-medium">Requester</th>
                  <th className="px-3 py-2 font-medium">Payees</th>
                  <th className="px-3 py-2 text-right font-medium">Amount</th>
                  {editable ? <th className="w-10 px-3 py-2" /> : <th className="px-3 py-2 font-medium">Status</th>}
                </tr>
              </thead>
              <tbody>
                {members.map((m) => (
                  <tr key={m.id} className="border-t">
                    <td className="px-3 py-2">
                      {canOpenMembers ? (
                        <Link href={`/requisitions/${m.id}`} className="font-medium underline-offset-4 hover:underline">
                          {m.requisition_number ?? "Pending number"}
                        </Link>
                      ) : (
                        <span className="font-medium">{m.requisition_number ?? "Pending number"}</span>
                      )}
                      {m.purpose ? <div className="max-w-xs truncate text-xs text-muted-foreground">{m.purpose}</div> : null}
                    </td>
                    <td className="px-3 py-2">{m.requester_name ?? "—"}</td>
                    <td className="max-w-xs truncate px-3 py-2 text-muted-foreground">{m.payees.join(", ") || "—"}</td>
                    <td className="px-3 py-2 text-right tabular-nums">{formatMoney(m.amount, m.currency)}</td>
                    {editable ? (
                      <td className="px-3 py-2">
                        <Button
                          variant="ghost"
                          size="icon-sm"
                          aria-label={`Remove ${m.requisition_number ?? "requisition"}`}
                          disabled={isPending || members.length <= 2}
                          title={members.length <= 2 ? "At least 2 requisitions are needed" : undefined}
                          onClick={() => save(members.filter((x) => x.id !== m.id).map((x) => x.id))}
                        >
                          <Trash2 className="size-4" />
                        </Button>
                      </td>
                    ) : (
                      <td className="px-3 py-2 text-muted-foreground">
                        {STATUS_LABELS[m.status as RequisitionStatus] ?? m.status}
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr className="border-t bg-muted/30 font-medium">
                  <td className="px-3 py-2" colSpan={3}>
                    Total to pay ({members.length} requisitions)
                  </td>
                  <td className="px-3 py-2 text-right tabular-nums">{formatMoney(total, currency)}</td>
                  <td />
                </tr>
              </tfoot>
            </table>
          </div>
        )}

        {editable ? (
          available.length === 0 ? (
            <p className="text-xs text-muted-foreground">No other {currency} requisitions are ready to add.</p>
          ) : (
            <div className="flex gap-2">
              <Select
                value={picked}
                onValueChange={(v) => setPicked(v ?? "")}
                disabled={isPending}
                items={Object.fromEntries(available.map((c) => [c.id, label(c)]))}
              >
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Add another requisition…" />
                </SelectTrigger>
                <SelectContent>
                  {available.map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {label(c)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Button
                variant="outline"
                disabled={!picked || isPending}
                onClick={() => save([...members.map((m) => m.id), picked])}
              >
                Add
              </Button>
            </div>
          )
        ) : null}
      </CardContent>
    </Card>
  );
}
