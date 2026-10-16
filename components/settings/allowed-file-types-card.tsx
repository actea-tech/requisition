"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Label } from "@/components/ui/label";
import { setAllowedFileTypes } from "@/app/(dashboard)/settings/approval-rules/actions";
import { FILE_TYPE_OPTIONS } from "@/lib/file-types";

export function AllowedFileTypesCard({ initialAllowed }: { initialAllowed: string[] }) {
  const [allowed, setAllowed] = useState<string[]>(initialAllowed);
  const [isPending, startTransition] = useTransition();

  function toggle(id: string, checked: boolean) {
    const next = checked ? [...allowed, id] : allowed.filter((a) => a !== id);
    if (next.length === 0) return;
    const previous = allowed;
    setAllowed(next);
    startTransition(async () => {
      const result = await setAllowedFileTypes(next);
      if (result.error) {
        toast.error(result.error);
        setAllowed(previous);
      }
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Allowed file types</CardTitle>
        <CardDescription>
          Only the file types switched on here can be uploaded — to a requisition&apos;s documents and to
          expenditure receipts. Each upload section shows its supported types. Files that were already
          uploaded stay as they are, whatever you change. At least one type must stay on.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-3 sm:grid-cols-2">
        {FILE_TYPE_OPTIONS.map((option) => {
          const checked = allowed.includes(option.id);
          return (
            <div key={option.id} className="flex items-center gap-2">
              <Checkbox
                id={`file-type-${option.id}`}
                checked={checked}
                disabled={isPending || (checked && allowed.length === 1)}
                onCheckedChange={(c) => toggle(option.id, c === true)}
              />
              <Label htmlFor={`file-type-${option.id}`} className="font-normal">
                {option.label}{" "}
                <span className="text-muted-foreground">({option.extensions.map((e) => `.${e}`).join(", ")})</span>
              </Label>
            </div>
          );
        })}
      </CardContent>
    </Card>
  );
}
