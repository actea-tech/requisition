"use client";

import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { FIELD_SPECS } from "@/lib/requisition-fields";

export interface FieldMeta {
  field_key: string;
  label: string;
  help_text: string | null;
  is_required: boolean;
}

export function DynamicField({
  field,
  value,
  onChange,
  disabled,
}: {
  field: FieldMeta;
  value: string;
  onChange: (value: string) => void;
  disabled: boolean;
}) {
  const spec = FIELD_SPECS[field.field_key] ?? { type: "text" as const };
  const id = `field-${field.field_key}`;

  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>
        {field.label}
        {field.is_required ? <span className="text-destructive"> *</span> : null}
      </Label>

      {spec.type === "textarea" ? (
        <Textarea id={id} value={value} onChange={(e) => onChange(e.target.value)} disabled={disabled} rows={3} />
      ) : spec.type === "select" ? (
        <Select
          value={value || undefined}
          onValueChange={(v) => onChange(v ?? "")}
          disabled={disabled}
          items={Object.fromEntries((spec.options ?? []).map((o) => [o.value, o.label]))}
        >
          <SelectTrigger className="w-full">
            <SelectValue placeholder="Select…" />
          </SelectTrigger>
          <SelectContent>
            {spec.options?.map((opt) => (
              <SelectItem key={opt.value} value={opt.value}>
                {opt.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      ) : (
        <Input
          id={id}
          type={spec.type === "number" ? "number" : "text"}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          disabled={disabled}
        />
      )}

      {field.help_text ? <p className="text-xs text-muted-foreground">{field.help_text}</p> : null}
    </div>
  );
}
