"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Trash2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { setRequisitionSupervisorsAction } from "@/app/(dashboard)/requisitions/[id]/actions";

interface Person {
  id: string;
  full_name: string;
}

const MAX_SUPERVISORS = 5;

export function SupervisorsPanel({
  requisitionId,
  selected,
  candidates,
  approvedIds,
  editable,
}: {
  requisitionId: string;
  selected: Person[];
  /** Everyone on the supervisor list the requester may pick (not themselves). */
  candidates: Person[];
  /** Supervisors who have approved in the current round. */
  approvedIds: string[];
  /** The requester, while they can still edit the requisition. */
  editable: boolean;
}) {
  const [isPending, startTransition] = useTransition();
  const [picked, setPicked] = useState("");
  const approved = new Set(approvedIds);
  const selectedIds = new Set(selected.map((s) => s.id));
  const available = candidates.filter((c) => !selectedIds.has(c.id));

  function save(nextIds: string[]) {
    startTransition(async () => {
      const result = await setRequisitionSupervisorsAction(requisitionId, nextIds);
      if (result.error) toast.error(result.error);
      setPicked("");
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">{editable ? "Supervisor review (optional)" : "Supervisors"}</CardTitle>
        {editable ? (
          <CardDescription>
            Want someone to review this before it goes to Finance? Choose one or more supervisors — they&apos;ll
            each need to approve it first. Leave it empty to send it straight on as usual.
          </CardDescription>
        ) : (
          <CardDescription>The supervisors chosen to review this before it went to Finance.</CardDescription>
        )}
      </CardHeader>
      <CardContent className="space-y-3">
        {selected.length === 0 ? (
          <p className="text-sm text-muted-foreground">No supervisors chosen.</p>
        ) : (
          <ul className="space-y-1.5">
            {selected.map((s) => (
              <li key={s.id} className="flex items-center justify-between gap-2 rounded-md border px-3 py-1.5 text-sm">
                <span className="flex items-center gap-2">
                  {s.full_name}
                  {approved.has(s.id) ? <Badge variant="success">Approved</Badge> : null}
                </span>
                {editable ? (
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    aria-label="Remove supervisor"
                    disabled={isPending}
                    onClick={() => save(selected.filter((x) => x.id !== s.id).map((x) => x.id))}
                  >
                    <Trash2 className="size-4" />
                  </Button>
                ) : null}
              </li>
            ))}
          </ul>
        )}

        {editable ? (
          selected.length >= MAX_SUPERVISORS ? (
            <p className="text-xs text-muted-foreground">Maximum of {MAX_SUPERVISORS} supervisors.</p>
          ) : available.length === 0 ? (
            <p className="text-xs text-muted-foreground">No other supervisors available to add.</p>
          ) : (
            <div className="flex gap-2">
              <Select
                value={picked}
                onValueChange={(v) => setPicked(v ?? "")}
                disabled={isPending}
                items={Object.fromEntries(available.map((c) => [c.id, c.full_name]))}
              >
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Add a supervisor…" />
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
                onClick={() => save([...selected.map((s) => s.id), picked])}
              >
                Add
              </Button>
            </div>
          )
        ) : null}
      </CardContent>
    </Card>
  );
}
