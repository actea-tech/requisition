"use client";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Label } from "@/components/ui/label";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";

export function DepartmentsChecklist({
  departments,
  selectedIds,
  onChange,
  disabled,
}: {
  departments: { id: string; name: string }[];
  selectedIds: string[];
  onChange: (ids: string[]) => void;
  disabled?: boolean;
}) {
  const selectedNames = departments.filter((d) => selectedIds.includes(d.id)).map((d) => d.name);

  function toggle(id: string, checked: boolean) {
    onChange(checked ? [...selectedIds, id] : selectedIds.filter((existing) => existing !== id));
  }

  return (
    <Popover>
      <PopoverTrigger render={<Button variant="outline" size="sm" disabled={disabled} className="w-44 justify-start font-normal" />}>
        <span className="truncate">{selectedNames.length > 0 ? selectedNames.join(", ") : "No department"}</span>
      </PopoverTrigger>
      <PopoverContent className="w-56">
        {departments.length === 0 ? (
          <p className="text-sm text-muted-foreground">No departments yet.</p>
        ) : (
          <div className="space-y-2">
            {departments.map((d) => (
              <div key={d.id} className="flex items-center gap-2">
                <Checkbox
                  id={`dept-${d.id}`}
                  checked={selectedIds.includes(d.id)}
                  onCheckedChange={(checked) => toggle(d.id, checked === true)}
                  disabled={disabled}
                />
                <Label htmlFor={`dept-${d.id}`} className="font-normal">
                  {d.name}
                </Label>
              </div>
            ))}
          </div>
        )}
      </PopoverContent>
    </Popover>
  );
}
