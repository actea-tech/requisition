"use client";

import { useState, useTransition } from "react";
import { Trash2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import {
  addDepartmentHead,
  removeDepartmentHead,
  setDepartmentActive,
  setDepartmentApprovalOverride,
} from "@/app/(dashboard)/settings/departments/actions";
import type { ApprovalMode } from "@/lib/supabase/database.types";

interface Profile {
  id: string;
  full_name: string;
  email: string;
}

interface Override {
  mode: ApprovalMode;
  quorum_count: number | null;
}

export function DepartmentCard({
  department,
  heads,
  candidates,
  override,
  globalMode,
}: {
  department: { id: string; name: string; is_active: boolean };
  heads: Profile[];
  candidates: Profile[];
  override: Override | null;
  globalMode: ApprovalMode;
}) {
  const [isPending, startTransition] = useTransition();
  const [pickerValue, setPickerValue] = useState("");
  const [mode, setMode] = useState<ApprovalMode | "default">(override?.mode ?? "default");
  const [quorum, setQuorum] = useState(override?.quorum_count?.toString() ?? "2");

  const headIds = new Set(heads.map((h) => h.id));
  const availableCandidates = candidates.filter((c) => !headIds.has(c.id));

  function handleAddHead() {
    if (!pickerValue) return;
    startTransition(async () => {
      await addDepartmentHead(department.id, pickerValue);
      setPickerValue("");
    });
  }

  function handleSaveOverride() {
    startTransition(async () => {
      await setDepartmentApprovalOverride(
        department.id,
        mode,
        mode === "quorum" ? Number(quorum) || 1 : null,
      );
    });
  }

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between space-y-0">
        <CardTitle className="flex items-center gap-2">
          {department.name}
          {!department.is_active ? <Badge variant="secondary">Inactive</Badge> : null}
        </CardTitle>
        <div className="flex items-center gap-2">
          <span className="text-xs text-muted-foreground">Active</span>
          <Switch
            checked={department.is_active}
            onCheckedChange={(checked) => startTransition(() => setDepartmentActive(department.id, checked))}
          />
        </div>
      </CardHeader>
      <CardContent className="space-y-5">
        <div>
          <p className="mb-2 text-sm font-medium">Department heads</p>
          {heads.length === 0 ? (
            <p className="text-sm text-muted-foreground">No heads assigned yet.</p>
          ) : (
            <ul className="space-y-1.5">
              {heads.map((head) => (
                <li key={head.id} className="flex items-center justify-between rounded-md border px-3 py-1.5 text-sm">
                  <div>
                    <span className="font-medium">{head.full_name}</span>{" "}
                    <span className="text-muted-foreground">{head.email}</span>
                  </div>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="size-7"
                    disabled={isPending}
                    onClick={() => startTransition(() => removeDepartmentHead(department.id, head.id))}
                  >
                    <Trash2 className="size-4" />
                  </Button>
                </li>
              ))}
            </ul>
          )}

          <div className="mt-3 flex gap-2">
            <Select value={pickerValue} onValueChange={(value) => setPickerValue(value ?? "")}>
              <SelectTrigger className="w-full max-w-xs">
                <SelectValue placeholder="Add a department head…" />
              </SelectTrigger>
              <SelectContent>
                {availableCandidates.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.full_name} ({c.email})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Button variant="outline" disabled={!pickerValue || isPending} onClick={handleAddHead}>
              Add
            </Button>
          </div>
        </div>

        <div className="border-t pt-4">
          <p className="mb-1 text-sm font-medium">Approval mode for this department</p>
          <p className="mb-2 text-xs text-muted-foreground">
            If only one head is assigned, their approval alone always resolves this stage, regardless of this
            setting. Leave as &ldquo;Use global default&rdquo; ({globalMode.replace("_", " ")}) unless this
            department needs a different rule.
          </p>
          <div className="flex flex-wrap items-center gap-2">
            <Select value={mode} onValueChange={(v) => setMode(v as ApprovalMode | "default")}>
              <SelectTrigger className="w-56">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="default">Use global default</SelectItem>
                <SelectItem value="first_approver">First approver decides</SelectItem>
                <SelectItem value="all_approvers">All heads must approve</SelectItem>
                <SelectItem value="quorum">Quorum of heads</SelectItem>
              </SelectContent>
            </Select>
            {mode === "quorum" ? (
              <Input
                type="number"
                min={1}
                value={quorum}
                onChange={(e) => setQuorum(e.target.value)}
                className="w-24"
              />
            ) : null}
            <Button size="sm" disabled={isPending} onClick={handleSaveOverride}>
              Save
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
