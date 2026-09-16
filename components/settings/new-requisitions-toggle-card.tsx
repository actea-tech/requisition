"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { setNewRequisitionsEnabled } from "@/app/(dashboard)/settings/approval-rules/actions";

export function NewRequisitionsToggleCard({ initialEnabled }: { initialEnabled: boolean }) {
  const [value, setValue] = useState<"yes" | "no">(initialEnabled ? "yes" : "no");
  const [isPending, startTransition] = useTransition();

  function handleChange(next: "yes" | "no") {
    setValue(next);
    startTransition(async () => {
      const result = await setNewRequisitionsEnabled(next === "yes");
      if (result.error) toast.error(result.error);
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>New requisitions</CardTitle>
        <CardDescription>
          Turn off to pause everyone from starting a new requisition — e.g. during maintenance, or to get key
          approvers set up before intake reopens. Anything already submitted is unaffected either way. Admins can
          still raise requisitions while this is off.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Select
          value={value}
          onValueChange={(v) => handleChange((v ?? "yes") as "yes" | "no")}
          disabled={isPending}
          items={{
            yes: "Open — anyone can start a new requisition",
            no: "Paused — only admins can start a new requisition",
          }}
        >
          <SelectTrigger className="w-full max-w-md">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="yes">Open — anyone can start a new requisition</SelectItem>
            <SelectItem value="no">Paused — only admins can start a new requisition</SelectItem>
          </SelectContent>
        </Select>
      </CardContent>
    </Card>
  );
}
