import { createClient } from "@/lib/supabase/server";
import { InviteUserDialog } from "@/components/settings/invite-user-dialog";
import { UsersTable } from "@/components/settings/users-table";

export default async function UsersSettingsPage() {
  const supabase = await createClient();

  const [{ data: users }, { data: departments }] = await Promise.all([
    supabase.from("profiles").select("id, full_name, email, role, department_id, is_active").order("full_name"),
    supabase.from("departments").select("id, name").eq("is_active", true).order("name"),
  ]);

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <InviteUserDialog departments={departments ?? []} />
      </div>
      <UsersTable users={users ?? []} departments={departments ?? []} />
    </div>
  );
}
