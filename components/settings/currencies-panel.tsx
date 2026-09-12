"use client";

import { useState, useTransition } from "react";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { createCurrency, deleteCurrency } from "@/app/(dashboard)/settings/currencies/actions";

export function CurrenciesPanel({ currencies }: { currencies: string[] }) {
  const [isPending, startTransition] = useTransition();
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);

  function handleAdd() {
    const trimmed = code.trim().toUpperCase();
    if (!trimmed) return;
    startTransition(async () => {
      const result = await createCurrency(trimmed);
      if (result.error) setError(result.error);
      else {
        setError(null);
        setCode("");
      }
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Currencies</CardTitle>
        <CardDescription>
          Used across the requisition form and approval thresholds. Add or remove the currencies your
          organization raises requisitions in.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {currencies.length === 0 ? (
          <p className="text-sm text-muted-foreground">No currencies yet — add one below.</p>
        ) : (
          <ul className="flex flex-wrap gap-2">
            {currencies.map((c) => (
              <li key={c} className="flex items-center gap-1.5 rounded-md border px-3 py-1.5 text-sm">
                {c}
                <Button
                  variant="ghost"
                  size="icon-sm"
                  disabled={isPending}
                  onClick={() => startTransition(() => deleteCurrency(c))}
                >
                  <Trash2 className="size-4" />
                </Button>
              </li>
            ))}
          </ul>
        )}

        <div className="flex items-start gap-2">
          <div>
            <Input
              placeholder="e.g. NGN"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              className="w-32"
              maxLength={3}
            />
            {error ? <p className="mt-1 text-sm text-destructive">{error}</p> : null}
          </div>
          <Button variant="outline" disabled={isPending || !code.trim()} onClick={handleAdd}>
            Add
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
