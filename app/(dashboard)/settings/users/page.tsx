import { createClient } from "@/lib/supabase/server";
import { InviteUserDialog } from "@/components/settings/invite-user-dialog";
import { UsersTable } from "@/components/settings/users-table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

export default async function UsersSettingsPage() {
  const supabase = await createClient();

  const [{ data: users }, { data: departments }] = await Promise.all([
    supabase
      .from("profiles")
      .select("id, full_name, email, role, department_id, is_active, is_test_user, must_change_password")
      .order("full_name"),
    supabase.from("departments").select("id, name").eq("is_active", true).order("name"),
  ]);

  const productionUsers = (users ?? []).filter((u) => !u.is_test_user);
  const testUsers = (users ?? []).filter((u) => u.is_test_user);

  return (
    <div className="space-y-4">
      <Tabs defaultValue="production">
        <div className="flex items-center justify-between">
          <InviteUserDialog departments={departments ?? []} />
          <TabsList>
            <TabsTrigger value="production">Production ({productionUsers.length})</TabsTrigger>
            <TabsTrigger value="test">Test ({testUsers.length})</TabsTrigger>
          </TabsList>
        </div>
        <TabsContent value="production">
          <UsersTable users={productionUsers} departments={departments ?? []} />
        </TabsContent>
        <TabsContent value="test">
          <UsersTable users={testUsers} departments={departments ?? []} />
        </TabsContent>
      </Tabs>
    </div>
  );
}
