"use client";

import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { setGlobalStageMode } from "@/app/(dashboard)/settings/approval-rules/actions";
import type { ApprovalMode, ApprovalStageKey } from "@/lib/supabase/database.types";

export function StageModeCard({
  stageKey,
  title,
  description,
  initialMode,
  initialQuorum,
}: {
  stageKey: ApprovalStageKey;
  title: string;
  description: string;
  initialMode: ApprovalMode;
  initialQuorum: number | null;
}) {
  const [mode, setMode] = useState<ApprovalMode>(initialMode);
  const [quorum, setQuorum] = useState(initialQuorum?.toString() ?? "2");
  const [isPending, startTransition] = useTransition();
  const [saved, setSaved] = useState(false);

  function handleSave() {
    startTransition(async () => {
      await setGlobalStageMode(stageKey, mode, mode === "quorum" ? Number(quorum) || 1 : null);
      setSaved(true);
      setTimeout(() => setSaved(false), 1500);
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-wrap items-center gap-2">
        <Select
          value={mode}
          onValueChange={(v) => setMode(v as ApprovalMode)}
          items={{
            first_approver: "First approver decides",
            all_approvers: "All eligible approvers must approve",
            quorum: "Quorum of approvers",
          }}
        >
          <SelectTrigger className="w-56">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="first_approver">First approver decides</SelectItem>
            <SelectItem value="all_approvers">All eligible approvers must approve</SelectItem>
            <SelectItem value="quorum">Quorum of approvers</SelectItem>
          </SelectContent>
        </Select>
        {mode === "quorum" ? (
          <Input type="number" min={1} value={quorum} onChange={(e) => setQuorum(e.target.value)} className="w-24" />
        ) : null}
        <Button size="sm" disabled={isPending} onClick={handleSave}>
          {saved ? "Saved" : "Save"}
        </Button>
      </CardContent>
    </Card>
  );
}
