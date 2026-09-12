"use client";

import { useState, useTransition } from "react";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  deleteDirectorAuthThreshold,
  setDirectorAuthMode,
  upsertDirectorAuthThreshold,
} from "@/app/(dashboard)/settings/approval-rules/actions";

type DirectorAuthMode = "accountant_discretion" | "amount_threshold";

export function DirectorAuthorizationCard({
  initialMode,
  thresholds,
  currencyOptions,
}: {
  initialMode: DirectorAuthMode;
  thresholds: { currency: string; threshold_amount: number }[];
  currencyOptions: { value: string; label: string }[];
}) {
  const [mode, setMode] = useState<DirectorAuthMode>(initialMode);
  const [isPending, startTransition] = useTransition();
  const [newCurrency, setNewCurrency] = useState("");
  const [newAmount, setNewAmount] = useState("");

  function handleModeChange(value: DirectorAuthMode) {
    setMode(value);
    startTransition(async () => {
      await setDirectorAuthMode(value);
    });
  }

  function handleAddThreshold() {
    const amount = Number(newAmount);
    if (!newCurrency || !amount) return;
    startTransition(async () => {
      await upsertDirectorAuthThreshold(newCurrency, amount);
      setNewCurrency("");
      setNewAmount("");
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Authorization requirement</CardTitle>
        <CardDescription>
          Decides whether a requisition needs authorization after Finance clears it, or can go straight to
          payment.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <Select
          value={mode}
          onValueChange={(v) => handleModeChange((v ?? "accountant_discretion") as DirectorAuthMode)}
          disabled={isPending}
          items={{
            accountant_discretion: "Finance Accountant decides per requisition",
            amount_threshold: "Automatic, based on amount threshold",
          }}
        >
          <SelectTrigger className="w-full max-w-md">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="accountant_discretion">Finance Accountant decides per requisition</SelectItem>
            <SelectItem value="amount_threshold">Automatic, based on amount threshold</SelectItem>
          </SelectContent>
        </Select>

        {mode === "amount_threshold" ? (
          <div className="space-y-2 border-t pt-4">
            <p className="text-sm font-medium">Thresholds by currency</p>
            <p className="text-xs text-muted-foreground">
              At or above the threshold, authorization is required. A currency with no threshold set here
              always requires authorization.
            </p>

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
                      {t.currency} &ge; {t.threshold_amount.toLocaleString()}
                    </span>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      disabled={isPending}
                      onClick={() => startTransition(() => deleteDirectorAuthThreshold(t.currency))}
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
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}
