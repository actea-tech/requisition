import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireProfile } from "@/lib/auth/session";
import { canConsolidate } from "@/lib/roles";
import { ConsolidateForm, type ReadyRequisition } from "@/components/requisitions/consolidate-form";

// Whole days since a timestamp, as of when the page is rendered.
function daysSince(iso: string) {
  return Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000));
}

export default async function ConsolidatePaymentsPage() {
  const profile = await requireProfile();
  if (!canConsolidate(profile.role)) notFound();
  const supabase = await createClient();

  const [{ data: readyRaw }, { data: lockedRaw }, { data: profiles }] = await Promise.all([
    supabase
      .from("requisitions")
      .select("id, requisition_number, purpose, amount, currency, requester_id, stage_entered_at")
      .eq("status", "approved_for_payment")
      // Test and real requisitions are never combined; admins can see both, so only list the kind they work in.
      .eq("is_test", profile.is_test_user)
      .neq("requisition_kind", "consolidated")
      .or("cancellation_status.is.null,cancellation_status.neq.requested")
      .order("stage_entered_at"),
    supabase.from("requisition_consolidation_items").select("requisition_id"),
    supabase.from("profiles").select("id, full_name"),
  ]);

  // Already part of a consolidated requisition: not available again.
  const locked = new Set((lockedRaw ?? []).map((l) => l.requisition_id));
  const ready = (readyRaw ?? []).filter((r) => !locked.has(r.id));

  const { data: payeesRaw } =
    ready.length > 0
      ? await supabase
          .from("requisition_payees")
          .select("requisition_id, payee_name, sort_order")
          .in(
            "requisition_id",
            ready.map((r) => r.id),
          )
          .order("sort_order")
      : { data: [] };

  const nameById = new Map((profiles ?? []).map((p) => [p.id, p.full_name]));
  const payeesByRequisition = new Map<string, string[]>();
  for (const p of payeesRaw ?? []) {
    if (!p.payee_name) continue;
    payeesByRequisition.set(p.requisition_id, [...(payeesByRequisition.get(p.requisition_id) ?? []), p.payee_name]);
  }

  const rows: ReadyRequisition[] = ready.map((r) => ({
    id: r.id,
    requisition_number: r.requisition_number,
    purpose: r.purpose,
    amount: r.amount ?? 0,
    currency: r.currency,
    requesterName: nameById.get(r.requester_id) ?? "Unknown",
    payees: payeesByRequisition.get(r.id) ?? [],
    daysWaiting: daysSince(r.stage_entered_at),
  }));

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold">Consolidate payments</h1>
        <p className="text-sm text-muted-foreground">
          Combine requisitions that are ready to pay into one, so a single bank transaction or cheque can pay
          them all. The total is worked out for you. The combined requisition then goes for authorization (or
          straight to payment, if you choose) like any other, and paying it pays every requisition in it.
        </p>
      </div>
      <ConsolidateForm rows={rows} />
    </div>
  );
}
