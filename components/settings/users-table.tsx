"use client";

import { useState, useTransition } from "react";
import { KeyRound, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import {
  deleteUser,
  resetUserPassword,
  setUserActive,
  setUserTestMode,
  updateUserRole,
} from "@/app/(dashboard)/settings/users/actions";
import { ROLE_OPTIONS } from "@/lib/roles";
import type { UserRole } from "@/lib/supabase/database.types";

interface UserRow {
  id: string;
  full_name: string;
  email: string;
  role: UserRole;
  department_id: string | null;
  is_active: boolean;
  is_test_user: boolean;
  must_change_password: boolean;
}

export function UsersTable({
  users,
  departments,
}: {
  users: UserRow[];
  departments: { id: string; name: string }[];
}) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Name</TableHead>
          <TableHead>Role</TableHead>
          <TableHead>Department</TableHead>
          <TableHead>Account setup</TableHead>
          <TableHead>Active</TableHead>
          <TableHead>Test mode</TableHead>
          <TableHead className="w-20" />
        </TableRow>
      </TableHeader>
      <TableBody>
        {users.map((user) => (
          <UserTableRow key={user.id} user={user} departments={departments} />
        ))}
      </TableBody>
    </Table>
  );
}

function UserTableRow({
  user,
  departments,
}: {
  user: UserRow;
  departments: { id: string; name: string }[];
}) {
  const [isPending, startTransition] = useTransition();
  const [confirmDeleteOpen, setConfirmDeleteOpen] = useState(false);
  const [confirmResetOpen, setConfirmResetOpen] = useState(false);

  function handleDelete() {
    setConfirmDeleteOpen(false);
    startTransition(async () => {
      const result = await deleteUser(user.id);
      if (result.error) toast.error(result.error);
      else toast.success(`"${user.full_name}" deleted`);
    });
  }

  function handleResetPassword() {
    setConfirmResetOpen(false);
    startTransition(async () => {
      const result = await resetUserPassword(user.id);
      if (result.error) toast.error(result.error);
      else toast.success(`New temporary password emailed to ${user.full_name}`);
    });
  }

  return (
    <TableRow>
      <TableCell>
        <div className="font-medium">{user.full_name}</div>
        <div className="text-xs text-muted-foreground">{user.email}</div>
      </TableCell>
      <TableCell>
        <Select
          value={user.role}
          onValueChange={(role) => {
            if (!role) return;
            startTransition(async () => {
              await updateUserRole(user.id, role as UserRole, user.department_id);
            });
          }}
          disabled={isPending}
          items={Object.fromEntries(ROLE_OPTIONS.map((o) => [o.value, o.label]))}
        >
          <SelectTrigger className="w-44">
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
      </TableCell>
      <TableCell>
        <Select
          value={user.department_id ?? "none"}
          onValueChange={(value) => {
            startTransition(async () => {
              await updateUserRole(user.id, user.role, value === "none" || !value ? null : value);
            });
          }}
          disabled={isPending}
          items={{ none: "No department", ...Object.fromEntries(departments.map((d) => [d.id, d.name])) }}
        >
          <SelectTrigger className="w-44">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="none">No department</SelectItem>
            {departments.map((d) => (
              <SelectItem key={d.id} value={d.id}>
                {d.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </TableCell>
      <TableCell>
        {user.must_change_password ? (
          <Badge variant="secondary">Inactive &mdash; hasn&apos;t signed in yet</Badge>
        ) : (
          <Badge>Active</Badge>
        )}
      </TableCell>
      <TableCell>
        <div className="flex items-center gap-2">
          <Switch
            checked={user.is_active}
            disabled={isPending}
            onCheckedChange={(checked) => startTransition(() => setUserActive(user.id, checked))}
          />
          {!user.is_active ? <Badge variant="secondary">Disabled</Badge> : null}
        </div>
      </TableCell>
      <TableCell>
        <div className="flex items-center gap-2">
          <Switch
            checked={user.is_test_user}
            disabled={isPending}
            onCheckedChange={(checked) => startTransition(() => setUserTestMode(user.id, checked))}
          />
          {user.is_test_user ? <Badge variant="secondary">Test</Badge> : null}
        </div>
      </TableCell>
      <TableCell>
        <div className="flex items-center gap-1">
          <AlertDialog open={confirmResetOpen} onOpenChange={setConfirmResetOpen}>
            <AlertDialogTrigger
              render={<Button variant="ghost" size="icon" className="size-7" disabled={isPending} />}
            >
              <KeyRound className="size-4" />
            </AlertDialogTrigger>
            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>
                  {user.must_change_password ? "Resend account details" : "Reset password"} for {user.full_name}?
                </AlertDialogTitle>
                <AlertDialogDescription>
                  {user.must_change_password
                    ? "Generates a new temporary password and emails them their sign-in details again."
                    : "Generates a new temporary password and emails it to them. They'll be required to set a new password the next time they sign in."}
                </AlertDialogDescription>
              </AlertDialogHeader>
              <AlertDialogFooter>
                <AlertDialogCancel>Cancel</AlertDialogCancel>
                <AlertDialogAction disabled={isPending} onClick={handleResetPassword}>
                  Send
                </AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>

          <AlertDialog open={confirmDeleteOpen} onOpenChange={setConfirmDeleteOpen}>
            <AlertDialogTrigger render={<Button variant="ghost" size="icon" className="size-7" disabled={isPending} />}>
              <Trash2 className="size-4" />
            </AlertDialogTrigger>
            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>Delete {user.full_name}?</AlertDialogTitle>
                <AlertDialogDescription>
                  This can&apos;t be undone. A user with requisition history (submitted, approved, uploaded, etc.)
                  can&apos;t be deleted — disable them instead.
                </AlertDialogDescription>
              </AlertDialogHeader>
              <AlertDialogFooter>
                <AlertDialogCancel>Cancel</AlertDialogCancel>
                <AlertDialogAction variant="destructive" disabled={isPending} onClick={handleDelete}>
                  Delete
                </AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>
        </div>
      </TableCell>
    </TableRow>
  );
}
