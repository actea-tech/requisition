"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { setPaymentStageCancellationEnabled } from "@/app/(dashboard)/settings/approval-rules/actions";

export function PaymentStageCancellationCard({ initialEnabled }: { initialEnabled: boolean }) {
  const [value, setValue] = useState<"yes" | "no">(initialEnabled ? "yes" : "no");
  const [isPending, startTransition] = useTransition();

  function handleChange(next: "yes" | "no") {
    setValue(next);
    startTransition(async () => {
      const result = await setPaymentStageCancellationEnabled(next === "yes");
      if (result.error) toast.error(result.error);
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Cancellation at Payment Processing</CardTitle>
        <CardDescription>
          Hidden by default — a requisition that&apos;s already reached Payment Processing has been fully
          authorized, so cancelling it from here is an exception, not the norm. Cancelling earlier (Finance
          or Authorization review) is unaffected either way.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Select
          value={value}
          onValueChange={(v) => handleChange((v ?? "no") as "yes" | "no")}
          disabled={isPending}
          items={{
            no: "Hidden — cancellation isn't offered at Payment Processing",
            yes: "Shown — Finance can request cancellation at Payment Processing",
          }}
        >
          <SelectTrigger className="w-full max-w-md">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="no">Hidden — cancellation isn&apos;t offered at Payment Processing</SelectItem>
            <SelectItem value="yes">Shown — Finance can request cancellation at Payment Processing</SelectItem>
          </SelectContent>
        </Select>
      </CardContent>
    </Card>
  );
}
