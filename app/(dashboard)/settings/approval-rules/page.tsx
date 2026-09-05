import { createClient } from "@/lib/supabase/server";
import { StageModeCard } from "@/components/settings/stage-mode-card";
import { DirectorAuthorizationCard } from "@/components/settings/director-authorization-card";

export default async function ApprovalRulesSettingsPage() {
  const supabase = await createClient();
  const [{ data: config }, { data: directorAuthModeRow }, { data: thresholds }] = await Promise.all([
    supabase.from("approval_stage_config").select("stage_key, mode, quorum_count").is("department_id", null),
    supabase.from("app_settings").select("value").eq("key", "director_auth_mode").maybeSingle(),
    supabase.from("director_auth_thresholds").select("currency, threshold_amount").order("currency"),
  ]);

  const financeConfig = config?.find((c) => c.stage_key === "finance");
  const directorConfig = config?.find((c) => c.stage_key === "director");
  const directorAuthMode = directorAuthModeRow?.value === "amount_threshold" ? "amount_threshold" : "accountant_discretion";

  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">
        These are the global defaults. Departments can override the department-review rule individually from
        Settings &rarr; Departments. In every case, if a stage has only one eligible approver, their decision
        alone always resolves it.
      </p>

      <StageModeCard
        stageKey="finance"
        title="Finance review"
        description="Applies to the Finance Accountant plus anyone they add to a requisition's review group."
        initialMode={financeConfig?.mode ?? "first_approver"}
        initialQuorum={financeConfig?.quorum_count ?? null}
      />

      <StageModeCard
        stageKey="director"
        title="Director authorization"
        description="Applies to everyone with the Director role."
        initialMode={directorConfig?.mode ?? "first_approver"}
        initialQuorum={directorConfig?.quorum_count ?? null}
      />

      <DirectorAuthorizationCard initialMode={directorAuthMode} thresholds={thresholds ?? []} />
    </div>
  );
}
