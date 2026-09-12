"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { setMinAuthorizerCount } from "@/app/(dashboard)/settings/authorizers/actions";

export function MinAuthorizerCountCard({ initialCount }: { initialCount: number }) {
  const [count, setCount] = useState(initialCount.toString());
  const [isPending, startTransition] = useTransition();

  function handleSave() {
    const value = Number(count);
    if (!value || value < 1 || value > 4) {
      toast.error("Enter a number between 1 and 4.");
      return;
    }
    startTransition(async () => {
      const result = await setMinAuthorizerCount(value);
      if (result.error) toast.error(result.error);
      else toast.success("Saved");
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Minimum authorizers required</CardTitle>
        <CardDescription>
          The Finance Accountant must select at least this many authorizers before a requisition can be cleared
          for authorization.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex gap-2">
        <Input
          type="number"
          min={1}
          max={4}
          value={count}
          onChange={(e) => setCount(e.target.value)}
          className="w-24"
        />
        <Button variant="outline" disabled={isPending} onClick={handleSave}>
          Save
        </Button>
      </CardContent>
    </Card>
  );
}
