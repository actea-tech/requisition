"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { forwardToAssistant, unforwardFromAssistant } from "@/app/(dashboard)/requisitions/[id]/actions";

interface Person {
  id: string;
  full_name: string;
}

export function AssistantForwardControl({
  requisitionId,
  candidates,
  forwardedAssistantId,
}: {
  requisitionId: string;
  candidates: Person[];
  forwardedAssistantId: string | null;
}) {
  const [isPending, startTransition] = useTransition();
  const [picked, setPicked] = useState(forwardedAssistantId ?? candidates[0]?.id ?? "");

  if (candidates.length === 0) return null;

  const forwardedTo = candidates.find((c) => c.id === forwardedAssistantId);

  function handleForward(assistantId: string) {
    startTransition(async () => {
      const result = await forwardToAssistant(requisitionId, assistantId);
      if (result.error) toast.error(result.error);
      else toast.success("Forwarded for approval");
    });
  }

  function handleUnforward() {
    startTransition(async () => {
      await unforwardFromAssistant(requisitionId);
      toast.success("Forward removed");
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Assistant Finance Accountant</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {forwardedTo ? (
          <div className="flex items-center justify-between rounded-md border px-3 py-2 text-sm">
            <span>
              Forwarded to <span className="font-medium">{forwardedTo.full_name}</span> for approval
            </span>
            <Button variant="ghost" size="sm" disabled={isPending} onClick={handleUnforward}>
              Unforward
            </Button>
          </div>
        ) : candidates.length === 1 ? (
          <Button
            className="w-full"
            variant="outline"
            disabled={isPending}
            onClick={() => handleForward(candidates[0].id)}
          >
            Forward to {candidates[0].full_name} for approval
          </Button>
        ) : (
          <div className="flex gap-2">
            <Select
              value={picked}
              onValueChange={(v) => setPicked(v ?? "")}
              disabled={isPending}
              items={Object.fromEntries(candidates.map((c) => [c.id, c.full_name]))}
            >
              <SelectTrigger className="w-full">
                <SelectValue placeholder="Choose an assistant…" />
              </SelectTrigger>
              <SelectContent>
                {candidates.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.full_name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Button variant="outline" disabled={!picked || isPending} onClick={() => handleForward(picked)}>
              Forward
            </Button>
          </div>
        )}
        <p className="text-xs text-muted-foreground">
          Above their approval threshold, an Assistant can only act on this requisition once it&apos;s forwarded
          to them here.
        </p>
      </CardContent>
    </Card>
  );
}
