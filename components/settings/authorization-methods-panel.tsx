"use client";

import { useState, useTransition } from "react";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { createAuthorizationMethod, deleteAuthorizationMethod } from "@/app/(dashboard)/settings/authorizers/actions";

interface Method {
  id: string;
  label: string;
}

export function AuthorizationMethodsPanel({ methods }: { methods: Method[] }) {
  const [isPending, startTransition] = useTransition();
  const [label, setLabel] = useState("");
  const [error, setError] = useState<string | null>(null);

  function handleAdd() {
    const trimmed = label.trim();
    if (!trimmed) return;
    startTransition(async () => {
      const result = await createAuthorizationMethod(trimmed);
      if (result.error) setError(result.error);
      else {
        setError(null);
        setLabel("");
      }
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Authorization methods</CardTitle>
        <CardDescription>
          Options an authorizer picks from when approving (e.g. &ldquo;Signed Cheque&rdquo;, &ldquo;Approved
          Online Transaction&rdquo;).
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {methods.length === 0 ? (
          <p className="text-sm text-muted-foreground">No methods yet — add one below.</p>
        ) : (
          <ul className="space-y-1.5">
            {methods.map((m) => (
              <li key={m.id} className="flex items-center justify-between rounded-md border px-3 py-1.5 text-sm">
                {m.label}
                <Button
                  variant="ghost"
                  size="icon-sm"
                  disabled={isPending}
                  onClick={() => startTransition(() => deleteAuthorizationMethod(m.id))}
                >
                  <Trash2 className="size-4" />
                </Button>
              </li>
            ))}
          </ul>
        )}

        <div className="flex items-start gap-2">
          <div>
            <Input
              placeholder="e.g. Bank Transfer"
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              className="w-64"
            />
            {error ? <p className="mt-1 text-sm text-destructive">{error}</p> : null}
          </div>
          <Button variant="outline" disabled={isPending || !label.trim()} onClick={handleAdd}>
            Add
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
