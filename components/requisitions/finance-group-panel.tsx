"use client";

import { useState, useTransition } from "react";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { addFinanceApprover, removeFinanceApprover } from "@/app/(dashboard)/requisitions/[id]/actions";

interface Person {
  id: string;
  full_name: string;
}

export function FinanceGroupPanel({
  requisitionId,
  members,
  candidates,
}: {
  requisitionId: string;
  members: Person[];
  candidates: Person[];
}) {
  const [isPending, startTransition] = useTransition();
  const [picked, setPicked] = useState("");
  const memberIds = new Set(members.map((m) => m.id));
  const available = candidates.filter((c) => !memberIds.has(c.id));

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Finance review group</CardTitle>
        <CardDescription>
          Your approval alone clears this requisition unless you add others below — then it follows the
          configured Finance approval rule.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {members.length === 0 ? (
          <p className="text-sm text-muted-foreground">Just you, for now.</p>
        ) : (
          <ul className="space-y-1.5">
            {members.map((m) => (
              <li key={m.id} className="flex items-center justify-between rounded-md border px-3 py-1.5 text-sm">
                {m.full_name}
                <Button
                  variant="ghost"
                  size="icon-sm"
                  disabled={isPending}
                  onClick={() => startTransition(() => removeFinanceApprover(requisitionId, m.id))}
                >
                  <Trash2 className="size-4" />
                </Button>
              </li>
            ))}
          </ul>
        )}

        <div className="flex gap-2">
          <Select
            value={picked}
            onValueChange={(v) => setPicked(v ?? "")}
            items={Object.fromEntries(available.map((c) => [c.id, c.full_name]))}
          >
            <SelectTrigger className="w-full">
              <SelectValue placeholder="Add another reviewer…" />
            </SelectTrigger>
            <SelectContent>
              {available.map((c) => (
                <SelectItem key={c.id} value={c.id}>
                  {c.full_name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Button
            variant="outline"
            disabled={!picked || isPending}
            onClick={() =>
              startTransition(async () => {
                await addFinanceApprover(requisitionId, picked);
                setPicked("");
              })
            }
          >
            Add
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
