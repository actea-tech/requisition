"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { STATUS_STEPS } from "@/lib/requisition-status";

export function AuditFiltersForm({ departments }: { departments: { id: string; name: string }[] }) {
  const router = useRouter();
  const searchParams = useSearchParams();

  function update(key: string, value: string) {
    const params = new URLSearchParams(searchParams.toString());
    if (value) params.set(key, value);
    else params.delete(key);
    router.push(`/audit?${params.toString()}`);
  }

  return (
    <div className="flex flex-wrap items-end gap-3">
      <div className="space-y-1.5">
        <Label>Status</Label>
        <Select
          value={searchParams.get("status") ?? "all"}
          onValueChange={(v) => update("status", v === "all" ? "" : (v ?? ""))}
          items={{
            all: "All statuses",
            ...Object.fromEntries(STATUS_STEPS.map((s) => [s.status, s.label])),
            returned: "Returned",
            rejected: "Rejected",
          }}
        >
          <SelectTrigger className="w-48">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All statuses</SelectItem>
            {STATUS_STEPS.map((s) => (
              <SelectItem key={s.status} value={s.status}>
                {s.label}
              </SelectItem>
            ))}
            <SelectItem value="returned">Returned</SelectItem>
            <SelectItem value="rejected">Rejected</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <div className="space-y-1.5">
        <Label>Department</Label>
        <Select
          value={searchParams.get("department") ?? "all"}
          onValueChange={(v) => update("department", v === "all" ? "" : (v ?? ""))}
          items={{ all: "All departments", ...Object.fromEntries(departments.map((d) => [d.id, d.name])) }}
        >
          <SelectTrigger className="w-48">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All departments</SelectItem>
            {departments.map((d) => (
              <SelectItem key={d.id} value={d.id}>
                {d.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="from">From</Label>
        <Input
          id="from"
          type="date"
          className="w-40"
          defaultValue={searchParams.get("from") ?? ""}
          onChange={(e) => update("from", e.target.value)}
        />
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="to">To</Label>
        <Input
          id="to"
          type="date"
          className="w-40"
          defaultValue={searchParams.get("to") ?? ""}
          onChange={(e) => update("to", e.target.value)}
        />
      </div>

      <Button variant="ghost" onClick={() => router.push("/audit")}>
        Clear
      </Button>
    </div>
  );
}
