"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { createRequisitionInDepartment } from "@/app/(dashboard)/requisitions/new/actions";

export function ChooseDepartmentForm({ departments }: { departments: { id: string; name: string }[] }) {
  const [departmentId, setDepartmentId] = useState("");
  const [isPending, startTransition] = useTransition();

  function handleContinue() {
    if (!departmentId) return;
    startTransition(async () => {
      const result = await createRequisitionInDepartment(departmentId);
      if (result?.error) toast.error(result.error);
    });
  }

  return (
    <div className="mx-auto max-w-md space-y-4 rounded-lg border bg-card p-6">
      <div>
        <h1 className="text-lg font-semibold">Which department is this for?</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          You belong to more than one department — pick which one this requisition is for. This can&apos;t be
          changed once it&apos;s created.
        </p>
      </div>
      <Select
        value={departmentId}
        onValueChange={(v) => setDepartmentId(v ?? "")}
        disabled={isPending}
        items={Object.fromEntries(departments.map((d) => [d.id, d.name]))}
      >
        <SelectTrigger className="w-full">
          <SelectValue placeholder="Select a department" />
        </SelectTrigger>
        <SelectContent>
          {departments.map((d) => (
            <SelectItem key={d.id} value={d.id}>
              {d.name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Button onClick={handleContinue} disabled={!departmentId || isPending} className="w-full">
        {isPending ? "Starting…" : "Continue"}
      </Button>
    </div>
  );
}
