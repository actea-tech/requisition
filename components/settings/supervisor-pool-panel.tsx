"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { addToSupervisorPool, removeFromSupervisorPool } from "@/app/(dashboard)/settings/authorizers/actions";

interface Person {
  id: string;
  full_name: string;
}

export function SupervisorPoolPanel({ members, candidates }: { members: Person[]; candidates: Person[] }) {
  const [isPending, startTransition] = useTransition();
  const [picked, setPicked] = useState("");

  return (
    <Card>
      <CardHeader>
        <CardTitle>Supervisor list</CardTitle>
        <CardDescription>
          Anyone listed here can be chosen as a supervisor by someone raising a requisition — mainly an
          Individual requisition, or a department head who wants a supervisor&apos;s input. It&apos;s optional
          for the requester: if they pick none, the requisition goes the usual way. The people they pick review
          it first, in the department-review position, before it goes to Finance; all of them must approve.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {members.length === 0 ? (
          <p className="text-sm text-muted-foreground">No one added yet.</p>
        ) : (
          <ul className="space-y-1.5">
            {members.map((m) => (
              <li key={m.id} className="flex items-center justify-between rounded-md border px-3 py-1.5 text-sm">
                {m.full_name}
                <Button
                  variant="ghost"
                  size="icon-sm"
                  aria-label="Remove from supervisor list"
                  disabled={isPending}
                  onClick={() => startTransition(() => removeFromSupervisorPool(m.id))}
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
            disabled={isPending}
            items={Object.fromEntries(candidates.map((c) => [c.id, c.full_name]))}
          >
            <SelectTrigger className="w-full">
              <SelectValue placeholder="Add a person…" />
            </SelectTrigger>
            <SelectContent>
              {candidates.map((c) => (
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
                const result = await addToSupervisorPool(picked);
                if (result.error) toast.error(result.error);
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
