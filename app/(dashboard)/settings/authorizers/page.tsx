import { createClient } from "@/lib/supabase/server";
import { AuthorizerPoolPanel } from "@/components/settings/authorizer-pool-panel";
import { MinAuthorizerCountCard } from "@/components/settings/min-authorizer-count-card";
import { AuthorizationMethodsPanel } from "@/components/settings/authorization-methods-panel";
import { AssistantDirectRoutingCard } from "@/components/settings/assistant-direct-routing-card";

export default async function AuthorizersSettingsPage() {
  const supabase = await createClient();
  const [{ data: poolRaw }, { data: allProfiles }, { data: minCountRow }, { data: methodsRaw }, { data: routingRow }] =
    await Promise.all([
      supabase.from("authorizer_pool").select("user_id"),
      supabase.from("profiles").select("id, full_name, role").eq("is_active", true).order("full_name"),
      supabase.from("app_settings").select("value").eq("key", "min_authorizer_count").maybeSingle(),
      supabase.from("authorization_methods").select("id, label").order("sort_order"),
      supabase.from("app_settings").select("value").eq("key", "assistant_finance_direct_routing").maybeSingle(),
    ]);

  const poolIds = new Set((poolRaw ?? []).map((p) => p.user_id));
  const members = (allProfiles ?? []).filter((p) => poolIds.has(p.id)).map((p) => ({ id: p.id, full_name: p.full_name }));
  // The active Director is already always an eligible authorizer
  // automatically — exclude them from the pool picker so nobody adds a
  // no-op entry.
  const candidates = (allProfiles ?? [])
    .filter((p) => !poolIds.has(p.id) && p.role !== "director")
    .map((p) => ({ id: p.id, full_name: p.full_name }));

  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">
        The active Director is always an eligible authorizer automatically. Anyone else — internal staff or a
        Board member — needs to be added to the pool below before they can be selected as an authorizer on a
        requisition.
      </p>
      <AuthorizerPoolPanel members={members} candidates={candidates} />
      <MinAuthorizerCountCard initialCount={Number(minCountRow?.value ?? 2)} />
      <AuthorizationMethodsPanel methods={methodsRaw ?? []} />
      <AssistantDirectRoutingCard
        initialValue={routingRow?.value === "direct" ? "direct" : "requires_accountant_approval"}
      />
    </div>
  );
}
