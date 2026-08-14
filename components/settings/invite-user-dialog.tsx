"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { inviteUser } from "@/app/(dashboard)/settings/users/actions";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { ROLE_OPTIONS } from "@/lib/roles";

export function InviteUserDialog({ departments }: { departments: { id: string; name: string }[] }) {
  const [open, setOpen] = useState(false);
  const [role, setRole] = useState("staff");
  const [departmentId, setDepartmentId] = useState<string>("");
  const [state, formAction, isPending] = useActionState(inviteUser, { error: null });
  const submittedRef = useRef(false);

  useEffect(() => {
    if (submittedRef.current && !isPending && !state.error) {
      submittedRef.current = false;
      setOpen(false);
      setRole("staff");
      setDepartmentId("");
    }
  }, [isPending, state.error]);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button />}>Invite user</DialogTrigger>
      <DialogContent>
        <form
          action={(formData) => {
            submittedRef.current = true;
            formAction(formData);
          }}
        >
          <DialogHeader>
            <DialogTitle>Invite a user</DialogTitle>
            <DialogDescription>
              They&apos;ll get an email with a link to set their password. No public sign-up — every account is
              created here.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-4">
            <div className="space-y-1.5">
              <Label htmlFor="full_name">Full name</Label>
              <Input id="full_name" name="full_name" required />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="email">Email</Label>
              <Input id="email" name="email" type="email" required />
            </div>
            <div className="space-y-1.5">
              <Label>Role</Label>
              <Select
                value={role}
                onValueChange={(value) => setRole(value ?? "staff")}
                items={Object.fromEntries(ROLE_OPTIONS.map((o) => [o.value, o.label]))}
              >
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {ROLE_OPTIONS.map((opt) => (
                    <SelectItem key={opt.value} value={opt.value}>
                      {opt.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <input type="hidden" name="role" value={role} />
            </div>
            <div className="space-y-1.5">
              <Label>Department</Label>
              <Select
                value={departmentId}
                onValueChange={(value) => setDepartmentId(value ?? "")}
                items={Object.fromEntries(departments.map((d) => [d.id, d.name]))}
              >
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="No department" />
                </SelectTrigger>
                <SelectContent>
                  {departments.map((d) => (
                    <SelectItem key={d.id} value={d.id}>
                      {d.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <input type="hidden" name="department_id" value={departmentId} />
            </div>
            {state.error ? <p className="text-sm text-destructive">{state.error}</p> : null}
          </div>

          <DialogFooter>
            <Button type="submit" disabled={isPending}>
              {isPending ? "Sending invite…" : "Send invite"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
