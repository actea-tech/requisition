"use client";

import { useState, useTransition } from "react";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  deleteFinanceAssistantThreshold,
  upsertFinanceAssistantThreshold,
} from "@/app/(dashboard)/settings/approval-rules/actions";

export function FinanceAssistantThresholdCard({
  thresholds,
  currencyOptions,
}: {
  thresholds: { currency: string; threshold_amount: number }[];
  currencyOptions: { value: string; label: string }[];
}) {
  const [isPending, startTransition] = useTransition();
  const [newCurrency, setNewCurrency] = useState("");
  const [newAmount, setNewAmount] = useState("");

  function handleAddThreshold() {
    const amount = Number(newAmount);
    if (!newCurrency || !amount) return;
    startTransition(async () => {
      await upsertFinanceAssistantThreshold(newCurrency, amount);
      setNewCurrency("");
      setNewAmount("");
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Assistant approval threshold</CardTitle>
        <CardDescription>
          At or below the threshold for a currency, the Finance Assistant can work on a requisition the same
          as the Finance Accountant, with no forwarding needed. Above it, only the Accountant can act — the
          Assistant is still notified and the Accountant can still forward it to them. A currency with no
          threshold set below is effectively disabled: the Assistant can only get a requisition in that
          currency via forwarding.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        {thresholds.length === 0 ? (
          <p className="text-sm text-muted-foreground">No thresholds configured yet.</p>
        ) : (
          <ul className="space-y-1.5">
            {thresholds.map((t) => (
              <li
                key={t.currency}
                className="flex items-center justify-between rounded-md border px-3 py-1.5 text-sm"
              >
                <span>
                  {t.currency} &le; {t.threshold_amount.toLocaleString()}
                </span>
                <Button
                  variant="ghost"
                  size="icon-sm"
                  disabled={isPending}
                  onClick={() => startTransition(() => deleteFinanceAssistantThreshold(t.currency))}
                >
                  <Trash2 className="size-4" />
                </Button>
              </li>
            ))}
          </ul>
        )}

        <div className="flex gap-2">
          <Select
            value={newCurrency || undefined}
            onValueChange={(v) => setNewCurrency(v ?? "")}
            disabled={isPending}
            items={Object.fromEntries(currencyOptions.map((c) => [c.value, c.label]))}
          >
            <SelectTrigger className="w-40">
              <SelectValue placeholder="Currency" />
            </SelectTrigger>
            <SelectContent>
              {currencyOptions.map((c) => (
                <SelectItem key={c.value} value={c.value}>
                  {c.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Input
            type="number"
            placeholder="Threshold amount"
            value={newAmount}
            onChange={(e) => setNewAmount(e.target.value)}
            className="w-40"
          />
          <Button variant="outline" disabled={isPending} onClick={handleAddThreshold}>
            Add / update
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
