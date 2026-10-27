"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { setRequisitionCopiedInAction } from "@/app/(dashboard)/requisitions/[id]/actions";

interface Person {
  id: string;
  full_name: string;
}

const MAX_COPIED_IN = 10;

export function CopiedInPanel({
  requisitionId,
  selected,
  candidates,
  editable,
}: {
  requisitionId: string;
  selected: Person[];
  /** Every active user the requester may copy in (not themselves). */
  candidates: Person[];
  /** The requester, until the requisition is closed. */
  editable: boolean;
}) {
  const [isPending, startTransition] = useTransition();
  const [picked, setPicked] = useState("");
  const selectedIds = new Set(selected.map((s) => s.id));
  const available = candidates.filter((c) => !selectedIds.has(c.id));

  function save(nextIds: string[]) {
    startTransition(async () => {
      const result = await setRequisitionCopiedInAction(requisitionId, nextIds);
      if (result.error) toast.error(result.error);
      setPicked("");
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">{editable ? "Copy someone in (optional)" : "Copied in"}</CardTitle>
        {editable ? (
          <CardDescription>
            Copy in anyone who should follow this requisition. They&apos;ll get an email at every stage, can read
            the whole requisition and comment on it — but they don&apos;t approve anything, and the approval route
            doesn&apos;t change.
          </CardDescription>
        ) : (
          <CardDescription>
            These people follow this requisition. They get an update at every stage and can comment, but
            don&apos;t approve.
          </CardDescription>
        )}
      </CardHeader>
      <CardContent className="space-y-3">
        {selected.length === 0 ? (
          <p className="text-sm text-muted-foreground">No one copied in.</p>
        ) : (
          <ul className="space-y-1.5">
            {selected.map((s) => (
              <li key={s.id} className="flex items-center justify-between gap-2 rounded-md border px-3 py-1.5 text-sm">
                {s.full_name}
                {editable ? (
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    aria-label={`Remove ${s.full_name}`}
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
          selected.length >= MAX_COPIED_IN ? (
            <p className="text-xs text-muted-foreground">Maximum of {MAX_COPIED_IN} people.</p>
          ) : available.length === 0 ? (
            <p className="text-xs text-muted-foreground">No one else available to copy in.</p>
          ) : (
            <div className="flex gap-2">
              <Select
                value={picked}
                onValueChange={(v) => setPicked(v ?? "")}
                disabled={isPending}
                items={Object.fromEntries(available.map((c) => [c.id, c.full_name]))}
              >
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Copy someone in…" />
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
