import Link from "next/link";
import { Card, CardAction, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { requireProfile } from "@/lib/auth/session";

export default async function DashboardHome() {
  const profile = await requireProfile();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Dashboard</h1>
        <p className="text-sm text-muted-foreground">
          Track requisitions from submission through payment processing.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle>Start a new requisition</CardTitle>
            <CardDescription>Submit a purchase or payment request for approval.</CardDescription>
            <CardAction>
              <Button render={<Link href="/requisitions/new" />} nativeButton={false} size="sm">
                New requisition
              </Button>
            </CardAction>
          </CardHeader>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>My requisitions</CardTitle>
            <CardDescription>Everything you&apos;ve submitted, and its current status.</CardDescription>
            <CardAction>
              <Button render={<Link href="/requisitions" />} nativeButton={false} size="sm" variant="outline">
                View
              </Button>
            </CardAction>
          </CardHeader>
        </Card>

        {profile.role !== "staff" ? (
          <Card>
            <CardHeader>
              <CardTitle>Pending my approval</CardTitle>
              <CardDescription>Requisitions waiting on your decision.</CardDescription>
              <CardAction>
                <Button render={<Link href="/approvals" />} nativeButton={false} size="sm" variant="outline">
                  Review
                </Button>
              </CardAction>
            </CardHeader>
          </Card>
        ) : null}
      </div>
    </div>
  );
}
