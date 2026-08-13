import { createClient } from "@/lib/supabase/server";
import { DepartmentCard } from "@/components/settings/department-card";
import { CreateDepartmentForm } from "@/components/settings/create-department-form";
import type { ApprovalMode } from "@/lib/supabase/database.types";

export default async function DepartmentsSettingsPage() {
  const supabase = await createClient();

  const [{ data: departments }, { data: heads }, { data: profiles }, { data: stageConfig }] = await Promise.all([
    supabase.from("departments").select("id, name, is_active").order("name"),
    supabase.from("department_heads").select("department_id, user_id"),
    supabase.from("profiles").select("id, full_name, email").eq("is_active", true).order("full_name"),
    supabase.from("approval_stage_config").select("department_id, mode, quorum_count").eq("stage_key", "department"),
  ]);

  const profileById = new Map((profiles ?? []).map((p) => [p.id, p]));
  const globalMode: ApprovalMode = stageConfig?.find((c) => c.department_id === null)?.mode ?? "first_approver";

  return (
    <div className="space-y-6">
      <CreateDepartmentForm />

      <div className="space-y-4">
        {(departments ?? []).map((department) => {
          const deptHeads = (heads ?? [])
            .filter((h) => h.department_id === department.id)
            .map((h) => profileById.get(h.user_id))
            .filter((p): p is { id: string; full_name: string; email: string } => Boolean(p));

          const override = stageConfig?.find((c) => c.department_id === department.id) ?? null;

          return (
            <DepartmentCard
              key={department.id}
              department={department}
              heads={deptHeads}
              candidates={profiles ?? []}
              override={override ? { mode: override.mode, quorum_count: override.quorum_count } : null}
              globalMode={globalMode}
            />
          );
        })}

        {(departments ?? []).length === 0 ? (
          <p className="text-sm text-muted-foreground">No departments yet — add one above.</p>
        ) : null}
      </div>
    </div>
  );
}
