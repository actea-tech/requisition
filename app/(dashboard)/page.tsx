import Link from "next/link";
import { Card, CardAction, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { requireProfile } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

export default async function DashboardHome() {
  const profile = await requireProfile();
  const supabase = await createClient();

  const [{ count: myCount }, { data: pendingIds }, { count: myActionCount }] = await Promise.all([
    supabase.from("requisitions").select("id", { count: "exact", head: true }).eq("requester_id", profile.id),
    supabase.rpc("get_pending_approval_requisition_ids", { p_user_id: profile.id }),
    // Requisitions returned straight back to them — easy to miss since
    // nothing else on the dashboard calls it out.
    supabase
      .from("requisitions")
      .select("id", { count: "exact", head: true })
      .eq("requester_id", profile.id)
      .eq("status", "returned")
      .eq("return_to", "requester"),
  ]);
  const pendingCount = pendingIds?.length ?? 0;

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
            <CardTitle className="flex items-center gap-2">
              My requisitions <span className="text-muted-foreground">({myCount ?? 0})</span>
              {myActionCount ? <Badge variant="destructive">{myActionCount} returned</Badge> : null}
            </CardTitle>
            <CardDescription>Everything you&apos;ve submitted, and its current status.</CardDescription>
            <CardAction>
              <Button render={<Link href="/requisitions" />} nativeButton={false} size="sm" variant="outline">
                View
              </Button>
            </CardAction>
          </CardHeader>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>
              Pending my approval <span className="text-muted-foreground">({pendingCount ?? 0})</span>
            </CardTitle>
            <CardDescription>Requisitions waiting on your decision.</CardDescription>
            <CardAction>
              <Button render={<Link href="/approvals" />} nativeButton={false} size="sm" variant="outline">
                Review
              </Button>
            </CardAction>
          </CardHeader>
        </Card>
      </div>
    </div>
  );
}
