"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { setDashboardAnalyticsSettings } from "@/app/(dashboard)/settings/approval-rules/actions";
import { ANALYTICS_ROLE_CHOICES } from "@/lib/analytics";
import { ROLE_LABELS } from "@/lib/roles";
import type { UserRole } from "@/lib/supabase/database.types";

export function DashboardAnalyticsCard({
  initialRoles,
  initialOverdueDays,
  initialInvoiceOverdueDays,
}: {
  initialRoles: UserRole[];
  initialOverdueDays: number;
  initialInvoiceOverdueDays: number;
}) {
  const [roles, setRoles] = useState<UserRole[]>(initialRoles);
  const [overdueDays, setOverdueDays] = useState(String(initialOverdueDays));
  const [invoiceDays, setInvoiceDays] = useState(String(initialInvoiceOverdueDays));
  const [isPending, startTransition] = useTransition();

  const dirty =
    roles.length !== initialRoles.length ||
    roles.some((r) => !initialRoles.includes(r)) ||
    overdueDays !== String(initialOverdueDays) ||
    invoiceDays !== String(initialInvoiceOverdueDays);

  function toggle(role: UserRole, checked: boolean) {
    setRoles((prev) => (checked ? [...prev, role] : prev.filter((r) => r !== role)));
  }

  function handleSave() {
    startTransition(async () => {
      const result = await setDashboardAnalyticsSettings(roles, Number(overdueDays), Number(invoiceDays));
      if (result.error) toast.error(result.error);
      else toast.success("Dashboard analytics settings saved");
    });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Dashboard analytics</CardTitle>
        <CardDescription>
          Choose who sees the analytics section on the dashboard (totals, turnaround time, charts and the
          longest-open requisitions). Admins always see it. What each role sees is fixed to what&apos;s relevant to
          them, as shown below — nobody sees more than that.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-5">
        <div className="grid gap-3 sm:grid-cols-2">
          {ANALYTICS_ROLE_CHOICES.map((choice) => (
            <div key={choice.role} className="flex items-start gap-2">
              <Checkbox
                id={`analytics-role-${choice.role}`}
                className="mt-0.5"
                checked={roles.includes(choice.role)}
                disabled={isPending}
                onCheckedChange={(c) => toggle(choice.role, c === true)}
              />
              <Label htmlFor={`analytics-role-${choice.role}`} className="block font-normal leading-snug">
                {ROLE_LABELS[choice.role]}
                <span className="block text-xs text-muted-foreground">{choice.scope}</span>
              </Label>
            </div>
          ))}
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="analytics-overdue-days">Overdue after (days at a review or payment stage)</Label>
            <Input
              id="analytics-overdue-days"
              type="number"
              min={1}
              max={365}
              value={overdueDays}
              disabled={isPending}
              onChange={(e) => setOverdueDays(e.target.value)}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="analytics-invoice-days">Awaiting invoice flagged after (days)</Label>
            <Input
              id="analytics-invoice-days"
              type="number"
              min={1}
              max={365}
              value={invoiceDays}
              disabled={isPending}
              onChange={(e) => setInvoiceDays(e.target.value)}
            />
          </div>
        </div>

        <Button disabled={!dirty || isPending} onClick={handleSave}>
          Save
        </Button>
      </CardContent>
    </Card>
  );
}
