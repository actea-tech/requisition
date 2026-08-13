"use client";

import { useTransition } from "react";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { setUserActive, updateUserRole } from "@/app/(dashboard)/settings/users/actions";
import { ROLE_OPTIONS } from "@/lib/roles";
import type { UserRole } from "@/lib/supabase/database.types";

interface UserRow {
  id: string;
  full_name: string;
  email: string;
  role: UserRole;
  department_id: string | null;
  is_active: boolean;
}

export function UsersTable({
  users,
  departments,
}: {
  users: UserRow[];
  departments: { id: string; name: string }[];
}) {
  const [isPending, startTransition] = useTransition();

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Name</TableHead>
          <TableHead>Role</TableHead>
          <TableHead>Department</TableHead>
          <TableHead>Active</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {users.map((user) => (
          <TableRow key={user.id}>
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
              <div className="flex items-center gap-2">
                <Switch
                  checked={user.is_active}
                  disabled={isPending}
                  onCheckedChange={(checked) => startTransition(() => setUserActive(user.id, checked))}
                />
                {!user.is_active ? <Badge variant="secondary">Disabled</Badge> : null}
              </div>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
