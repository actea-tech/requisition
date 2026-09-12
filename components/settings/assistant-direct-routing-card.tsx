"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { setAssistantFinanceDirectRouting } from "@/app/(dashboard)/settings/authorizers/actions";

type Routing = "direct" | "requires_accountant_approval";

export function AssistantDirectRoutingCard({ initialValue }: { initialValue: Routing }) {
  const [value, setValue] = useState<Routing>(initialValue);
  const [isPending, startTransition] = useTransition();

  function handleChange(next: Routing) {
    setValue(next);
    startTransition(async () => {
      const result = await setAssistantFinanceDirectRouting(next);
      if (result.error) toast.error(result.error);
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Assistant-raised Finance-direct requests</CardTitle>
        <CardDescription>
          A Finance Accountant&apos;s or admin&apos;s Finance-direct requisitions (e.g. payroll) always go
          straight to authorization. This decides what happens when a Finance Assistant raises one instead.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Select
          value={value}
          onValueChange={(v) => handleChange((v ?? "requires_accountant_approval") as Routing)}
          disabled={isPending}
          items={{
            requires_accountant_approval: "Goes to the Finance Accountant for approval first",
            direct: "Goes straight to authorization, same as the Accountant",
          }}
        >
          <SelectTrigger className="w-full max-w-md">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="requires_accountant_approval">Goes to the Finance Accountant for approval first</SelectItem>
            <SelectItem value="direct">Goes straight to authorization, same as the Accountant</SelectItem>
          </SelectContent>
        </Select>
      </CardContent>
    </Card>
  );
}
