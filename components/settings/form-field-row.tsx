"use client";

import { useTransition } from "react";
import { Switch } from "@/components/ui/switch";
import { TableCell, TableRow } from "@/components/ui/table";
import { setFieldRequired, setFieldVisibility } from "@/app/(dashboard)/settings/form-fields/actions";

interface FieldRow {
  id: string;
  label: string;
  help_text: string | null;
  is_visible: boolean;
  is_required: boolean;
}

export function FormFieldRow({ field }: { field: FieldRow }) {
  const [isPending, startTransition] = useTransition();

  return (
    <TableRow>
      <TableCell>
        <div className="font-medium">{field.label}</div>
        {field.help_text ? <div className="text-xs text-muted-foreground">{field.help_text}</div> : null}
      </TableCell>
      <TableCell>
        <Switch
          checked={field.is_visible}
          disabled={isPending}
          onCheckedChange={(checked) => startTransition(() => setFieldVisibility(field.id, checked))}
        />
      </TableCell>
      <TableCell>
        <Switch
          checked={field.is_required}
          disabled={isPending || !field.is_visible}
          onCheckedChange={(checked) => startTransition(() => setFieldRequired(field.id, checked))}
        />
      </TableCell>
    </TableRow>
  );
}
