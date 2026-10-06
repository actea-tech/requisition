"use client";

import { Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { DynamicField, type FieldMeta } from "@/components/requisitions/dynamic-field";
import { emptyPayee, payeesTotal, type PayeeFieldKey, type PayeeRow } from "@/lib/payees";

export function PayeesEditor({
  payees,
  onChange,
  fields,
  editable,
  currency,
}: {
  payees: PayeeRow[];
  onChange: (next: PayeeRow[]) => void;
  fields: FieldMeta[];
  editable: boolean;
  currency: string;
}) {
  const multiple = payees.length > 1;
  const total = payeesTotal(payees);

  function update(key: string, field: PayeeFieldKey, value: string) {
    onChange(payees.map((p) => (p.key === key ? { ...p, [field]: value } : p)));
  }

  return (
    <div className="space-y-4 sm:col-span-2">
      {payees.map((payee, index) => (
        <div key={payee.key} className="space-y-4 rounded-lg border p-4">
          {multiple || editable ? (
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-medium">{multiple ? `Payee ${index + 1}` : "Payee"}</h3>
              {editable && multiple ? (
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="text-muted-foreground hover:text-destructive"
                  onClick={() => onChange(payees.filter((p) => p.key !== payee.key))}
                >
                  <Trash2 className="size-4" />
                  Remove
                </Button>
              ) : null}
            </div>
          ) : null}
          <div className="grid gap-4 sm:grid-cols-2">
            {fields.map((field) => (
              <DynamicField
                key={field.field_key}
                field={field}
                value={payee[field.field_key as PayeeFieldKey] ?? ""}
                onChange={(v) => update(payee.key, field.field_key as PayeeFieldKey, v)}
                disabled={!editable}
                idSuffix={payee.key}
              />
            ))}
          </div>
        </div>
      ))}

      <div className="flex flex-wrap items-center justify-between gap-3">
        {editable ? (
          <div className="space-y-1">
            <Button type="button" variant="outline" size="sm" onClick={() => onChange([...payees, emptyPayee()])}>
              <Plus className="size-4" />
              Add payee
            </Button>
            {multiple ? (
              <p className="text-xs text-muted-foreground">
                All payees are paid in {currency}. Currency is locked while there is more than one payee.
              </p>
            ) : null}
          </div>
        ) : (
          <span />
        )}
        <div className="text-right">
          <div className="text-xs text-muted-foreground">Total payment</div>
          <div className="text-lg font-semibold">
            {currency}{" "}
            {total.toLocaleString(undefined, {
              minimumFractionDigits: Number.isInteger(total) ? 0 : 2,
              maximumFractionDigits: 2,
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
