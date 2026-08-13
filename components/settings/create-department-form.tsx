"use client";

import { useActionState, useRef } from "react";
import { createDepartment } from "@/app/(dashboard)/settings/departments/actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

export function CreateDepartmentForm() {
  const formRef = useRef<HTMLFormElement>(null);
  const [state, formAction, isPending] = useActionState(createDepartment, { error: null });

  return (
    <form
      ref={formRef}
      action={async (formData) => {
        await formAction(formData);
        formRef.current?.reset();
      }}
      className="flex items-start gap-2"
    >
      <div>
        <Input name="name" placeholder="e.g. Finance, Programs, IT" className="w-64" required />
        {state.error ? <p className="mt-1 text-sm text-destructive">{state.error}</p> : null}
      </div>
      <Button type="submit" disabled={isPending}>
        Add department
      </Button>
    </form>
  );
}
