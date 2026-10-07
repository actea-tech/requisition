"use client";

import { useState, useTransition } from "react";
import { ArrowDown, ArrowUp, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Label } from "@/components/ui/label";
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
import {
  addRequisitionAuthorizer,
  moveRequisitionAuthorizer,
  removeRequisitionAuthorizer,
  setAuthorizersOrderedAction,
} from "@/app/(dashboard)/requisitions/[id]/actions";

interface Person {
  id: string;
  full_name: string;
}

const MAX_AUTHORIZERS = 4;

export function AuthorizerGroupPanel({
  requisitionId,
  members,
  ordered,
  approvedIds,
  orderEditable,
  outForAuthorization,
  candidates,
  requesterId,
  disabled = false,
}: {
  requisitionId: string;
  /** In the order they were selected (which is the sequence when `ordered`). */
  members: Person[];
  /** Authorize one after another, in the listed order, instead of all at once in any order. */
  ordered: boolean;
  approvedIds: string[];
  /** The sequence can still be set/reordered (Finance review, or out for authorization). */
  orderEditable: boolean;
  /** Already notified and awaiting authorizers' decisions. */
  outForAuthorization: boolean;
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
  const approved = new Set(approvedIds);
  // The order itself can only be switched before anyone has authorized.
  const canToggleOrder = orderEditable && approved.size === 0;
  const nextUpId = ordered && outForAuthorization ? members.find((m) => !approved.has(m.id))?.id : undefined;

  function doAdd(userId: string) {
    startTransition(async () => {
      const result = await addRequisitionAuthorizer(requisitionId, userId);
      if (result.error) toast.error(result.error);
      setPicked("");
    });
  }

  function doRemove(userId: string) {
    startTransition(async () => {
      const result = await removeRequisitionAuthorizer(requisitionId, userId);
      if (result.error) toast.error(result.error);
    });
  }

  function doMove(userId: string, direction: -1 | 1) {
    startTransition(async () => {
      const result = await moveRequisitionAuthorizer(requisitionId, userId, direction);
      if (result.error) toast.error(result.error);
    });
  }

  function doSetOrdered(next: boolean) {
    startTransition(async () => {
      const result = await setAuthorizersOrderedAction(requisitionId, next);
      if (result.error) toast.error(result.error);
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
            Select 1–4 people to authorize this payment — nobody is selected for you, so include the Director
            if they should authorize. All of them must approve before it moves to payment processing. By
            default they&apos;re all notified at once and can authorize in any order; tick &ldquo;Authorize in
            sequence&rdquo; to have them go one after another in the order listed. You can add another authorizer
            later — even after it&apos;s fully authorized or already at Payment Processing — which reopens it until
            they&apos;ve authorized too. Anyone who hasn&apos;t authorized yet can still be removed or reordered;
            once someone has authorized they stay.
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
              {canToggleOrder ? (
                <div className="flex items-start gap-2 rounded-md border p-3">
                  <Checkbox
                    id="authorizers-ordered"
                    checked={ordered}
                    disabled={isPending}
                    onCheckedChange={(c) => doSetOrdered(c === true)}
                  />
                  <Label htmlFor="authorizers-ordered" className="block text-sm font-normal leading-snug">
                    <span className="font-medium">Authorize in sequence</span>
                    <span className="block text-xs text-muted-foreground">
                      The first authorizer must authorize before the second is notified and can authorize, and
                      so on, in the order listed below. Off: everyone is notified at once, in any order.
                    </span>
                  </Label>
                </div>
              ) : ordered ? (
                <p className="text-xs text-muted-foreground">
                  Authorizing in sequence, in the order listed — it can&apos;t be switched off once an authorizer
                  has authorized, but anyone who hasn&apos;t authorized yet can still be moved.
                </p>
              ) : null}

              {members.length === 0 ? (
                <p className="text-sm text-muted-foreground">No authorizers selected yet.</p>
              ) : (
                <ul className="space-y-1.5">
                  {members.map((m, index) => {
                    const isApproved = approved.has(m.id);
                    const prevApproved = index > 0 && approved.has(members[index - 1].id);
                    const nextApproved = index < members.length - 1 && approved.has(members[index + 1].id);
                    return (
                      <li
                        key={m.id}
                        className="flex items-center justify-between gap-2 rounded-md border px-3 py-1.5 text-sm"
                      >
                        <span className="flex items-center gap-2">
                          {ordered ? (
                            <span className="flex size-5 shrink-0 items-center justify-center rounded-full bg-muted text-[11px] font-semibold text-muted-foreground">
                              {index + 1}
                            </span>
                          ) : null}
                          {m.full_name}
                          {isApproved ? <Badge variant="success">Authorized</Badge> : null}
                          {m.id === nextUpId ? <Badge variant="warning">Up next</Badge> : null}
                        </span>
                        <span className="flex items-center">
                          {ordered && orderEditable ? (
                            <>
                              <Button
                                variant="ghost"
                                size="icon-sm"
                                aria-label="Move up"
                                disabled={isPending || index === 0 || isApproved || prevApproved}
                                onClick={() => doMove(m.id, -1)}
                              >
                                <ArrowUp className="size-4" />
                              </Button>
                              <Button
                                variant="ghost"
                                size="icon-sm"
                                aria-label="Move down"
                                disabled={isPending || index === members.length - 1 || isApproved || nextApproved}
                                onClick={() => doMove(m.id, 1)}
                              >
                                <ArrowDown className="size-4" />
                              </Button>
                            </>
                          ) : null}
                {isApproved ? null : (
                            <Button
                              variant="ghost"
                              size="icon-sm"
                              aria-label="Remove authorizer"
                              disabled={isPending}
                              onClick={() => doRemove(m.id)}
                            >
                              <Trash2 className="size-4" />
                            </Button>
                          )}
                        </span>
                      </li>
                    );
                  })}
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
