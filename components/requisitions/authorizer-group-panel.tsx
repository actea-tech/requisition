"use client";

import { useState, useTransition } from "react";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { addRequisitionAuthorizer, removeRequisitionAuthorizer } from "@/app/(dashboard)/requisitions/[id]/actions";

interface Person {
  id: string;
  full_name: string;
}

const MAX_AUTHORIZERS = 4;

export function AuthorizerGroupPanel({
  requisitionId,
  members,
  candidates,
  requesterId,
  disabled = false,
}: {
  requisitionId: string;
  members: Person[];
  candidates: Person[];
  requesterId: string;
  /** True once "Requires authorization?" is set to No — the selection is already cleared, and this keeps it that way. */
  disabled?: boolean;
}) {
  const [isPending, startTransition] = useTransition();
  const [picked, setPicked] = useState("");
  const [confirmConflictOpen, setConfirmConflictOpen] = useState(false);
  const memberIds = new Set(members.map((m) => m.id));
  const available = candidates.filter((c) => !memberIds.has(c.id));
  const atCap = members.length >= MAX_AUTHORIZERS;

  function doAdd(userId: string) {
    startTransition(async () => {
      await addRequisitionAuthorizer(requisitionId, userId);
      setPicked("");
    });
  }

  function handleAddClick() {
    if (!picked) return;
    if (picked === requesterId) {
      setConfirmConflictOpen(true);
      return;
    }
    doAdd(picked);
  }

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Authorizers</CardTitle>
          <CardDescription>
            Select 1–4 people to authorize this payment. All of them must approve before it moves to payment
            processing.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {disabled ? (
            <p className="text-sm text-muted-foreground">
              Not needed — this requisition is set to clear directly for payment. Switch &ldquo;Requires
              authorization?&rdquo; to Yes to select authorizers.
            </p>
          ) : (
            <>
              {members.length === 0 ? (
                <p className="text-sm text-muted-foreground">No authorizers selected yet.</p>
              ) : (
                <ul className="space-y-1.5">
                  {members.map((m) => (
                    <li
                      key={m.id}
                      className="flex items-center justify-between rounded-md border px-3 py-1.5 text-sm"
                    >
                      {m.full_name}
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        disabled={isPending}
                        onClick={() => startTransition(() => removeRequisitionAuthorizer(requisitionId, m.id))}
                      >
                        <Trash2 className="size-4" />
                      </Button>
                    </li>
                  ))}
                </ul>
              )}

              {atCap ? (
                <p className="text-xs text-muted-foreground">Maximum of {MAX_AUTHORIZERS} authorizers selected.</p>
              ) : (
                <div className="flex gap-2">
                  <Select
                    value={picked}
                    onValueChange={(v) => setPicked(v ?? "")}
                    disabled={isPending}
                    items={Object.fromEntries(available.map((c) => [c.id, c.full_name]))}
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Add an authorizer…" />
                    </SelectTrigger>
                    <SelectContent>
                      {available.map((c) => (
                        <SelectItem key={c.id} value={c.id}>
                          {c.full_name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <Button variant="outline" disabled={!picked || isPending} onClick={handleAddClick}>
                    Add
                  </Button>
                </div>
              )}
            </>
          )}
        </CardContent>
      </Card>

      <AlertDialog open={confirmConflictOpen} onOpenChange={setConfirmConflictOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Add the requester as an authorizer?</AlertDialogTitle>
            <AlertDialogDescription>
              This person raised this requisition — adding them as an authorizer is a conflict of interest. You
              can proceed anyway, or cancel and pick someone else.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                setConfirmConflictOpen(false);
                doAdd(picked);
              }}
            >
              Add anyway
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
