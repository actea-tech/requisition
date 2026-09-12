"use client";

import { useState, useTransition } from "react";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { addToAuthorizerPool, removeFromAuthorizerPool } from "@/app/(dashboard)/settings/authorizers/actions";

interface Person {
  id: string;
  full_name: string;
}

export function AuthorizerPoolPanel({ members, candidates }: { members: Person[]; candidates: Person[] }) {
  const [isPending, startTransition] = useTransition();
  const [picked, setPicked] = useState("");

  return (
    <Card>
      <CardHeader>
        <CardTitle>Authorizer pool</CardTitle>
        <CardDescription>
          Who else (besides the Director) can be selected as an authorizer on a requisition.
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
                  disabled={isPending}
                  onClick={() => startTransition(() => removeFromAuthorizerPool(m.id))}
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
                await addToAuthorizerPool(picked);
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
